# Phase 4: assumption-driven Monte Carlo stress test of the proposed allocation.
# Run from the project root: Rscript R/05_simulation.R
allocation_path <- file.path("outputs", "tables", "bed_allocation.csv")
if (!file.exists(allocation_path)) {
  stop("Required allocation file is missing: ", allocation_path, ". Run R/04_optimization.R first.")
}
allocation <- read.csv(allocation_path, stringsAsFactors = FALSE, check.names = FALSE)
required <- c("department", "expected_beds", "allocated_beds")
missing <- setdiff(required, names(allocation))
if (!nrow(allocation) || length(missing)) {
  stop("Allocation file must contain columns: ", paste(required, collapse = ", "))
}
if (anyNA(allocation[required]) || any(!is.finite(allocation$expected_beds)) ||
    any(!is.finite(allocation$allocated_beds)) || any(allocation$expected_beds < 0) ||
    any(allocation$allocated_beds < 0) || anyDuplicated(allocation$department)) {
  stop("Allocation input contains missing, invalid, or duplicate department values.")
}
iterations_text <- Sys.getenv("HRDSS_SIMULATIONS", "5000")
iterations <- suppressWarnings(as.numeric(iterations_text))
if (length(iterations) != 1L || is.na(iterations) || !is.finite(iterations) ||
    iterations < 1 || iterations != floor(iterations) || iterations > .Machine$integer.max) {
  stop("HRDSS_SIMULATIONS must be a positive whole number.")
}
iterations <- as.integer(iterations)
scenarios <- data.frame(
  scenario = c("Baseline", "Demand surge", "High acuity", "Combined stress"),
  demand_multiplier = c(1.00, 1.25, 1.00, 1.25),
  icu_share = c(0.10, 0.10, 0.20, 0.20),
  stringsAsFactors = FALSE
)
set.seed(2026)
scenario_results <- vector("list", nrow(scenarios))
for (i in seq_len(nrow(scenarios))) {
  scenario <- scenarios[i, ]
  draws <- vapply(seq_len(iterations), function(j) {
    demand <- rpois(nrow(allocation), lambda = allocation$expected_beds * scenario$demand_multiplier)
    served <- pmin(demand, allocation$allocated_beds)
    total_demand <- sum(demand)
    total_unmet <- sum(demand - served)
    c(unmet_beds = total_unmet,
      unmet_rate = if (total_demand > 0) total_unmet / total_demand else 0,
      icu_beds_needed = ceiling(total_demand * scenario$icu_share))
  }, numeric(3))
  scenario_results[[i]] <- data.frame(
    unmet_beds = draws["unmet_beds", ],
    unmet_rate = draws["unmet_rate", ],
    icu_beds_needed = draws["icu_beds_needed", ],
    scenario = scenario$scenario,
    simulation = seq_len(iterations),
    stringsAsFactors = FALSE
  )
}
results <- do.call(rbind, scenario_results)
summaries <- lapply(scenarios$scenario, function(name) {
  rows <- results[results$scenario == name, , drop = FALSE]
  data.frame(
    scenario = name,
    unmet_beds_p50 = median(rows$unmet_beds),
    unmet_beds_p90 = unname(quantile(rows$unmet_beds, 0.90)),
    unmet_rate_p90 = unname(quantile(rows$unmet_rate, 0.90)),
    icu_beds_p90 = unname(quantile(rows$icu_beds_needed, 0.90)),
    stringsAsFactors = FALSE
  )
})
summary <- do.call(rbind, summaries)
dir.create(file.path("outputs", "tables"), recursive = TRUE, showWarnings = FALSE)
write.csv(results, file.path("outputs", "tables", "simulation_results.csv"), row.names = FALSE)
write.csv(summary, file.path("outputs", "tables", "simulation_summary.csv"), row.names = FALSE)
cat("Simulation results saved; iterations per scenario:", iterations, "\n")
