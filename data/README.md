# Dataset Documentation

## Source

**Healthcare Dataset** (synthetic), originally published on Kaggle by Prasad Patil:
https://www.kaggle.com/datasets/prasad22/healthcare-dataset

Mirrored as a plain CSV for reproducible download at:
https://raw.githubusercontent.com/yuanz25/healthcare-data-analysis/main/healthcare_dataset.csv

- 55,500 synthetic patient hospitalization records
- No real patient data — safe for public academic use, no PHI/privacy concerns
- Generated for education/portfolio use; admission counts, billing amounts,
  and clinical outcomes are randomly generated and do **not** reflect real
  epidemiology. This is acceptable for demonstrating the analytics
  pipeline (cleaning → forecasting → optimization → simulation → dashboard),
  but any "insights" should be read as methodological illustrations, not
  real clinical findings.

## Raw columns

| Column | Type | Notes |
|---|---|---|
| Name | string | Patient name (synthetic) |
| Age | integer | 13–89 |
| Gender | string | Male / Female |
| Blood Type | string | e.g. A+, O- |
| Medical Condition | string | 6 categories: Cancer, Obesity, Diabetes, Hypertension, Arthritis, Asthma |
| Date of Admission | date | 2019-05-08 to 2024-05-07 |
| Doctor | string | Attending physician |
| Hospital | string | Facility name |
| Insurance Provider | string | Payer |
| Billing Amount | float | Some negative values (data-entry errors, see below) |
| Room Number | integer | Assigned room |
| Admission Type | string | Elective / Urgent / Emergency |
| Discharge Date | date | Always after admission date |
| Medication | string | Prescribed drug |
| Test Results | string | Normal / Abnormal / Inconclusive |

## Known data-quality issues (found during profiling)

- **534** fully duplicated rows.
- **~11,000** rows sharing Name + Admission Date + Medical Condition +
  Insurance Provider but differing only in `Age` — treated as the same
  admission record entered more than once with inconsistent age.
- **108** rows with a negative `Billing Amount` (data-entry error).
- No missing values and no invalid dates in the raw file.

## Derived / proxy variables (clearly labelled, not raw measurements)

The raw dataset has no `Department`, `Bed Occupancy`, or `ICU` fields, so the
project derives clearly-documented proxies rather than inventing real
hospital measurements:

| Derived field | Definition | Purpose |
|---|---|---|
| `length_of_stay` | `discharge_date - admission_date` (days) | Core operational metric for forecasting/optimization |
| `age_group` | 0–18 Paediatric / 19–65 Adult / 65+ Geriatric | Demand segmentation |
| `department` | Mapped 1:1 from `Medical Condition` (see table below) | Stand-in for a hospital department/ward, since the source data has no ward field |
| `admission_year_month`, `admission_dow`, `admission_week` | Extracted from `Date of Admission` | Seasonal/weekly demand analysis |

`Medical Condition` → `department` mapping (a reasonable, documented
convention — not a claim about how any real hospital is organised):

| Medical Condition | Department |
|---|---|
| Cancer | Oncology |
| Diabetes | Endocrinology |
| Hypertension | Cardiology |
| Obesity | General Medicine |
| Asthma | Pulmonology |
| Arthritis | Orthopedics |

**ICU requirement is intentionally NOT fabricated** in Phase 1 — the raw
data gives no clinical acuity signal that would justify labeling any row as
an ICU case. ICU demand will instead be handled as a modeled scenario
(assumption-driven, explicitly labeled as simulated) starting in Phase 4.

## Files

- `data/raw/healthcare_dataset.csv` — untouched download of the source file
- `data/processed/healthcare_clean.csv` — output of `R/01_data_cleaning.R`
