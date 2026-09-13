# =============================================================================
# 02_eda.R
# Hospital Resource Decision Support System (HR-DSS) — Phase 1
#
# Purpose:
#   Exploratory data analysis on the cleaned dataset — descriptive stats,
#   admission trends, department-wise demand, length-of-stay analysis,
#   correlation, and seasonality. Saves figures to outputs/figures/,
#   summary tables to outputs/tables/, and a text summary to
#   outputs/reports/.
#
# Input:  data/processed/healthcare_clean.csv
# Output: outputs/figures/*.png, outputs/tables/*.csv,
#         outputs/reports/phase1_eda_summary.txt
# =============================================================================

library(tidyverse)
library(lubridate)
library(scales)

dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/reports", showWarnings = FALSE, recursive = TRUE)

df <- read_csv("data/processed/healthcare_clean.csv", show_col_types = FALSE) %>%
  mutate(
    date_of_admission = as_date(date_of_admission),
    admission_year_month = as_date(admission_year_month),
    admission_week = as_date(admission_week)
  )

theme_set(theme_minimal(base_size = 12))

# -----------------------------------------------------------------------
# 1. Descriptive statistics
# -----------------------------------------------------------------------
desc_numeric <- df %>%
  summarise(
    n = n(),
    age_mean = mean(age), age_sd = sd(age),
    los_mean = mean(length_of_stay), los_sd = sd(length_of_stay),
    los_median = median(length_of_stay),
    billing_mean = mean(billing_amount), billing_median = median(billing_amount)
  )
write_csv(desc_numeric, "outputs/tables/descriptive_stats.csv")

# -----------------------------------------------------------------------
# 2. Department-wise patient distribution
# -----------------------------------------------------------------------
dept_counts <- df %>% count(department, sort = TRUE) %>%
  mutate(pct = round(100 * n / sum(n), 1))
write_csv(dept_counts, "outputs/tables/department_distribution.csv")

p_dept <- ggplot(dept_counts, aes(x = reorder(department, n), y = n)) +
  geom_col(fill = "#2C7FB8") +
  coord_flip() +
  labs(title = "Admissions by Department", x = NULL, y = "Number of admissions")
ggsave("outputs/figures/01_admissions_by_department.png", p_dept, width = 8, height = 5, dpi = 150)

# -----------------------------------------------------------------------
# 3. Admission trends: daily / weekly / monthly
# -----------------------------------------------------------------------
monthly_trend <- df %>% count(admission_year_month, name = "admissions")
p_monthly <- ggplot(monthly_trend, aes(x = admission_year_month, y = admissions)) +
  geom_line(color = "#D95F02", linewidth = 0.8) +
  labs(title = "Monthly Admission Trend", x = "Month", y = "Admissions")
ggsave("outputs/figures/02_monthly_admission_trend.png", p_monthly, width = 9, height = 5, dpi = 150)

weekly_trend <- df %>% count(admission_week, name = "admissions")
p_weekly <- ggplot(weekly_trend, aes(x = admission_week, y = admissions)) +
  geom_line(color = "#1B9E77", linewidth = 0.5) +
  labs(title = "Weekly Admission Trend", x = "Week", y = "Admissions")
ggsave("outputs/figures/03_weekly_admission_trend.png", p_weekly, width = 9, height = 5, dpi = 150)

dow_trend <- df %>% count(admission_dow, name = "admissions")
p_dow <- ggplot(dow_trend, aes(x = admission_dow, y = admissions)) +
  geom_col(fill = "#7570B3") +
  labs(title = "Admissions by Day of Week", x = NULL, y = "Admissions")
ggsave("outputs/figures/04_admissions_by_dow.png", p_dow, width = 7, height = 5, dpi = 150)

# -----------------------------------------------------------------------
# 4. Length-of-stay analysis
# -----------------------------------------------------------------------
p_los <- ggplot(df, aes(x = length_of_stay)) +
  geom_histogram(binwidth = 1, fill = "#66A61E", color = "white") +
  labs(title = "Length of Stay Distribution", x = "Length of stay (days)", y = "Count")
ggsave("outputs/figures/05_los_distribution.png", p_los, width = 8, height = 5, dpi = 150)

los_by_dept <- df %>%
  group_by(department) %>%
  summarise(mean_los = mean(length_of_stay), median_los = median(length_of_stay), n = n()) %>%
  arrange(desc(mean_los))
write_csv(los_by_dept, "outputs/tables/los_by_department.csv")

p_los_dept <- ggplot(df, aes(x = department, y = length_of_stay)) +
  geom_boxplot(fill = "#E6AB02") +
  coord_flip() +
  labs(title = "Length of Stay by Department", x = NULL, y = "Length of stay (days)")
