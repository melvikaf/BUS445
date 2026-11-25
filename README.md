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
| [03_Variable_Selection.Rmd](03_Variable_Selection.Rmd) | Compares logistic predictor sets on shared training folds using AUC, precision, and lift at 10%, 20%, and 30% outreach capacity. |

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

[03_Variable_Selection.Rmd](03_Variable_Selection.Rmd) contains the feature
definitions, fold preprocessing, and exact focused and broader model formulas.
After joining the cleaned data and split assignments, use
`add_cell2cell_features()` from its Feature engineering section before
imputing predictors. Use `prepare_cell2cell_fold()` on the fitting and
validation rows for each training fold. The focused and broader formulas
are `model_terms$subscriptions_and_web` and `model_terms$all_blocks`.
The EDA notebook reads the same feature definitions.

Keep observed `MonthlyRevenue` and `CustomerID` for the financial handoff.
The revenue exposure in the EDA describes historical churners. Future
campaign impact requires model scores, treatment-effect evidence,
contribution margin, retention duration, and outreach and offer costs.
