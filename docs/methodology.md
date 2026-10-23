# Phase 1 Methodology — Data & EDA

## 1. Data acquisition

Source: synthetic 55,500-row Kaggle healthcare dataset (see `data/README.md`
for provenance and full data dictionary). Downloaded once to
`data/raw/healthcare_dataset.csv` and never modified in place.

## 2. Cleaning pipeline (`R/01_data_cleaning.R`)

1. Standardize column names (`janitor::clean_names`) and text fields
   (trim whitespace, consistent casing).
2. Parse `Date of Admission` / `Discharge Date` as dates.
3. Remove exact duplicate rows.
4. Resolve near-duplicate admissions — rows identical on
   name + admission date + condition + insurer but differing only in
   `age` — by keeping the maximum reported age per group.
5. Drop rows with negative `billing_amount` (data-entry errors).
6. Drop rows where `discharge_date < date_of_admission` (none found, but
   checked defensively).
7. Guard for missing values (none present in the source file).

## 3. Feature engineering

- `length_of_stay` = discharge date − admission date (days)
- `age_group`: Paediatric (≤18) / Adult (19–65) / Geriatric (65+)
- `department`: mapped from `medical_condition` (documented 1:1 mapping,
  since the raw data has no ward/department field — see `data/README.md`)
- Calendar features: `admission_year_month`, `admission_week`,
  `admission_dow` for trend/seasonality analysis

## 4. Exploratory analysis (`R/02_eda.R`)

- Descriptive statistics for age, length of stay, billing amount
- Department-wise admission counts
- Daily/weekly/monthly admission trends and day-of-week pattern
- Length-of-stay distribution, overall and by department
- Admission-type distribution (Elective / Urgent / Emergency)
- Daily bed-occupancy proxy, derived by expanding each admission into its
  [admission date, discharge date] interval and counting overlaps
- Correlation heatmap across numeric features
- Seasonal (month-of-year) admission pattern pooled across years

## 5. Results snapshot

See `outputs/reports/phase1_eda_summary.txt` for the numeric summary and
`outputs/figures/` for all charts. Headline findings from this run:

- Cleaning removed exact duplicates, ~11k near-duplicate admissions
  (collapsed on max reported age), and rows with negative billing amounts.
- Admissions are close to evenly split across the 6 department proxies and
  across the 3 admission types — expected, since the source is a
  randomly-generated synthetic dataset rather than real epidemiological data.
- Length of stay ranges 1–30 days with no strong relationship to age,
  billing amount, or department — again consistent with random generation.

**Caveat:** because the underlying data is synthetic and uniformly random,
Phase 1 EDA here mainly validates that the *pipeline* is correct
(cleaning logic, feature engineering, chart generation). The forecasting
and optimization phases will still run correctly on this data, but any
"seasonal pattern" or "department differences" found are pipeline
demonstrations, not real hospital signal — call this out explicitly in
any write-up or presentation of results.

## 6. Phase 2 — forecasting (`R/03_forecasting.R`)

Build a complete monthly admission series for each department proxy. Compare
seasonal-naive and ETS forecasts on a rolling terminal holdout of up to 12
months using mean absolute error (MAE), select the lower-MAE model, then refit
it to the full history and forecast six months ahead. The output includes the
80% interval from the selected model. Model scores are diagnostic only: the
synthetic random data does not establish predictive value for a real hospital.

## 7. Phase 3 — explainable bed allocation (`R/allocation_functions.R`, `R/04_optimization.R`)

Convert each department's first forecast month to expected concurrent beds by
multiplying forecast admissions by its cleaned-data mean length of stay and
dividing by 30.4375. The batch model and dashboard use the first month in the
six-month forecast, matching the prior pipeline's planning horizon. Demand
adjustments multiply the forecast once; the source forecast table is never
modified. Expected beds remain available as a fractional estimate, while
modeled bed demand is `ceiling(expected_beds)` so a fractional bed is not
silently treated as available capacity.

