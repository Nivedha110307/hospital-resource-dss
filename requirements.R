# Install all R packages needed across the HR-DSS project phases.
# Run once: Rscript requirements.R

pkgs <- c(
  # Phase 1 — data & EDA
  "tidyverse", "janitor", "lubridate", "scales",
  # Phase 2 — forecasting
  "forecast", "fable", "tsibble", "feasts",
  # Phase 3 — optimization uses base R (no additional solver package)
  # Phase 4 — simulation
  "simmer",
  # Phase 5 — dashboard
  "shiny", "shinydashboard", "plotly", "DT"
)

version_parts <- strsplit(R.version$minor, "\\.")[[1]]
r_version <- paste(R.version$major, version_parts[[1]], sep = ".")
user_library <- file.path(path.expand("~"), "R", "win-library", r_version)
if (.Platform$OS.type != "windows") {
  user_library <- file.path(path.expand("~"), "R", "library", r_version)
}
dir.create(user_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(user_library, .libPaths()))

installed <- rownames(installed.packages())
to_install <- setdiff(pkgs, installed)

if (length(to_install) > 0) {
  install.packages(to_install, lib = user_library, repos = "https://cloud.r-project.org")
} else {
  message("All required packages already installed.")
}
