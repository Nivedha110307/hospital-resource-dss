# Phase 2: monthly demand forecasts by department.
# Compare seasonal-naive and ETS models using a rolling one-year holdout.
library(tidyverse)
library(lubridate)
library(forecast)

dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("models", recursive = TRUE, showWarnings = FALSE)
df <- read_csv("data/processed/healthcare_clean.csv", show_col_types = FALSE) %>%
  mutate(admission_year_month = floor_date(as.Date(admission_year_month), "month"))
months <- seq(min(df$admission_year_month), max(df$admission_year_month), by = "month")
departments <- sort(unique(df$department))
actual <- df %>% count(department, admission_year_month, name = "admissions") %>%
  complete(department, admission_year_month = months, fill = list(admissions = 0L))
forecast_rows <- list(); metric_rows <- list()
for (dept in departments) {
  y <- actual %>% filter(department == dept) %>% arrange(admission_year_month) %>% pull(admissions)
  n <- length(y); h <- min(12L, max(1L, n %/% 5L)); train <- y[seq_len(n-h)]; truth <- y[(n-h+1L):n]
  ts_train <- ts(train, frequency = 12)
  candidates <- list(SeasonalNaive = snaive(ts_train, h = h), ETS = forecast(ets(ts_train), h = h))
  scores <- vapply(candidates, function(x) mean(abs(truth - as.numeric(x$mean))), numeric(1))
  chosen <- names(which.min(scores))
  # Refit the selected method to all observed months for the operational horizon.
  full_ts <- ts(y, frequency = 12)
  fc <- if (chosen == "ETS") forecast(ets(full_ts), h = 6) else snaive(full_ts, h = 6)
  future_dates <- seq(max(months) %m+% months(1), by = "month", length.out = 6)
  forecast_rows[[dept]] <- tibble(department = dept, month = future_dates,
    forecast = pmax(0, as.numeric(fc$mean)), lower80 = pmax(0, as.numeric(fc$lower[,1])),
    upper80 = pmax(0, as.numeric(fc$upper[,1])), model = chosen)
  metric_rows[[dept]] <- tibble(department = dept, model = names(scores), holdout_mae = as.numeric(scores), holdout_months = h)
}
write_csv(bind_rows(forecast_rows), "outputs/tables/demand_forecast.csv")
write_csv(bind_rows(metric_rows), "outputs/tables/forecast_model_comparison.csv")
cat("Forecasts saved to outputs/tables (six months per department).\n")
