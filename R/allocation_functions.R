# Shared, dependency-light functions for batch optimization and Shiny scenarios.

default_department_priorities <- function(departments) {
  priorities <- rep(1, length(departments))
  names(priorities) <- departments
  priorities[departments == "General Medicine"] <- 1.10
  priorities
}

validate_capacity <- function(capacity) {
  if (length(capacity) != 1L || is.na(capacity) || !is.finite(capacity) ||
      capacity < 0 || capacity != floor(capacity) || capacity > .Machine$integer.max) {
    stop("Available bed capacity must be a finite, non-negative whole number.", call. = FALSE)
  }
  as.integer(capacity)
}

apply_demand_scenario <- function(forecasts, scenario, base_capacity,
                                  demand_increase_pct = 20, demand_reduction_pct = 20,
                                  capacity_reduction_pct = 25,
                                  surge_department = NULL, department_multiplier = 1.5) {
  base_capacity <- validate_capacity(base_capacity)
  scenario_keys <- c("baseline", "increased_demand", "reduced_demand", "reduced_capacity", "department_surge")
  if (length(scenario) != 1L || is.na(scenario) || !scenario %in% scenario_keys) {
    stop("Select a supported scenario: ", paste(scenario_keys, collapse = ", "), call. = FALSE)
  }
  validate_pct <- function(value, label, maximum = 100) {
    if (length(value) != 1L || is.na(value) || !is.finite(value) || value < 0 || value > maximum) {
      stop(label, " must be between 0 and ", maximum, ".", call. = FALSE)
    }
    value
  }
  scenario_label <- switch(scenario,
    baseline = "Baseline Demand",
    increased_demand = "Increased Demand",
    reduced_demand = "Reduced Demand",
    reduced_capacity = "Reduced Bed Capacity",
    department_surge = "Selected Department Surge")
  overall_multiplier <- 1
  department_multipliers <- NULL
  scenario_capacity <- base_capacity
  if (scenario == "increased_demand") {
    overall_multiplier <- 1 + validate_pct(demand_increase_pct, "Demand increase") / 100
  } else if (scenario == "reduced_demand") {
    overall_multiplier <- 1 - validate_pct(demand_reduction_pct, "Demand reduction") / 100
  } else if (scenario == "reduced_capacity") {
    reduction <- validate_pct(capacity_reduction_pct, "Capacity reduction")
    scenario_capacity <- as.integer(round(base_capacity * (1 - reduction / 100)))
  } else if (scenario == "department_surge") {
    if (!"department" %in% names(forecasts) || length(surge_department) != 1L ||
        is.na(surge_department) || !surge_department %in% forecasts$department) {
      stop("Choose a department present in the forecast for the department surge scenario.", call. = FALSE)
    }
    if (length(department_multiplier) != 1L || is.na(department_multiplier) ||
        !is.finite(department_multiplier) || department_multiplier <= 0) {
      stop("Department surge multiplier must be finite and greater than zero.", call. = FALSE)
    }
    department_multipliers <- setNames(as.numeric(department_multiplier), as.character(surge_department))
  }
  list(
    scenario = scenario,
    scenario_label = scenario_label,
    overall_multiplier = overall_multiplier,
    department_multipliers = department_multipliers,
    base_capacity = base_capacity,
    capacity = scenario_capacity
  )
}

