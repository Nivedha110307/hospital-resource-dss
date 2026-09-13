# Install all R packages needed across the HR-DSS project phases.
# Run once: Rscript requirements.R

pkgs <- c(
  # Phase 1 — data & EDA
  "tidyverse", "janitor", "lubridate", "scales",
  # Phase 2 — forecasting
  "forecast", "fable", "tsibble", "feasts",
  # Phase 3 — optimization
  "lpSolve",
  # Phase 4 — simulation
  "simmer",
  # Phase 5 — dashboard
  "shiny", "shinydashboard", "plotly", "DT"
)

installed <- rownames(installed.packages())
to_install <- setdiff(pkgs, installed)

if (length(to_install) > 0) {
  install.packages(to_install, repos = "https://cloud.r-project.org")
} else {
  message("All required packages already installed.")
}
