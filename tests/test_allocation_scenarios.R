# Run from project root: Rscript tests/test_allocation_scenarios.R
source(file.path("R", "allocation_functions.R"))
forecast_path <- file.path("outputs", "tables", "demand_forecast.csv")
processed_path <- file.path("data", "processed", "healthcare_clean.csv")
if (!file.exists(forecast_path)) stop("Missing test input: ", forecast_path)
if (!file.exists(processed_path)) stop("Missing test input: ", processed_path)
forecasts <- read.csv(forecast_path, stringsAsFactors = FALSE)
cleaned <- read.csv(processed_path, stringsAsFactors = FALSE)
original_forecasts <- forecasts
check <- function(condition, message) {
  if (!isTRUE(condition)) stop("FAIL: ", message, call. = FALSE)
  cat("PASS: ", message, "\n", sep = "")
}
expect_error <- function(expression, pattern, label) {
  value <- tryCatch({ force(expression); NULL }, error = identity)
  check(inherits(value, "error") && grepl(pattern, conditionMessage(value)), label)
}

# A: base case and restoration after other scenarios; irrelevant controls cannot leak.
baseline_settings <- apply_demand_scenario(forecasts, "baseline", 180)
baseline_demand <- calculate_bed_demand(forecasts, cleaned,
  baseline_settings$overall_multiplier, baseline_settings$department_multipliers)
priorities <- default_department_priorities(baseline_demand$department)
baseline <- evaluate_allocation_policy(baseline_demand, 180, priorities)
first_month_rows <- forecasts[as.Date(forecasts$month) == min(as.Date(forecasts$month)), , drop = FALSE]
check(baseline_settings$scenario_label == "Baseline Demand" && baseline_settings$overall_multiplier == 1 &&
  is.null(baseline_settings$department_multipliers) && baseline_settings$capacity == 180,
  "baseline selects original forecast, no demand or department multiplier, and base capacity")
check(identical(baseline_demand$base_forecast, as.numeric(
  first_month_rows$forecast[match(baseline_demand$department, first_month_rows$department)])),
  "baseline forecasts equal the original earliest-month forecasts")
check(sum(baseline$allocated_beds) == 180 && all(baseline$allocated_beds >= 0) &&
  all(baseline$allocated_beds <= baseline$modeled_bed_demand),
  "baseline allocations satisfy capacity and department demand bounds")

increased_settings <- apply_demand_scenario(forecasts, "increased_demand", 180,
  demand_increase_pct = 20, demand_reduction_pct = 45, capacity_reduction_pct = 60,
  surge_department = baseline_demand$department[1], department_multiplier = 2.5)
increased_demand <- calculate_bed_demand(forecasts, cleaned, increased_settings$overall_multiplier,
  increased_settings$department_multipliers)
check(increased_settings$overall_multiplier == 1.2 &&
  sum(increased_demand$modeled_bed_demand) > sum(baseline_demand$modeled_bed_demand),
  "increased demand raises modeled demand exactly once")
restored_settings <- apply_demand_scenario(forecasts, "baseline", 180,
  demand_increase_pct = 80, demand_reduction_pct = 45, capacity_reduction_pct = 60,
  surge_department = baseline_demand$department[1], department_multiplier = 2.5)
restored_demand <- calculate_bed_demand(forecasts, cleaned,
  restored_settings$overall_multiplier, restored_settings$department_multipliers)
restored <- evaluate_allocation_policy(restored_demand, restored_settings$capacity, priorities)
check(identical(baseline_demand, restored_demand) && identical(baseline, restored),
  "switching from increased demand back to baseline restores identical results despite irrelevant controls")
check(identical(forecasts, original_forecasts), "scenario calculations do not mutate the source forecast")

# B/C: global demand and available capacity adjustments.
reduced_demand_settings <- apply_demand_scenario(forecasts, "reduced_demand", 180,
  demand_reduction_pct = 20)
reduced_demand <- calculate_bed_demand(forecasts, cleaned, reduced_demand_settings$overall_multiplier)
check(sum(reduced_demand$modeled_bed_demand) < sum(baseline_demand$modeled_bed_demand),
  "reduced-demand scenario lowers modeled demand")
reduced_capacity_settings <- apply_demand_scenario(forecasts, "reduced_capacity", 180,
  capacity_reduction_pct = 25)
reduced_capacity <- evaluate_allocation_policy(baseline_demand, reduced_capacity_settings$capacity, priorities)
check(reduced_capacity_settings$capacity == 135 && sum(reduced_capacity$allocated_beds) <= 135,
  "reduced-capacity scenario applies the capacity reduction and respects the limit")
changed_capacity_settings <- apply_demand_scenario(forecasts, "baseline", 120,
  demand_increase_pct = 50, capacity_reduction_pct = 75)
