# BUS 445 — Cell2Cell retention analysis

This project uses the supplied Cell2Cell customer data to explore churn and
compare predictors for prioritizing proactive retention outreach. In the CSV,
`Churn = Yes` means the customer left during the recorded observation period.
`Churn = No` means the customer did not leave during that period.

## Setup

Install R and the two R packages listed in [requirements.txt](requirements.txt).
In the R console, run:

```r
install.packages(c("rmarkdown", "knitr"), repos = "https://cloud.r-project.org")
```

HTML rendering also requires Pandoc 2.8 or newer. RStudio can use its bundled
Pandoc when knitting. For terminal rendering, make Pandoc available on
`PATH` or set `RSTUDIO_PANDOC` to the directory containing its executable.

Place the supplied CSV at `Provided_Data/cell2celltrain.csv` and keep that
source file intact.

## Run the notebooks

Open the notebooks in RStudio and click **Knit**, or run these commands from
the repository root:

```sh
Rscript -e 'rmarkdown::render("01_Data_Cleaning.Rmd")'
Rscript -e 'rmarkdown::render("02_EDA.Rmd")'
Rscript -e 'rmarkdown::render("03_Variable_Selection.Rmd")'
```

| Notebook | What it does |
| --- | --- |
| [01_Data_Cleaning.Rmd](01_Data_Cleaning.Rmd) | Audits data types, missing values, and invalid entries. Writes the cleaned dataset and split manifest. |
| [02_EDA.Rmd](02_EDA.Rmd) | Revisits Milestone 1 assumptions, explores eligible predictors and churn relationships, and checks correlations using training records. |
| [03_Variable_Selection.Rmd](03_Variable_Selection.Rmd) | Screens predictor sets and tests focused refinements and handset-price removal on the shared folds. Provides exact logistic formulas and raw forest lists. |

For macOS RStudio installations with the bundled Pandoc layout, the following
setting makes Pandoc available to terminal renders:

```sh
export RSTUDIO_PANDOC="/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/$(uname -m)"
```

## Shared data for modeling

- [cleaned_data.csv](Generated_Data/cleaned_data.csv) contains 51,047 customer records and the original set of fields after cleaning.
- [split_manifest.csv](Generated_Data/split_manifest.csv) contains one row per `CustomerID`, a `split` of `train` or `test`, and a `cv_fold` of 1–3 for training customers. Test fold values are blank.
- [feature_register.csv](Generated_Data/feature_register.csv) documents original fields, engineered features, eligibility decisions, and preliminary evidence.

Join the files by `CustomerID` and reuse the saved assignments. The split is
stratified by churn with seed 445 and contains 38,285 training customers and
12,762 test customers. For cross-validation, fit preprocessing and the model
on two training folds and score the third. Reserve the test partition for
final evaluation once variable and model choices are locked.

## Modeling handoff

The exact formulas and raw lists are printed in
[03_Variable_Selection.Rmd](03_Variable_Selection.Rmd) and available from the
shared R script. From the repository root:

```r
source("R/preprocessing.R")
specs <- cell2cell_handoff_predictors()

reformulate(specs$logistic$focused_both, response = "churn_flag")
reformulate(specs$logistic$focused_missing, response = "churn_flag")
reformulate(specs$logistic$broader_without_price, response = "churn_flag")
specs$forest$focused_raw
specs$forest$broader_raw
```

- **Logistic regression.** The primary specification adds
  `UsageChangeMissing` and the spline-tenure × equipment-age interaction
  to the original focused terms. It retains both interaction main effects
  and the original subscription counts. The missingness-only version is the
  simpler challenger. The broader challenger omits `HandsetPrice`.
- **Random forest.** The focused and broader raw lists both use numeric
  tenure, numeric equipment age, and fixed charge. A forest can learn
  nonlinear splits and interactions. The team can separately test the
  pre-imputation usage-missingness flag and substitution of billing gap for
  fixed charge. Logistic screening is evidence for which variants to test.
- **Both families.** Use `add_cell2cell_features()` before imputation.
  Within each saved fold, pass fitting rows, assessment rows, and that
  model's predictor fields to `prepare_cell2cell_fold()`. For a logistic
  formula, the predictor fields are obtained with
  `all.vars(reformulate(specs$logistic$focused_both))` (without a response
  argument). Missing numeric values receive fitting-fold medians. Missing
  or unseen categories receive the fitting-fold mode and use the same
  factor levels in both partitions. Keep `CustomerID`, `Churn` and
  `churn_flag` outside predictor lists. The retention-history fields remain
  outside both sets until their timing is verified. For a forest classifier, encode
  `Churn` as a factor with levels `No` and `Yes`, and rank by the
  predicted probability of `Yes`.
- **Evaluation.** Compare AUC, precision and lift on the same assessed
  customers at 10%, 20%, and 30% outreach. Break ties by `CustomerID`.
  BIC is a secondary fit-versus-complexity check for logistic models fitted
  on identical rows and outcomes. Use the reserved test set after the
  team freezes the specification and scoring procedure.