calculate_bed_demand <- function(forecasts, cleaned_data, overall_multiplier = 1,
                                 department_multipliers = NULL) {
  required_forecast <- c("department", "month", "forecast")
  missing_forecast <- setdiff(required_forecast, names(forecasts))
  if (length(missing_forecast)) {
    stop("Forecast input is missing: ", paste(missing_forecast, collapse = ", "), call. = FALSE)
  }
  if (!all(c("department", "length_of_stay") %in% names(cleaned_data))) {
    stop("Processed data must include department and length_of_stay.", call. = FALSE)
  }
  if (!nrow(forecasts) || anyNA(forecasts$department) || any(!nzchar(forecasts$department)) ||
      anyNA(forecasts$month) || anyNA(forecasts$forecast) ||
      any(!is.finite(forecasts$forecast)) || any(forecasts$forecast < 0)) {
    stop("Forecast data contains no rows or missing, non-finite, or negative values.", call. = FALSE)
  }
  month_dates <- as.Date(forecasts$month)
  if (anyNA(month_dates)) stop("Forecast month contains invalid dates.", call. = FALSE)
  latest_month <- min(month_dates)
  latest <- forecasts[month_dates == latest_month, , drop = FALSE]
  if (anyDuplicated(latest$department)) {
    stop("Forecast data must contain one row per department for its earliest month.", call. = FALSE)
  }
  if (anyNA(cleaned_data$department) || any(!nzchar(cleaned_data$department)) ||
      anyNA(cleaned_data$length_of_stay) || any(!is.finite(cleaned_data$length_of_stay)) ||
      any(cleaned_data$length_of_stay < 0)) {
    stop("Processed data contains missing or invalid departments or length-of-stay values.", call. = FALSE)
  }
  departments <- unique(as.character(latest$department))
  all_departments <- unique(as.character(cleaned_data$department))
  absent <- setdiff(departments, all_departments)
  if (length(absent)) stop("No processed length-of-stay data for department(s): ", paste(absent, collapse = ", "), call. = FALSE)
  extra <- setdiff(all_departments, departments)
  if (length(extra)) stop("Forecast is missing department(s) present in processed data: ", paste(extra, collapse = ", "), call. = FALSE)
  if (length(overall_multiplier) != 1L || is.na(overall_multiplier) ||
      !is.finite(overall_multiplier) || overall_multiplier < 0) {
    stop("Overall demand multiplier must be finite and non-negative.", call. = FALSE)
  }
  multipliers <- setNames(rep(1, length(departments)), departments)
  if (!is.null(department_multipliers)) {
    if (is.null(names(department_multipliers)) || any(!names(department_multipliers) %in% departments) ||
        anyNA(department_multipliers) || any(!is.finite(department_multipliers)) ||
        any(department_multipliers <= 0)) {
      stop("Department multipliers must be positive finite values named for forecast departments.", call. = FALSE)
    }
    multipliers[names(department_multipliers)] <- department_multipliers
  }
  los_means <- vapply(departments, function(department) {
    mean(cleaned_data$length_of_stay[cleaned_data$department == department])
  }, numeric(1))
  if (any(!is.finite(los_means)) || any(los_means < 0)) {
    stop("Could not calculate valid mean length of stay for every department.", call. = FALSE)
  }
  forecast_values <- as.numeric(latest$forecast[match(departments, latest$department)]) *
    overall_multiplier * multipliers[departments]
  expected_beds <- forecast_values * los_means[departments] / 30.4375
  if (any(!is.finite(expected_beds)) || any(expected_beds < 0)) {
    stop("Scenario produced non-finite or negative bed demand.", call. = FALSE)
  }
  data.frame(
    department = departments,
    month = as.character(latest_month),
    base_forecast = as.numeric(latest$forecast[match(departments, latest$department)]),
    demand_multiplier = overall_multiplier * multipliers[departments],
    adjusted_forecast = forecast_values,
    mean_los = unname(los_means[departments]),
    expected_beds = expected_beds,
    modeled_bed_demand = ceiling(expected_beds),
    stringsAsFactors = FALSE
  )
}

