# Phase 3: explainable, balanced integer bed allocation.
# Run from the project root: Rscript R/04_optimization.R
source(file.path("R", "allocation_functions.R"))
dir.create(file.path("outputs", "tables"), recursive = TRUE, showWarnings = FALSE)
forecast_path <- file.path("outputs", "tables", "demand_forecast.csv")
processed_path <- file.path("data", "processed", "healthcare_clean.csv")
if (!file.exists(forecast_path)) stop("Required forecast file is missing: ", forecast_path, ". Run R/03_forecasting.R first.")
if (!file.exists(processed_path)) stop("Required processed data file is missing: ", processed_path, ". Run R/01_data_cleaning.R first.")
forecasts <- read.csv(forecast_path, stringsAsFactors = FALSE, check.names = FALSE)
cleaned_data <- read.csv(processed_path, stringsAsFactors = FALSE, check.names = FALSE)
bed_demand <- calculate_bed_demand(forecasts, cleaned_data)
capacity_text <- Sys.getenv("HRDSS_BED_CAPACITY", "180")
capacity_num <- suppressWarnings(as.numeric(capacity_text))
capacity <- validate_capacity(capacity_num)
priorities <- default_department_priorities(bed_demand$department)
allocation <- evaluate_allocation_policy(bed_demand, capacity, priorities, "weighted")
latest_rows <- forecasts[as.Date(forecasts$month) == min(as.Date(forecasts$month)), , drop = FALSE]
latest_rows <- latest_rows[match(allocation$department, latest_rows$department), , drop = FALSE]
for (column in intersect(c("lower80", "upper80", "model"), names(latest_rows))) {
  allocation[[column]] <- latest_rows[[column]]
}
allocation$forecast <- allocation$adjusted_forecast
summary <- summarize_scenario_results(allocation)
write.csv(allocation, file.path("outputs", "tables", "bed_allocation.csv"), row.names = FALSE, na = "")
write.csv(summary, file.path("outputs", "tables", "allocation_summary.csv"), row.names = FALSE, na = "")
cat("Allocation saved. Policy: ", unique(allocation$policy), "; capacity: ", capacity,
    " beds; allocated: ", sum(allocation$allocated_beds), "; unmet demand: ",
    sum(allocation$unmet_beds), " beds.\n", sep = "")
