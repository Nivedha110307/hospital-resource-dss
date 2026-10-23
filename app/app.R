# Launch from the repository root with shiny::runApp("app") or from app/ with shiny::runApp(".").
library(shiny)
library(tidyverse)
library(plotly)
library(DT)

find_project_root <- function() {
  current <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  candidates <- unique(normalizePath(c(current, file.path(current, ".."), file.path(current, "../..")),
                                     winslash = "/", mustWork = TRUE))
  valid <- vapply(candidates, function(path) {
    file.exists(file.path(path, "app", "app.R")) &&
      file.exists(file.path(path, "R", "allocation_functions.R")) &&
      dir.exists(file.path(path, "data", "processed"))
  }, logical(1))
  if (!any(valid)) {
    stop("Cannot locate HR-DSS project root from ", current,
         ". Expected app/app.R, R/allocation_functions.R, and data/processed/.")
  }
  candidates[which(valid)[1]]
}
project_root <- find_project_root()
project_paths <- list(
  processed = file.path(project_root, "data", "processed"),
  figures = file.path(project_root, "outputs", "figures"),
  tables = file.path(project_root, "outputs", "tables"),
  reports = file.path(project_root, "outputs", "reports")
)
source(file.path(project_root, "R", "allocation_functions.R"), local = FALSE)

# Sensitivity ranges are centralized here so scenario assumptions are easy to adjust.
scenario_config <- list(
  capacity_min = 0L, capacity_max = 600L, capacity_default = 180L,
  demand_increase_min_pct = 0L, demand_increase_max_pct = 100L, demand_increase_default_pct = 20L,
  demand_reduction_min_pct = 0L, demand_reduction_max_pct = 50L, demand_reduction_default_pct = 20L,
  capacity_reduction_min_pct = 0L, capacity_reduction_max_pct = 75L, capacity_reduction_default_pct = 25L,
  department_surge_min = 1, department_surge_max = 3, department_surge_default = 1.5,
  priority_min = 0.5, priority_max = 3, priority_default = 1.1,
  minimum_share_min = 0, minimum_share_max = 0.30, minimum_share_default = 0.10
)

read_required_csv <- function(path, purpose) {
  if (!file.exists(path)) {
    stop("Required input file is missing: ", path, ". ", purpose, call. = FALSE)
  }
  tryCatch(read.csv(path, stringsAsFactors = FALSE, check.names = FALSE), error = function(e) {
    stop("Could not read ", path, ": ", conditionMessage(e), call. = FALSE)
  })
}

read_optional_result <- function(filename) {
  path <- file.path(project_paths$tables, filename)
  if (!file.exists(path)) return(structure(data.frame(), source_path = path))
  result <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  attr(result, "source_path") <- path
  result
}

require_result <- function(result, instruction) {
  validate(need(nrow(result) > 0,
    paste0("Required result file is missing or empty: ", attr(result, "source_path"), ". ", instruction)))
  result
}