optimize_bed_allocation <- function(bed_demand, capacity, priorities = NULL,
                                    minimum_beds = NULL, policy_name = "Weighted balanced shortage") {
  capacity <- validate_capacity(capacity)
  required <- c("department", "expected_beds", "modeled_bed_demand")
  absent <- setdiff(required, names(bed_demand))
  if (length(absent) || !nrow(bed_demand)) {
    stop("Bed demand must be a non-empty table containing: ", paste(required, collapse = ", "), call. = FALSE)
  }
  if (anyNA(bed_demand$department) || any(!nzchar(bed_demand$department)) ||
      anyDuplicated(bed_demand$department) || anyNA(bed_demand$expected_beds) ||
      any(!is.finite(bed_demand$expected_beds)) || any(bed_demand$expected_beds < 0) ||
      anyNA(bed_demand$modeled_bed_demand) || any(!is.finite(bed_demand$modeled_bed_demand)) ||
      any(bed_demand$modeled_bed_demand < 0) ||
      any(bed_demand$modeled_bed_demand != floor(bed_demand$modeled_bed_demand))) {
    stop("Bed demand contains missing, invalid, or non-integer modeled demand values.", call. = FALSE)
  }
  departments <- as.character(bed_demand$department)
  demand <- as.integer(bed_demand$modeled_bed_demand)
  if (is.null(priorities)) priorities <- default_department_priorities(departments)
  if (is.null(names(priorities)) || any(!departments %in% names(priorities))) {
    stop("A priority weight is required for every forecast department.", call. = FALSE)
  }
  priorities <- as.numeric(priorities[departments])
  if (anyNA(priorities) || any(!is.finite(priorities)) || any(priorities <= 0)) {
    stop("Department priority weights must be finite and greater than zero.", call. = FALSE)
  }
  if (is.null(minimum_beds)) minimum_beds <- setNames(rep(0L, length(departments)), departments)
  if (is.null(names(minimum_beds)) || any(!departments %in% names(minimum_beds))) {
    stop("A minimum allocation value is required for every forecast department.", call. = FALSE)
  }
  minimum_beds <- as.numeric(minimum_beds[departments])
  if (anyNA(minimum_beds) || any(!is.finite(minimum_beds)) || any(minimum_beds < 0) ||
      any(minimum_beds != floor(minimum_beds)) || any(minimum_beds > demand)) {
    stop("Minimum allocations must be non-negative whole beds and cannot exceed modeled department demand.", call. = FALSE)
  }
  if (sum(minimum_beds) > capacity) {
    stop(sprintf("Minimum allocation conflict: department minimums total %d beds, exceeding the %d-bed capacity.",
                 sum(minimum_beds), capacity), call. = FALSE)
  }
  allocation <- as.integer(minimum_beds)
  target <- min(capacity, sum(demand))
  # Exact greedy optimizer for separable convex shortage cost:
  # priority * (unmet / modeled demand)^2. Each bed goes where it gives the
  # largest marginal reduction in weighted shortage; marginal value decreases
  # after each bed. This avoids arbitrary tied LP corner allocations.
  while (sum(allocation) < target) {
    unmet <- demand - allocation
    marginal <- ifelse(unmet > 0 & demand > 0,
      priorities * (2 * unmet - 1) / (demand ^ 2), -Inf)
    best <- which.max(marginal)
    if (!length(best) || !is.finite(marginal[best])) break
    allocation[best] <- allocation[best] + 1L
  }
  unmet <- demand - allocation
  total_allocated <- sum(allocation)
  shortage_pct <- ifelse(demand > 0, 100 * unmet / demand, 0)
  capacity_share_pct <- if (capacity > 0) 100 * allocation / capacity else rep(0, length(allocation))
  result <- bed_demand
  result$priority <- priorities
  result$minimum_beds <- as.integer(minimum_beds)
  result$allocated_beds <- allocation
  result$unmet_beds <- as.integer(unmet)
  result$shortage_pct <- shortage_pct
  result$capacity_share_pct <- capacity_share_pct
  result$capacity <- capacity
  result$policy <- policy_name
  result$shortage_rank <- rank(-result$unmet_beds, ties.method = "min")
  result$total_unmet_beds <- sum(unmet)
  result$capacity_utilization_pct <- if (capacity > 0) 100 * total_allocated / capacity else 0
  if (any(result$allocated_beds < 0) || any(result$allocated_beds != floor(result$allocated_beds)) ||
      any(result$unmet_beds < 0) || any(result$unmet_beds != floor(result$unmet_beds)) ||
      any(result$allocated_beds > demand) || total_allocated > capacity) {
    stop("Allocation failed an integer, demand, or capacity constraint.", call. = FALSE)
  }
  result
}

