# Derive row-level features before any imputation. Scoring data may omit Churn.
add_cell2cell_features <- function(data) {
  required_fields <- c("MonthlyRevenue", "TotalRecurringCharge", "PercChangeMinutes",
                       "MonthlyMinutes", "DroppedCalls", "UniqueSubs", "ActiveSubs")
  missing_fields <- setdiff(required_fields, names(data))
  if (length(missing_fields)) {
    stop("Feature source columns missing: ", paste(missing_fields, collapse = ", "),
         call. = FALSE)
  }
  data$billing_gap <- data$MonthlyRevenue - data$TotalRecurringCharge
  data$UsageChangeMissing <- as.integer(is.na(data$PercChangeMinutes))
  usable_minutes <- which(data$MonthlyMinutes > 0 & data$DroppedCalls >= 0)
  data$DroppedCallRate <- rep(NA_real_, nrow(data))
  data$DroppedCallRate[usable_minutes] <-
    100 * data$DroppedCalls[usable_minutes] / data$MonthlyMinutes[usable_minutes]
  data$InactiveSubs <- data$UniqueSubs - data$ActiveSubs
  data$InactiveSubs[which(data$InactiveSubs < 0)] <- NA
  if ("Churn" %in% names(data)) {
    stopifnot(all(data$Churn %in% c("Yes", "No")))
    data$churn_flag <- as.integer(data$Churn == "Yes")
  }
  data
}

# Fit preprocessing on the analysis data and apply it to the scoring rows.
prepare_cell2cell_fold <- function(analysis, assessment, inputs) {
  stopifnot(all(inputs %in% names(analysis)), all(inputs %in% names(assessment)),
            !any(inputs %in% c("CustomerID", "Churn", "churn_flag")))
  for (field in inputs) {
    values <- analysis[[field]]
    if (is.numeric(values)) {
      median_value <- median(values, na.rm = TRUE)
      if (!is.finite(median_value)) {
        stop("No finite fitting-fold median for ", field, call. = FALSE)
      }
      analysis[[field]][is.na(values)] <- median_value
      assessment[[field]][is.na(assessment[[field]])] <- median_value
    } else {
      # Use observed labels even if either data frame already stores factors.
      values <- as.character(values)
      scoring_values <- as.character(assessment[[field]])
      counts <- sort(table(values), decreasing = TRUE)
      levels_seen <- names(counts)
      if (!length(levels_seen)) {
        stop("No observed fitting-fold categories for ", field, call. = FALSE)
      }
      values[is.na(values)] <- levels_seen[1L]
      scoring_values[!scoring_values %in% levels_seen] <- levels_seen[1L]
      analysis[[field]] <- factor(values, levels = levels_seen)
      assessment[[field]] <- factor(scoring_values, levels = levels_seen)
    }
  }
  list(analysis = analysis, assessment = assessment)
}

cell2cell_feature_groups <- function() {
  benchmark <- c("MonthsInService", "CurrentEquipmentDays", "PercChangeMinutes",
                 "DroppedCalls", "BlockedCalls", "CustomerCareCalls",
                 "MonthlyRevenue", "PercChangeRevenues")
  additional_blocks <- list(
    handset = c("HandsetWebCapable", "HandsetRefurbished", "Handsets",
                "HandsetModels", "HandsetPrice"),
    roaming = "RoamingCalls",
    overage = "OverageMinutes",
    subscriptions = c("UniqueSubs", "ActiveSubs"),
    account_history = c("NewCellphoneUser", "NotNewCellphoneUser",
                        "ReferralsMadeBySubscriber"),
    calling = c("MonthlyMinutes", "DirectorAssistedCalls", "UnansweredCalls",
                "ThreewayCalls", "ReceivedCalls", "OutboundCalls", "InboundCalls",
                "PeakCallsInOut", "OffPeakCallsInOut", "CallForwardingCalls",
                "CallWaitingCalls")
  )
  alternate_fields <- c("TotalRecurringCharge", "DroppedBlockedCalls")
  list(benchmark = benchmark, additional_blocks = additional_blocks,
       alternate_fields = alternate_fields)
}

cell2cell_handoff_predictors <- function() {
  groups <- cell2cell_feature_groups()
  spline <- "splines::ns(MonthsInService, df = 3)"
  interaction <- paste0(spline, ":CurrentEquipmentDays")
  benchmark <- c(spline, setdiff(groups$benchmark, "MonthsInService"), "billing_gap")
  focused <- c(benchmark, groups$additional_blocks$subscriptions, "HandsetWebCapable")
  broader_as_screened <- c(benchmark, unlist(groups$additional_blocks, use.names = FALSE))
  broader_without_price <- setdiff(broader_as_screened, "HandsetPrice")

  raw_fields <- function(terms) {
    c(setdiff(all.vars(reformulate(terms)), "billing_gap"), "TotalRecurringCharge")
  }

  list(
    tenure_interaction = interaction,
    logistic = list(
      benchmark = benchmark,
      focused = focused,
      focused_missing = c(focused, "UsageChangeMissing"),
      focused_both = c(focused, "UsageChangeMissing", interaction),
      broader_as_screened = broader_as_screened,
      broader_without_price = broader_without_price
    ),
    forest = list(
      focused_raw = raw_fields(focused),
      broader_raw = raw_fields(broader_without_price)
    )
  )
}