changed_capacity <- evaluate_allocation_policy(baseline_demand, changed_capacity_settings$capacity, priorities)
check(sum(changed_capacity$allocated_beds) == 120 && identical(baseline_demand, restored_demand),
  "baseline uses selected base capacity while leaving baseline forecast unchanged")
baseline_again <- evaluate_allocation_policy(baseline_demand, 180, priorities)
check(identical(baseline, baseline_again), "restoring base capacity restores the original baseline allocation")
zero_capacity <- evaluate_allocation_policy(baseline_demand, 0, priorities)
zero_summary <- summarize_scenario_results(zero_capacity)
check(sum(zero_capacity$allocated_beds) == 0 && zero_summary$capacity_utilization_pct == 0,
  "zero capacity produces zero allocation and safe zero utilization")

# D: department surge changes only the selected department.
surge_department <- baseline_demand$department[1]
surge_settings <- apply_demand_scenario(forecasts, "department_surge", 180,
  demand_increase_pct = 90, demand_reduction_pct = 40, capacity_reduction_pct = 70,
  surge_department = surge_department, department_multiplier = 1.5)
surge_demand <- calculate_bed_demand(forecasts, cleaned, surge_settings$overall_multiplier,
  surge_settings$department_multipliers)
other_departments <- surge_demand$department != surge_department
check(surge_demand$adjusted_forecast[surge_demand$department == surge_department] ==
  surge_demand$base_forecast[surge_demand$department == surge_department] * 1.5 &&
  all(surge_demand$adjusted_forecast[other_departments] == surge_demand$base_forecast[other_departments]) &&
  surge_settings$capacity == 180,
  "department surge affects only its selected forecast and ignores unrelated scenario controls")

# E: both allocation policies run on the same inputs and report actual outputs.
policy_results <- compare_allocation_policies(baseline_demand, 180, priorities, minimum_share = 0.10)
check(nrow(policy_results$comparison) == nrow(baseline_demand) &&
  all(policy_results$minimum_floor$minimum_beds <= policy_results$minimum_floor$allocated_beds) &&
  sum(policy_results$weighted$allocated_beds) <= 180 &&
  sum(policy_results$minimum_floor$allocated_beds) <= 180,
  "policy comparison runs both policies on the same baseline demand/capacity and respects the floor")
infeasible_policy <- compare_allocation_policies(baseline_demand, 1, priorities, minimum_share = 1)
check(!is.null(infeasible_policy$minimum_floor_error) &&
  grepl("Minimum allocation conflict", infeasible_policy$minimum_floor_error) &&
  sum(infeasible_policy$weighted$allocated_beds) <= 1,
  "infeasible alternative policy is reported without suppressing the feasible weighted result")
priorities_changed <- priorities
priorities_changed[baseline_demand$department[1]] <- 2
reweighted <- evaluate_allocation_policy(baseline_demand, 180, priorities_changed)
check(reweighted$allocated_beds[1] >= baseline$allocated_beds[1],
  "changing a configured department priority changes allocation according to the model objective")

# Verify the discrete marginal-gain optimizer against exhaustive enumeration
# on a small case, including unequal department priorities.
tiny <- data.frame(department = c("A", "B", "C"), expected_beds = c(3, 3, 3),
  modeled_bed_demand = c(3L, 3L, 3L))
tiny_priorities <- c(A = 1, B = 2, C = 1)
tiny_result <- optimize_bed_allocation(tiny, 4, tiny_priorities)
tiny_allocations <- expand.grid(A = 0:3, B = 0:3, C = 0:3)
tiny_allocations <- tiny_allocations[rowSums(tiny_allocations) <= 4, , drop = FALSE]
tiny_objectives <- apply(tiny_allocations, 1, function(x) {
  sum(tiny_priorities * ((3 - x) / 3)^2)
})
tiny_actual_objective <- sum(tiny_priorities * ((3 - tiny_result$allocated_beds) / 3)^2)
check(abs(tiny_actual_objective - min(tiny_objectives)) < 1e-12,
  "discrete optimizer matches exhaustive global optimum on a small allocation case")

# F: missing, non-finite, invalid capacity, and infeasible policy inputs.
bad_forecasts <- forecasts
bad_forecasts$forecast[1] <- Inf
expect_error(calculate_bed_demand(bad_forecasts, cleaned), "non-finite", "rejects non-finite forecasts")
expect_error(calculate_bed_demand(forecasts[, c("department", "month")], cleaned),
  "missing: forecast", "rejects missing forecast input columns")
expect_error(validate_capacity(-1), "capacity", "rejects negative capacity")
expect_error(validate_capacity(10.5), "capacity", "rejects fractional capacity")
full_floor <- setNames(baseline_demand$modeled_bed_demand, baseline_demand$department)
expect_error(optimize_bed_allocation(baseline_demand, 1, priorities, full_floor),
  "Minimum allocation conflict", "reports conflicting minimum allocations")

cat("All allocation scenario tests passed.\n")