evaluate_allocation_policy <- function(bed_demand, capacity, priorities = NULL,
                                       policy = c("weighted", "minimum_floor"),
                                       minimum_share = 0.10) {
  policy <- match.arg(policy)
  if (length(minimum_share) != 1L || is.na(minimum_share) || !is.finite(minimum_share) ||
      minimum_share < 0 || minimum_share > 1) {
    stop("Minimum allocation share must be between 0 and 1.", call. = FALSE)
  }
  minimums <- setNames(rep(0L, nrow(bed_demand)), bed_demand$department)
  label <- "Weighted balanced shortage"
  if (policy == "minimum_floor") {
    minimums <- setNames(as.integer(ceiling(bed_demand$modeled_bed_demand * minimum_share)),
                         bed_demand$department)
    label <- sprintf("Weighted shortage + %.0f%% department demand floor", 100 * minimum_share)
  }
  optimize_bed_allocation(bed_demand, capacity, priorities, minimums, label)
}

compare_allocation_policies <- function(bed_demand, capacity, priorities = NULL, minimum_share = 0.10) {
  weighted <- evaluate_allocation_policy(bed_demand, capacity, priorities, "weighted", minimum_share)
  floor_policy <- tryCatch(
    evaluate_allocation_policy(bed_demand, capacity, priorities, "minimum_floor", minimum_share),
    error = function(e) e
  )
  floor_error <- if (inherits(floor_policy, "error")) conditionMessage(floor_policy) else NULL
  if (!is.null(floor_error)) {
    minimums <- ceiling(bed_demand$modeled_bed_demand * minimum_share)
    comparison <- data.frame(
      department = bed_demand$department,
      priority = if (is.null(priorities)) default_department_priorities(bed_demand$department) else priorities[bed_demand$department],
      modeled_bed_demand = bed_demand$modeled_bed_demand,
      weighted_allocated = weighted$allocated_beds,
      weighted_unmet = weighted$unmet_beds,
      floor_minimum = as.integer(minimums),
      floor_allocated = NA_integer_,
      floor_unmet = NA_integer_,
      allocation_change = NA_integer_,
      unmet_change = NA_integer_,
      stringsAsFactors = FALSE
    )
    return(list(weighted = weighted, minimum_floor = NULL, comparison = comparison,
                minimum_floor_error = floor_error))
  }
  comparison <- data.frame(
    department = weighted$department,
    priority = weighted$priority,
    modeled_bed_demand = weighted$modeled_bed_demand,
    weighted_allocated = weighted$allocated_beds,
    weighted_unmet = weighted$unmet_beds,
    floor_minimum = floor_policy$minimum_beds,
    floor_allocated = floor_policy$allocated_beds,
    floor_unmet = floor_policy$unmet_beds,
    allocation_change = floor_policy$allocated_beds - weighted$allocated_beds,
    unmet_change = floor_policy$unmet_beds - weighted$unmet_beds,
    stringsAsFactors = FALSE
  )
  list(weighted = weighted, minimum_floor = floor_policy, comparison = comparison,
       minimum_floor_error = NULL)
}

summarize_scenario_results <- function(allocation) {
  if (!nrow(allocation)) stop("Cannot summarize an empty allocation.", call. = FALSE)
  capacity <- unique(allocation$capacity)
  if (length(capacity) != 1L) stop("Allocation contains inconsistent capacity values.", call. = FALSE)
  allocated <- sum(allocation$allocated_beds)
  demand <- sum(allocation$modeled_bed_demand)
  unmet <- sum(allocation$unmet_beds)
  data.frame(
    total_modeled_demand = demand,
    available_capacity = capacity,
    allocated_beds = allocated,
    total_unmet_demand = unmet,
    capacity_utilization_pct = if (capacity > 0) 100 * allocated / capacity else 0,
    demand_coverage_pct = if (demand > 0) 100 * allocated / demand else 100
  )
}
