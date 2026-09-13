# =============================================================================
# 01_data_cleaning.R
# Hospital Resource Decision Support System (HR-DSS) — Phase 1
#
# Purpose:
#   Load the raw synthetic healthcare dataset, clean it, engineer the
#   features needed for later phases (forecasting, optimization,
#   simulation), and write a processed CSV to data/processed/.
#
# Input:  data/raw/healthcare_dataset.csv
# Output: data/processed/healthcare_clean.csv
# =============================================================================

library(tidyverse)
library(janitor)
library(lubridate)

# -----------------------------------------------------------------------
# 1. Load raw data
# -----------------------------------------------------------------------
raw_path <- "data/raw/healthcare_dataset.csv"
stopifnot(file.exists(raw_path))

raw_df <- read_csv(raw_path, show_col_types = FALSE) %>%
  clean_names()  # -> name, age, gender, blood_type, medical_condition,
                 #    date_of_admission, doctor, hospital, insurance_provider,
                 #    billing_amount, room_number, admission_type,
                 #    discharge_date, medication, test_results

cat("Raw rows:", nrow(raw_df), " Raw cols:", ncol(raw_df), "\n")

# -----------------------------------------------------------------------
# 2. Standardize text fields
# -----------------------------------------------------------------------
clean_df <- raw_df %>%
  mutate(
    name = str_squish(str_to_title(name)),
    gender = str_to_title(str_squish(gender)),
    blood_type = str_to_upper(str_squish(blood_type)),
    medical_condition = str_to_title(str_squish(medical_condition)),
    admission_type = str_to_title(str_squish(admission_type)),
    test_results = str_to_title(str_squish(test_results)),
    doctor = str_squish(doctor),
    hospital = str_squish(hospital),
    insurance_provider = str_squish(insurance_provider),
    date_of_admission = as_date(date_of_admission),
    discharge_date = as_date(discharge_date)
  )

# -----------------------------------------------------------------------
# 3. Remove exact duplicate rows
# -----------------------------------------------------------------------
n_before <- nrow(clean_df)
clean_df <- clean_df %>% distinct()
cat("Removed", n_before - nrow(clean_df), "exact duplicate rows\n")

# -----------------------------------------------------------------------
# 4. Resolve near-duplicate admissions
#    (same patient/admission/condition/insurer, inconsistent age entries)
#    Convention: keep the maximum reported age per admission group,
#    assuming later/updated entries are more accurate.
# -----------------------------------------------------------------------
n_before <- nrow(clean_df)
clean_df <- clean_df %>%
  group_by(name, date_of_admission, medical_condition, insurance_provider) %>%
  slice_max(order_by = age, n = 1, with_ties = FALSE) %>%
  ungroup()
cat("Removed", n_before - nrow(clean_df), "near-duplicate admission rows\n")

# -----------------------------------------------------------------------
# 5. Outlier / invalid-value handling
# -----------------------------------------------------------------------
# 5a. Negative billing amounts are data-entry errors — document and drop.
n_negative_billing <- sum(clean_df$billing_amount < 0, na.rm = TRUE)
clean_df <- clean_df %>% filter(billing_amount >= 0)
cat("Removed", n_negative_billing, "rows with negative billing_amount\n")

# 5b. Discharge date must not precede admission date.
n_bad_dates <- sum(clean_df$discharge_date < clean_df$date_of_admission, na.rm = TRUE)
clean_df <- clean_df %>% filter(discharge_date >= date_of_admission)
cat("Removed", n_bad_dates, "rows with discharge before admission\n")

# 5c. Missing-value check (raw source has none, but guard for future runs)
na_counts <- colSums(is.na(clean_df))
if (any(na_counts > 0)) {
  cat("Missing values found:\n")
  print(na_counts[na_counts > 0])
  clean_df <- clean_df %>% drop_na()
}

# -----------------------------------------------------------------------
# 6. Feature engineering
# -----------------------------------------------------------------------
condition_to_department <- c(
  "Cancer"       = "Oncology",
  "Diabetes"     = "Endocrinology",
  "Hypertension" = "Cardiology",
  "Obesity"      = "General Medicine",
  "Asthma"       = "Pulmonology",
  "Arthritis"    = "Orthopedics"
)

clean_df <- clean_df %>%
  mutate(
    length_of_stay = as.integer(discharge_date - date_of_admission),
    age_group = case_when(
      age <= 18 ~ "Paediatric",
      age <= 65 ~ "Adult",
      TRUE ~ "Geriatric"
    ),
    department = recode(medical_condition, !!!condition_to_department,
                         .default = "Other"),
    admission_year = year(date_of_admission),
    admission_month = month(date_of_admission, label = TRUE, abbr = TRUE),
    admission_year_month = floor_date(date_of_admission, "month"),
    admission_week = floor_date(date_of_admission, "week"),
    admission_dow = wday(date_of_admission, label = TRUE, abbr = TRUE)
  )

# -----------------------------------------------------------------------
# 7. Sanity checks before writing output
# -----------------------------------------------------------------------
stopifnot(all(clean_df$length_of_stay >= 0))
stopifnot(all(clean_df$billing_amount >= 0))
stopifnot(!anyNA(clean_df$department))

cat("\nFinal cleaned rows:", nrow(clean_df), "\n")
cat("Departments:", paste(sort(unique(clean_df$department)), collapse = ", "), "\n")

# -----------------------------------------------------------------------
# 8. Write processed dataset
# -----------------------------------------------------------------------
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
write_csv(clean_df, "data/processed/healthcare_clean.csv")
cat("Saved: data/processed/healthcare_clean.csv\n")
