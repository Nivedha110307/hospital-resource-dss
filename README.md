# Hospital Resource Decision Support System (HR-DSS)

## Problem statement

Hospitals must continuously balance uncertain patient demand against limited
beds, staff, ICU capacity, and other resources. Static resource planning can
lead to shortages, underutilization, and inefficient allocation.

## Proposed solution

HR-DSS is an R-based analytics and decision-support platform combining
statistical analysis, demand forecasting, optimization, Monte Carlo
simulation, and interactive visualization to support hospital resource
planning.

**Project story:**
- Phase 1 → What happened? (data + EDA)
- Phase 2 → What will happen? (forecasting)
- Phase 3 → What should we allocate? (optimization)
- Phase 4 → What if conditions change? (simulation & risk)
- Phase 5 → How does the decision-maker use the results? (Shiny dashboard)

## Status: Phase 1 complete ✅

Data acquisition, cleaning, feature engineering, and exploratory analysis.
See `outputs/reports/phase1_eda_summary.txt`, `outputs/figures/`, and
`outputs/tables/` for results, and `docs/methodology.md` for details.

## Technology stack

| Component | Technology |
|---|---|
| Language | R |
| Data processing | tidyverse, janitor, lubridate |
| Visualization | ggplot2 |
| Forecasting (Phase 2) | forecast / fable |
| Optimization (Phase 3) | lpSolve |
| Simulation (Phase 4) | base R / simmer |
| Dashboard (Phase 5) | Shiny, plotly, DT |
| Version control | Git + GitHub |

## Repository structure

```
hospital-resource-dss/
├── data/
│   ├── raw/                # untouched source data
│   ├── processed/          # cleaned, feature-engineered data
│   └── README.md           # dataset documentation & provenance
├── R/
│   ├── 01_data_cleaning.R
│   └── 02_eda.R
├── models/                 # (Phase 2+ forecasting/optimization models)
├── app/                    # (Phase 5 Shiny dashboard)
├── outputs/
│   ├── figures/
│   ├── tables/
│   └── reports/
├── docs/
│   ├── methodology.md
│   └── dataset.md
├── tests/
├── requirements.R
└── README.md
```

## How to run Phase 1

```r
install.packages(c("tidyverse", "janitor", "lubridate", "scales"))
# or: source("requirements.R")

source("R/01_data_cleaning.R")   # writes data/processed/healthcare_clean.csv
source("R/02_eda.R")             # writes outputs/figures, outputs/tables, outputs/reports
```

## Dataset

Synthetic 55,500-record hospital dataset (Kaggle: prasad22/healthcare-dataset).
See `data/README.md` for the full data dictionary, known data-quality issues,
and every derived/proxy variable (e.g. `department`, `length_of_stay`),
clearly labeled as such.

## License

MIT — see `LICENSE`.
