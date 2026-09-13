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

## 6. Next: Phase 2

Use `department` and `admission_year_month`/day as the forecasting grain,
comparing naive, ETS, and ARIMA models on the cleaned series.