ui <- fluidPage(
  titlePanel("Hospital Resource Decision Support System — HRDSS 2.0"),
  p("Forecast-derived planning estimates using synthetic records. Modeled bed demand and simulated outcomes are not clinical measurements."),
  sidebarLayout(
    sidebarPanel(
      h4("Capacity stress scenario"),
      selectInput("scenario", "Scenario", choices = c(
        "Baseline demand" = "baseline",
        "Increased demand" = "increased_demand",
        "Reduced demand" = "reduced_demand",
        "Reduced bed capacity" = "reduced_capacity",
        "Selected department surge" = "department_surge"
      )),
      sliderInput("capacity", "Available bed capacity", min = scenario_config$capacity_min,
                  max = scenario_config$capacity_max, value = scenario_config$capacity_default, step = 1),
      sliderInput("demand_increase", "Demand increase (%)", min = scenario_config$demand_increase_min_pct,
                  max = scenario_config$demand_increase_max_pct, value = scenario_config$demand_increase_default_pct, step = 5),
      sliderInput("demand_reduction", "Demand reduction (%)", min = scenario_config$demand_reduction_min_pct,
                  max = scenario_config$demand_reduction_max_pct, value = scenario_config$demand_reduction_default_pct, step = 5),
      sliderInput("capacity_reduction", "Capacity reduction scenario (%)", min = scenario_config$capacity_reduction_min_pct,
                  max = scenario_config$capacity_reduction_max_pct, value = scenario_config$capacity_reduction_default_pct, step = 5),
      selectInput("surge_department", "Department for surge", choices = NULL),
      sliderInput("department_surge", "Selected department multiplier", min = scenario_config$department_surge_min,
                  max = scenario_config$department_surge_max, value = scenario_config$department_surge_default, step = 0.1),
      hr(),
      h4("Allocation policy assumptions"),
      selectInput("priority_department", "Department priority to adjust", choices = NULL),
      sliderInput("priority_weight", "Selected department priority", min = scenario_config$priority_min,
                  max = scenario_config$priority_max, value = scenario_config$priority_default, step = 0.1),
      selectInput("active_policy", "Policy shown in overview", choices = c(
        "Weighted balanced shortage" = "weighted", "Minimum department floor" = "minimum_floor")),
      sliderInput("minimum_share", "Alternative policy minimum share of modeled demand (%)",
                  min = scenario_config$minimum_share_min * 100, max = scenario_config$minimum_share_max * 100,
                  value = scenario_config$minimum_share_default * 100, step = 1),
      helpText("Scenario controls recalculate forecast adjustments, modeled bed demand, allocation, and shortages. Historical forecasting is not rerun."),
      helpText(paste("Project data:", project_root))
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Overview",
          fluidRow(
            column(2, h5("Estimated demand"), strong(textOutput("kpi_demand", inline = TRUE))),
            column(2, h5("Available beds"), strong(textOutput("kpi_capacity", inline = TRUE))),
            column(2, h5("Allocated beds"), strong(textOutput("kpi_allocated", inline = TRUE))),
            column(3, h5("Estimated unmet demand"), strong(textOutput("kpi_unmet", inline = TRUE))),
            column(3, h5("Capacity utilization"), strong(textOutput("kpi_utilization", inline = TRUE)))
          ),
          h4("Scenario summary"), DTOutput("scenario_summary"),
          h4("Department allocation and explanation inputs"), DTOutput("allocation_table"),
          h4("Largest modeled shortages"), DTOutput("shortage_table"),
          h4("How this allocation was produced"), verbatimTextOutput("explanation")
        ),
        tabPanel("Stress testing",
          h4("Baseline versus selected scenario demand"), plotlyOutput("demand_comparison_plot"),
          h4("Baseline versus selected scenario allocation"), plotlyOutput("allocation_comparison_plot"),
          h4("Department-level unmet demand"), plotlyOutput("shortage_plot"),
          h4("Total shortage and capacity use"), plotlyOutput("summary_comparison_plot"),
          h4("Departments with the largest shortage increase"), DTOutput("shortage_change_table")
        ),
        tabPanel("Policy comparison",
          p("Both policies use the selected scenario's same forecast adjustments and bed capacity."),
          verbatimTextOutput("policy_status"),
          DTOutput("policy_comparison_table"), plotlyOutput("policy_comparison_plot"),
          h4("Department shortage redistribution"), plotlyOutput("policy_shortage_plot"),
          verbatimTextOutput("policy_explanation")
        ),
        tabPanel("Forecasts", plotlyOutput("forecast_plot"), DTOutput("forecast_table"), DTOutput("model_table")),
        tabPanel("Simulation risk", plotlyOutput("risk_plot"), DTOutput("risk_table")),
        tabPanel("About", h3("Interpretation and limitations"),
          p("The source dataset is synthetic. Department is a proxy mapped from medical condition; no real bed capacity, staffing, or ICU observations are available."),
          p("Forecasts are model estimates, bed demand is derived from forecast admissions and historical mean length of stay, and simulation outputs are modeled scenarios. None should be interpreted as observed outcomes or validated clinical requirements."),
          p("The objective balances the weighted squared percentage shortage. The 1.10 General Medicine priority is an explicit illustrative planning assumption; users can change department priorities and the alternative minimum-allocation share."))
      )
    )
  )
)