### Preparing one shared validation fold

This example prepares the primary logistic candidate and the focused raw
forest option for fold 1. Each option uses the same customer assignments.

```r
source("R/preprocessing.R")
specs <- cell2cell_handoff_predictors()
cleaned <- read.csv("Generated_Data/cleaned_data.csv", na.strings = c("", "NA"))
manifest <- read.csv("Generated_Data/split_manifest.csv")
training_manifest <- subset(manifest, split == "train")
training <- cleaned[match(training_manifest$CustomerID, cleaned$CustomerID), ]
stopifnot(identical(training$CustomerID, training_manifest$CustomerID))
training <- add_cell2cell_features(training)

validation <- training_manifest$cv_fold == 1
analysis_rows <- training[!validation, ]
assessment_rows <- training[validation, ]
logistic_fields <- all.vars(reformulate(specs$logistic$focused_both))
logistic_fold <- prepare_cell2cell_fold(analysis_rows, assessment_rows, logistic_fields)

forest_fields <- specs$forest$focused_raw
forest_fold <- prepare_cell2cell_fold(analysis_rows, assessment_rows, forest_fields)
forest_x <- forest_fold$analysis[forest_fields]
forest_y <- factor(forest_fold$analysis$Churn, levels = c("No", "Yes"))
forest_validation_x <- forest_fold$assessment[forest_fields]
assessment_ids <- forest_fold$assessment$CustomerID
```

Preserve the observed `MonthlyRevenue` column keyed by `CustomerID`
separately from any imputed model copy. The finance teammate can join the
observed values to later model scores and report revenue coverage.

## Memo-ready findings

Observed training churn peaked at 31.0% at 13–24 months of service, versus
18.6% in the first six months. Among customers with more than 36 months of
service, churn ranged from 15.2% with 0–180-day equipment to 39.0% with
equipment aged 731 days or more. The same 277 training customers lacked
both usage and revenue changes and had 56.7% observed churn, compared with
28.6% among customers with both recorded. These are historical
associations. Scoring-time availability of missingness still requires
verification.

Adding missingness and the tenure-by-equipment interaction to the focused
logistic reference raised validation AUC from 0.612 to 0.617 and 10%
precision from 41.4% to 43.1%. Lift increased from 1.435 to 1.495 at 10%,
1.327 to 1.375 at 20%, and 1.272 to 1.311 at 30%, with gains in all three
folds at each cutoff. The price-free broad challenger had AUC 0.617 and
lift of 1.420, 1.347, and 1.300 across those cutoffs. The original
subscription counts remain in the primary specification. The algebraically
equivalent alternative reproduced the same scores, and gap alone performed
inconsistently across folds.

The training sample contained approximately **$633,652 in recorded monthly
revenue associated with historical churners**, covering 10,980 of 11,033
churners (99.52%). Campaign impact requires treatment-effect evidence,
contribution margin, retained duration, and outreach and offer costs.
The observation window for churn remains unverified. Earlier full-file
exploration limits the independence of the reserved test set. The team
still needs to compare algorithms, agree on outreach capacity, verify
scoring-time inputs, and evaluate the locked model.

# Modelling Workflow

## Logistic Regression

1. **Train and compare models:** Use the three predictor sets from `preprocessing.R` to train three logistic regression models. Evaluate each model using 3-fold cross-validation at 10%, 20%, and 30% outreach capacity.

2. **Select the best model:** Compare the models based on AUC and precision. The selected model is `focused_both`.

3. **Train and test the final model:** Train `focused_both` using the entire training set with a 10% outreach capacity, then evaluate it on the test set.

4. **Save predictions:** The predicted churn probabilities are saved in `predicted_probabilities/logistic_predictions.csv`. Open this file to see each test customer's predicted churn probability and whether they actually churned.

5. **Estimate revenue:** Use the final model to estimate revenue under different business assumptions:

   ```r
   # Fixed outreach capacity
   outreach_capacity <- 0.10

   # Business assumptions to test
   churn_rates <- c(0.15, 0.25, 0.30, 0.40)
   retention_success_rates <- c(0.15, 0.25, 0.35, 0.45)
   contact_costs <- c(2, 3, 4, 5)

   # Retention offer cost
   offer_costs <- c(0, 20, 30, 50)

   # Revenue projection period (months)
   projection_months <- 12
   ```

   The revenue analysis tests all possible combinations of these assumptions, resulting in **256 scenarios**.

   The results are saved in `revenue_scenarios/logistic_revenue_estimates.csv`. Open this file to compare the estimated revenue across scenarios.

## Random Forest

Follow the same workflow for the Random Forest model:

1. Train and compare the models using 3-fold cross-validation at 10%, 20%, and 30% outreach capacity.
2. Select the best model based on AUC and precision. The chosen model is `broader_raw`.
3. Train the selected model using the entire training set and evaluate it on the test set at 10% outreach capacity.
4. Save the test predictions in `predicted_probabilities`.
5. Run the same 256 revenue scenarios using the same business assumptions.

The Random Forest revenue results are saved in `revenue_scenarios`.