The old linear shortage objective gave each bed a constant value. With equal
department weights, many allocation vectors had the same objective, so the
solver could return a corner solution that gave some departments zero beds.
The revised exact discrete allocator minimizes the sum of
`priority * (unmet_beds / modeled_bed_demand)^2`. This convex shortage penalty
rewards reducing the largest percentage shortages first. It assigns each bed
to the department where that bed gives the largest marginal reduction in the
penalty; marginal benefit declines as coverage improves. The separable convex
integer problem with one shared capacity constraint is solved exactly by this
marginal allocation rule, without a mixed-integer search.

Department priorities are configurable in the dashboard. The illustrative
default is 1.10 for General Medicine and 1.00 elsewhere; it is a planning
assumption, not clinical evidence. Every allocation is bounded below by zero
and above by rounded modeled demand, and total allocation cannot exceed
capacity. The alternative policy imposes a configurable minimum share of each
department's modeled demand before allocating remaining beds by the same
marginal rule. If those minimums exceed available capacity, the model reports
the conflict. The optimizer reports unmet demand as rounded modeled bed demand
minus allocated beds, department shortage percentages, capacity shares,
priority weights, and totals. Capacity utilization is zero when capacity is
zero and allocation is zero. Default capacity is 180 and can be set with
`HRDSS_BED_CAPACITY`.

## 8. Phase 4 — simulation (`R/05_simulation.R`)

For four explicit scenarios (baseline, 25% demand surge, doubled assumed ICU
share, and combined stress), generate 5,000 Poisson demand draws per
department. Apply the Phase 3 fixed allocation, then report unmet beds, unmet
rate, and simulated ICU bed need. ICU share is an assumption (10% baseline,
20% high-acuity scenario); the dataset contains no ICU field. Set
`HRDSS_SIMULATIONS` to change the iteration count. The summary reports
medians and 90th percentiles to show uncertainty, not confidence guarantees.

## 9. HRDSS 2.0 — dynamic capacity stress testing

The dashboard applies one of five named scenarios to the original first-month
forecast: baseline, configurable overall increase, configurable overall
reduction, reduced bed capacity, or a multiplier for one selected department.
Only the selected scenario's adjustment is active. Baseline explicitly uses
multiplier 1, no department multiplier, and the selected base capacity;
settings for other scenario types do not leak into it. Each reactive update
recalculates adjusted forecast, expected and rounded bed demand, allocation,
unmet demand, shortage percentages, and capacity use. Forecast models are not
refitted. Comparisons use the same forecast and capacity for the weighted and
minimum-floor policies and calculate both from the shared allocation
functions. Baseline results are always recalculated from the unmodified source
forecast rather than read from a previous output CSV.

Scenario sliders and their ranges are centralized in `scenario_config` near
the top of `app/app.R`. The dashboard shows baseline-versus-scenario demand,
allocation, shortage, total unmet demand, and capacity utilization. Explanation
text and policy comparisons are derived from the actual current model results.

## 10. Phase 5 — dashboard (`app/app.R`)

Launch with `Rscript.exe -e "shiny::runApp('app')"` from the repository root,
or `Rscript.exe -e "shiny::runApp('.')"` from `app/`. Project-root discovery
supports both launch directories. Required forecast and processed-data files
produce explicit missing-file messages. Saved Monte Carlo summaries remain
available in the Simulation Risk tab; the interactive stress scenarios are
separate deterministic forecast-and-allocation recalculations.

## 11. Tests and limitations

Run `Rscript.exe tests/test_allocation_scenarios.R` from the project root to
check baseline restoration, global demand increase/decrease, capacity stress,
department surge, policy comparison, priority changes, and invalid/conflicting
inputs. Run the regular pipeline in order using the commands in `README.md`.

The source data is randomly generated and contains no real department, bed,
staffing, or acuity observations. Departments are mapped from conditions;
occupancy is inferred from admission and discharge dates; ICU need is simulated.
Consequently, outputs demonstrate a reproducible analytics pipeline and must
not be treated as clinical or real-world operational recommendations.