server <- function(input, output, session) {
  observe({
    forecast_path <- file.path(project_paths$tables, "demand_forecast.csv")
    if (!file.exists(forecast_path)) return(invisible(NULL))
    departments <- tryCatch(sort(unique(read_required_csv(forecast_path, "Run R/03_forecasting.R.")$department)),
                            error = function(e) character())
    if (length(departments)) {
      updateSelectInput(session, "surge_department", choices = departments, selected = departments[1])
      updateSelectInput(session, "priority_department", choices = departments,
                        selected = if ("General Medicine" %in% departments) "General Medicine" else departments[1])
    }
  })

  inputs <- reactive({
    forecast_path <- file.path(project_paths$tables, "demand_forecast.csv")
    processed_path <- file.path(project_paths$processed, "healthcare_clean.csv")
    list(
      forecasts = read_required_csv(forecast_path, "Run R/03_forecasting.R to create forecast data."),
      cleaned = read_required_csv(processed_path, "Run R/01_data_cleaning.R to create processed data.")
    )
  })

  calculations <- reactive({
    source_data <- inputs()
    departments <- sort(unique(as.character(source_data$forecasts$department)))
    priorities <- default_department_priorities(departments)
    selected_priority <- input$priority_department
    if (!is.null(selected_priority) && selected_priority %in% departments) {
      priorities[selected_priority] <- input$priority_weight
    }
    baseline_demand <- calculate_bed_demand(source_data$forecasts, source_data$cleaned)
    scenario_settings <- apply_demand_scenario(
      forecasts = source_data$forecasts,
      scenario = input$scenario,
      base_capacity = input$capacity,
      demand_increase_pct = input$demand_increase,
      demand_reduction_pct = input$demand_reduction,
      capacity_reduction_pct = input$capacity_reduction,
      surge_department = input$surge_department,
      department_multiplier = input$department_surge
    )
    scenario_demand <- calculate_bed_demand(source_data$forecasts, source_data$cleaned,
      overall_multiplier = scenario_settings$overall_multiplier,
      department_multipliers = scenario_settings$department_multipliers)
    baseline_capacity <- scenario_settings$base_capacity
    scenario_capacity <- scenario_settings$capacity
    baseline_policy <- evaluate_allocation_policy(baseline_demand, baseline_capacity, priorities,
      input$active_policy, input$minimum_share / 100)
    policy_comparison <- compare_allocation_policies(scenario_demand, scenario_capacity, priorities,
      input$minimum_share / 100)
    if (input$active_policy == "minimum_floor" && !is.null(policy_comparison$minimum_floor_error)) {
      stop(policy_comparison$minimum_floor_error, call. = FALSE)
    }
    selected_allocation <- if (input$active_policy == "minimum_floor") policy_comparison$minimum_floor else policy_comparison$weighted
    selected_allocation$baseline_allocated_beds <- baseline_policy$allocated_beds
    selected_allocation$baseline_unmet_beds <- baseline_policy$unmet_beds
    selected_allocation$allocation_change <- selected_allocation$allocated_beds - baseline_policy$allocated_beds
    selected_allocation$unmet_change <- selected_allocation$unmet_beds - baseline_policy$unmet_beds
    selected_allocation$scenario <- scenario_settings$scenario_label
    summary <- summarize_scenario_results(selected_allocation)
    baseline_summary <- summarize_scenario_results(baseline_policy)
    list(
      raw_forecasts = source_data$forecasts,
      baseline = baseline_policy,
      active = selected_allocation,
      summary = summary,
      baseline_summary = baseline_summary,
      policy_comparison = policy_comparison,
      scenario_demand = scenario_demand,
      scenario_name = scenario_settings$scenario_label,
      capacity = scenario_capacity,
      priorities = priorities
    )
  })

  output$kpi_demand <- renderText({ format(calculations()$summary$total_modeled_demand, big.mark = ",") })
  output$kpi_capacity <- renderText({ format(calculations()$capacity, big.mark = ",") })
  output$kpi_allocated <- renderText({ format(calculations()$summary$allocated_beds, big.mark = ",") })
  output$kpi_unmet <- renderText({ format(calculations()$summary$total_unmet_demand, big.mark = ",") })
  output$kpi_utilization <- renderText({ paste0(round(calculations()$summary$capacity_utilization_pct, 1), "%") })

  output$scenario_summary <- renderDT({
    x <- calculations()
    summary <- rbind(
      data.frame(comparison = "Baseline", scenario = "Baseline demand", x$baseline_summary),
      data.frame(comparison = "Selected scenario", scenario = x$scenario_name, x$summary)
    )
    datatable(summary, rownames = FALSE, options = list(dom = "t"))
  })
  output$allocation_table <- renderDT({
    x <- calculations()$active
    view <- x[, c("department", "adjusted_forecast", "expected_beds", "modeled_bed_demand",
      "allocated_beds", "unmet_beds", "shortage_pct", "capacity_share_pct", "priority",
      "minimum_beds", "baseline_allocated_beds", "allocation_change", "unmet_change")]
    datatable(view, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE)) %>%
      formatRound(c("adjusted_forecast", "expected_beds", "shortage_pct", "capacity_share_pct"), 1)
  })
  output$shortage_table <- renderDT({
    x <- calculations()$active
    x <- x[order(-x$unmet_beds, x$department), c("department", "unmet_beds", "shortage_pct", "shortage_rank")]
    datatable(x, rownames = FALSE, options = list(pageLength = 6, dom = "t"))
  })
  output$explanation <- renderText({
    x <- calculations()
    active <- x$active
    summary <- x$summary
    worst <- active[active$unmet_beds == max(active$unmet_beds), , drop = FALSE]
    worst_text <- if (max(active$unmet_beds) == 0) "No department has modeled unmet demand." else
      paste(paste0(worst$department, " (", worst$unmet_beds, " beds)"), collapse = ", ")
    changed <- active[active$allocation_change != 0 | active$unmet_change != 0, , drop = FALSE]
    changes_text <- if (!nrow(changed)) "No allocation changes from the baseline." else
      paste(paste0(changed$department, ": allocation ", ifelse(changed$allocation_change > 0, "+", ""),
        changed$allocation_change, ", unmet ", ifelse(changed$unmet_change > 0, "+", ""), changed$unmet_change), collapse = "; ")
    paste0("Policy: ", unique(active$policy), ". The allocator minimizes the sum of priority-weighted squared department shortage percentages. ",
      "Each available bed is assigned to the department where it most reduces that shortage penalty; marginal benefit declines as coverage improves. ",
      "Modeled demand is rounded up to whole beds. Capacity ", x$capacity, " beds; allocated ", summary$allocated_beds,
      "; estimated unmet ", summary$total_unmet_demand, "; utilization ", round(summary$capacity_utilization_pct, 1), "%. ",
      "Highest unmet demand: ", worst_text, ". Changes versus baseline: ", changes_text,
      ". Department priorities and any minimum allocations are shown in the table and policy settings.")
  })

  comparison_data <- reactive({
    x <- calculations()
    baseline <- x$baseline
    scenario <- x$active
    data.frame(
      department = rep(baseline$department, 2),
      series = rep(c("Baseline", x$scenario_name), each = nrow(baseline)),
      modeled_bed_demand = c(baseline$modeled_bed_demand, scenario$modeled_bed_demand),
      allocated_beds = c(baseline$allocated_beds, scenario$allocated_beds),
      unmet_beds = c(baseline$unmet_beds, scenario$unmet_beds),
      stringsAsFactors = FALSE
    )
  })
  output$demand_comparison_plot <- renderPlotly({
    ggplotly(ggplot(comparison_data(), aes(department, modeled_bed_demand, fill = series)) +
      geom_col(position = "dodge") + labs(x = NULL, y = "Modeled bed demand", fill = NULL) + theme_minimal())
  })
  output$allocation_comparison_plot <- renderPlotly({
    ggplotly(ggplot(comparison_data(), aes(department, allocated_beds, fill = series)) +
      geom_col(position = "dodge") + labs(x = NULL, y = "Allocated beds", fill = NULL) + theme_minimal())
  })
  output$shortage_plot <- renderPlotly({
    x <- comparison_data()
    ggplotly(ggplot(x, aes(reorder(department, unmet_beds), unmet_beds, fill = series)) +
      geom_col(position = "dodge") + coord_flip() + labs(x = NULL, y = "Estimated unmet beds", fill = NULL) + theme_minimal())
  })
  output$summary_comparison_plot <- renderPlotly({
    x <- calculations()
    values <- data.frame(
      comparison = rep(c("Baseline", "Selected scenario"), 2),
      measure = c(rep("Total unmet beds", 2), rep("Capacity utilization (%)", 2)),
      value = c(x$baseline_summary$total_unmet_demand, x$summary$total_unmet_demand,
                x$baseline_summary$capacity_utilization_pct, x$summary$capacity_utilization_pct)
    )
    ggplotly(ggplot(values, aes(comparison, value, fill = comparison)) + geom_col(show.legend = FALSE) +
      facet_wrap(~measure, scales = "free_y") + labs(x = NULL, y = NULL) + theme_minimal())
  })
  output$shortage_change_table <- renderDT({
    x <- calculations()$active
    x <- x[order(-x$unmet_change, -x$unmet_beds, x$department),
      c("department", "baseline_unmet_beds", "unmet_beds", "unmet_change", "shortage_pct")]
    datatable(x, rownames = FALSE, options = list(pageLength = 6, dom = "t"))
  })

  output$policy_comparison_table <- renderDT({
    x <- calculations()$policy_comparison$comparison
    datatable(x, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
  })
  output$policy_comparison_plot <- renderPlotly({
    x <- calculations()$policy_comparison
    floor_unmet <- if (is.null(x$minimum_floor)) NA_real_ else sum(x$minimum_floor$unmet_beds)
    values <- data.frame(
      policy = c("Weighted balanced shortage", "Minimum department floor"),
      unmet = c(sum(x$weighted$unmet_beds), floor_unmet)
    )
    values <- values[is.finite(values$unmet), , drop = FALSE]
    ggplotly(ggplot(values, aes(policy, unmet, fill = policy)) + geom_col(show.legend = FALSE) +
      labs(x = NULL, y = "Total estimated unmet beds") + theme_minimal())
  })
  output$policy_shortage_plot <- renderPlotly({
    x <- calculations()$policy_comparison$comparison
    values <- data.frame(
      department = rep(x$department, 2),
      policy = rep(c("Weighted balanced shortage", "Minimum department floor"), each = nrow(x)),
      unmet_beds = c(x$weighted_unmet, x$floor_unmet),
      stringsAsFactors = FALSE
    )
    ggplotly(ggplot(values, aes(reorder(department, unmet_beds), unmet_beds, fill = policy)) +
      geom_col(position = "dodge") + coord_flip() +
      labs(x = NULL, y = "Estimated unmet beds", fill = NULL) + theme_minimal())
  })
  output$policy_explanation <- renderText({
    x <- calculations()$policy_comparison
    if (!is.null(x$minimum_floor_error)) {
      return(paste0("The minimum-floor policy is infeasible for these demand and capacity inputs: ",
                    x$minimum_floor_error, " The weighted balanced-shortage result remains available."))
    }
    paste0("Same scenario forecast and capacity were used for both runs. Weighted policy unmet demand: ",
      sum(x$weighted$unmet_beds), " beds; minimum-floor policy unmet demand: ",
      sum(x$minimum_floor$unmet_beds), " beds. The alternative requires at least ",
      round(input$minimum_share), "% of each department's rounded modeled demand, with the remaining capacity allocated by the same marginal shortage rule. ",
      "These are model outputs, not an assertion that one policy is clinically superior.")
  })
  output$policy_status <- renderText({
    error <- calculations()$policy_comparison$minimum_floor_error
    if (is.null(error)) "Both policies are feasible for the selected scenario." else paste("Alternative policy unavailable:", error)
  })

  output$forecast_plot <- renderPlotly({
    forecasts <- read_optional_result("demand_forecast.csv")
    require_result(forecasts, "Run R/03_forecasting.R from the project root.")
    forecasts$month <- as.Date(forecasts$month)
    p <- ggplot(forecasts, aes(month, forecast, color = department, group = department,
      text = paste0(department, "<br>", month, "<br>Forecast estimate: ", round(forecast)))) +
      geom_ribbon(aes(ymin = lower80, ymax = upper80, fill = department), alpha = .15, color = NA) +
      geom_line() + geom_point() + labs(x = NULL, y = "Forecast admissions", color = "Department", fill = "Department") + theme_minimal()
    ggplotly(p, tooltip = "text")
  })
  output$forecast_table <- renderDT({
    x <- require_result(read_optional_result("demand_forecast.csv"), "Run R/03_forecasting.R from the project root.")
    datatable(x, rownames = FALSE, options = list(pageLength = 8))
  })
  output$model_table <- renderDT({
    x <- require_result(read_optional_result("forecast_model_comparison.csv"), "Run R/03_forecasting.R from the project root.")
    datatable(x, rownames = FALSE, options = list(pageLength = 8))
  })
  output$risk_plot <- renderPlotly({
    x <- require_result(read_optional_result("simulation_summary.csv"), "Run R/05_simulation.R from the project root.")
    ggplotly(ggplot(x, aes(scenario, unmet_beds_p90, fill = scenario)) + geom_col(show.legend = FALSE) +
      labs(x = NULL, y = "90th percentile simulated unmet beds") + theme_minimal())
  })
  output$risk_table <- renderDT({
    x <- require_result(read_optional_result("simulation_summary.csv"), "Run R/05_simulation.R from the project root.")
    datatable(x, rownames = FALSE, options = list(pageLength = 8))
  })
}
shinyApp(ui, server)