ggsave("outputs/figures/06_los_by_department_boxplot.png", p_los_dept, width = 8, height = 5, dpi = 150)

# -----------------------------------------------------------------------
# 5. Patient-type / admission-type distribution
# -----------------------------------------------------------------------
admtype_counts <- df %>% count(admission_type, sort = TRUE)
write_csv(admtype_counts, "outputs/tables/admission_type_distribution.csv")

p_admtype <- ggplot(admtype_counts, aes(x = admission_type, y = n, fill = admission_type)) +
  geom_col(show.legend = FALSE) +
  labs(title = "Admissions by Admission Type", x = NULL, y = "Admissions")
ggsave("outputs/figures/07_admissions_by_type.png", p_admtype, width = 7, height = 5, dpi = 150)

# -----------------------------------------------------------------------
# 6. Bed / room utilization proxy (rooms in concurrent use per day)
# -----------------------------------------------------------------------
# Expand each admission into an occupancy interval and count rooms in use
# per day as a simple proxy for bed occupancy trend.
occupancy <- df %>%
  select(date_of_admission, discharge_date, department) %>%
  mutate(row_id = row_number()) %>%
  rowwise() %>%
  mutate(day_seq = list(seq(date_of_admission, discharge_date, by = "day"))) %>%
  ungroup() %>%
  unnest(day_seq)

daily_occupancy <- occupancy %>% count(day_seq, name = "occupied_beds")
write_csv(daily_occupancy, "outputs/tables/daily_occupancy_proxy.csv")

p_occ <- ggplot(daily_occupancy, aes(x = day_seq, y = occupied_beds)) +
  geom_line(color = "#E7298A", linewidth = 0.4) +
  labs(title = "Estimated Daily Bed Occupancy (proxy from admission/discharge dates)",
       x = "Date", y = "Occupied beds (proxy)")
ggsave("outputs/figures/08_daily_occupancy_proxy.png", p_occ, width = 9, height = 5, dpi = 150)

# -----------------------------------------------------------------------
# 7. Correlation analysis (numeric features)
# -----------------------------------------------------------------------
num_df <- df %>% select(age, length_of_stay, billing_amount, room_number)
corr_mat <- cor(num_df, use = "complete.obs")
write.csv(corr_mat, "outputs/tables/correlation_matrix.csv")

corr_long <- as.data.frame(as.table(corr_mat))
p_corr <- ggplot(corr_long, aes(Var1, Var2, fill = Freq)) +
  geom_tile() +
  geom_text(aes(label = round(Freq, 2)), size = 3) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B", midpoint = 0) +
  labs(title = "Correlation Heatmap", x = NULL, y = NULL, fill = "r")
ggsave("outputs/figures/09_correlation_heatmap.png", p_corr, width = 6, height = 5, dpi = 150)

# -----------------------------------------------------------------------
# 8. Seasonal demand comparison (month-of-year, pooled across years)
# -----------------------------------------------------------------------
seasonal <- df %>%
  mutate(month_name = month(date_of_admission, label = TRUE, abbr = TRUE)) %>%
  count(month_name, name = "admissions")
write_csv(seasonal, "outputs/tables/seasonal_admissions.csv")

p_seasonal <- ggplot(seasonal, aes(x = month_name, y = admissions, group = 1)) +
  geom_line(color = "#666666") + geom_point(color = "#D95F02") +
  labs(title = "Seasonal Admission Pattern (pooled across years)", x = NULL, y = "Admissions")
ggsave("outputs/figures/10_seasonal_pattern.png", p_seasonal, width = 8, height = 5, dpi = 150)

# -----------------------------------------------------------------------
# 9. Write a plain-text Phase 1 summary report
# -----------------------------------------------------------------------
sink("outputs/reports/phase1_eda_summary.txt")
cat("HR-DSS — Phase 1 EDA Summary\n")
cat("=============================\n\n")
cat("Rows after cleaning:", nrow(df), "\n")
cat("Date range:", as.character(min(df$date_of_admission)), "to",
    as.character(max(df$date_of_admission)), "\n\n")
cat("-- Descriptive stats --\n"); print(desc_numeric)
cat("\n-- Department distribution --\n"); print(dept_counts)
cat("\n-- Admission type distribution --\n"); print(admtype_counts)
cat("\n-- Length of stay by department --\n"); print(los_by_dept)
cat("\n-- Correlation matrix --\n"); print(round(corr_mat, 3))
sink()

cat("EDA complete. Figures in outputs/figures/, tables in outputs/tables/,\n",
    "summary in outputs/reports/phase1_eda_summary.txt\n")
