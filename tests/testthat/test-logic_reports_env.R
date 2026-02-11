# Test Logic - Environmental Statistics
#
# Tests for logic_reports_env.R
# Ported from V7mdlReportsEnv.txt

library(testthat)
library(here)
library(duckdb)

source(here("R", "logic_reports_env.R"))

test_that("summarize_env_numeric calculates correct statistics", {
  # VBA source: EnvReport() calculations in V7mdlReportsEnv.txt
  
  env_df <- data.frame(
    PlotNumber = c("001", "002", "003", "004", "005"),
    Elevation = c(450, 520, 380, 490, 510),
    SlopeGradient = c(15, 25, 10, 20, NA),
    Aspect = c(180, 90, 270, 180, 45),
    stringsAsFactors = FALSE
  )
  
  stats <- summarize_env_numeric(env_df)
  
  expect_true(nrow(stats) >= 3)
  
  # Check Elevation stats
  elev_stats <- stats[stats$Variable == "Elevation", ]
  expect_equal(elev_stats$Mean, round(mean(c(450, 520, 380, 490, 510)), 2))
  expect_equal(elev_stats$Min, 380)
  expect_equal(elev_stats$Max, 520)
  expect_equal(elev_stats$N, 5)
  
  # Check SlopeGradient stats (has NA)
  slope_stats <- stats[stats$Variable == "SlopeGradient", ]
  expect_equal(slope_stats$N, 4) # One NA
  expect_equal(slope_stats$Mean, round(mean(c(15, 25, 10, 20)), 2))
})

test_that("summarize_env_numeric auto-detects numeric columns", {
  env_df <- data.frame(
    PlotNumber = c("001", "002", "003"),
    Elevation = c(450, 520, 380),
    SlopeGradient = c(15, 25, 10),
    Zone = c("IDF", "IDF", "PP"),
    stringsAsFactors = FALSE
  )
  
  stats <- summarize_env_numeric(env_df, numeric_vars = NULL)
  
  # Should include Elevation and SlopeGradient but not Zone
  expect_true("Elevation" %in% stats$Variable)
  expect_true("SlopeGradient" %in% stats$Variable)
  expect_false("Zone" %in% stats$Variable)
})

test_that("summarize_env_categorical calculates correct frequencies", {
  env_df <- data.frame(
    PlotNumber = c("001", "002", "003", "004", "005"),
    MoistureRegime = c("5", "6", "5", "7", "5"),
    NutrientRegime = c("C", "C", "D", "C", "D"),
    stringsAsFactors = FALSE
  )
  
  freq <- summarize_env_categorical(env_df, c("MoistureRegime", "NutrientRegime"))
  
  expect_true(nrow(freq) > 0)
  
  # Check MoistureRegime "5" frequency
  mr5 <- freq[freq$Variable == "MoistureRegime" & freq$Category == "5", ]
  expect_equal(mr5$Count, 3L)
  expect_equal(mr5$Percent, 60.0)
  
  # Check NutrientRegime "C" frequency
  nrc <- freq[freq$Variable == "NutrientRegime" & freq$Category == "C", ]
  expect_equal(nrc$Count, 3L)
  expect_equal(nrc$Percent, 60.0)
})

test_that("summarize_env_categorical handles NA values", {
  env_df <- data.frame(
    PlotNumber = c("001", "002", "003", "004"),
    MoistureRegime = c("5", NA, "6", "5"),
    stringsAsFactors = FALSE
  )
  
  freq <- summarize_env_categorical(env_df, "MoistureRegime")
  
  # NA should be excluded from counts
  total_count <- sum(freq$Count)
  expect_equal(total_count, 3) # Only 3 non-NA values
})

test_that("transpose_env_for_report creates correct format", {
  # VBA source: EnvReport() transpose logic in V7mdlReportsEnv.txt
  
  env_df <- data.frame(
    PlotNumber = c("001", "002", "003"),
    Elevation = c(450, 520, 380),
    SlopeGradient = c(15, 25, 10),
    Zone = c("IDF", "IDF", "PP"),
    stringsAsFactors = FALSE
  )
  
  transposed <- transpose_env_for_report(env_df)
  
  expect_true("Variable" %in% names(transposed))
  expect_true("Plot_001" %in% names(transposed))
  expect_true("Plot_002" %in% names(transposed))
  expect_true("Plot_003" %in% names(transposed))
  
  # Check that variables are rows
  expect_true("Elevation" %in% transposed$Variable)
  expect_true("SlopeGradient" %in% transposed$Variable)
  expect_true("Zone" %in% transposed$Variable)
  
  # Check values
  elev_row <- transposed[transposed$Variable == "Elevation", ]
  expect_equal(elev_row$Plot_001, "450")
  expect_equal(elev_row$Plot_002, "520")
  expect_equal(elev_row$Plot_003, "380")
})

test_that("add_env_section_headers inserts headers correctly", {
  # VBA source: EnvReport() NULL row insertion in V7mdlReportsEnv.txt
  
  transposed <- data.frame(
    Variable = c("Elevation", "SlopeGradient", "SoilClassGroup", "StandAge"),
    Plot_001 = c("450", "15", "BR", "80"),
    Plot_002 = c("520", "25", "DY", "120"),
    stringsAsFactors = FALSE
  )
  
  result <- add_env_section_headers(transposed)
  
  expect_true(nrow(result) >= nrow(transposed))
  
  # Should contain section headers
  expect_true(any(grepl("SITE", result$Variable)))
  expect_true(any(grepl("SOIL", result$Variable)))
  expect_true(any(grepl("VEGETATION", result$Variable)))
})

test_that("calculate_env_completeness returns correct percentages", {
  env_df <- data.frame(
    PlotNumber = c("001", "002", "003"),
    Elevation = c(450, NA, 380),
    SlopeGradient = c(15, 25, NA),
    Aspect = c(180, 90, 270),
    stringsAsFactors = FALSE
  )
  
  completeness <- calculate_env_completeness(env_df)
  
  expect_equal(nrow(completeness), 3)
  
  # Plot 001: 3/3 fields = 100%
  plot1 <- completeness[completeness$PlotNumber == "001", ]
  expect_equal(plot1$PercentComplete, 100.0)
  
  # Plot 002: 2/3 fields = 66.7%
  plot2 <- completeness[completeness$PlotNumber == "002", ]
  expect_equal(plot2$PercentComplete, round(100 * 2 / 3, 1))
  
  # Plot 003: 2/3 fields = 66.7%
  plot3 <- completeness[completeness$PlotNumber == "003", ]
  expect_equal(plot3$PercentComplete, round(100 * 2 / 3, 1))
})

test_that("calculate_env_completeness handles specific required_fields", {
  env_df <- data.frame(
    PlotNumber = c("001", "002"),
    Elevation = c(450, NA),
    SlopeGradient = c(15, 25),
    Aspect = c(180, 90),
    Zone = c("IDF", "PP"),
    stringsAsFactors = FALSE
  )
  
  # Only check Elevation and SlopeGradient
  completeness <- calculate_env_completeness(env_df, required_fields = c("Elevation", "SlopeGradient"))
  
  expect_equal(completeness$FieldsTotal[1], 2)
  
  # Plot 001: 2/2 fields = 100%
  expect_equal(completeness$PercentComplete[1], 100.0)
  
  # Plot 002: 1/2 fields = 50%
  expect_equal(completeness$PercentComplete[2], 50.0)
})

test_that("format_env_var_names converts database names to labels", {
  # VBA source: EnvReport() SQL SELECT aliases in V7mdlReportsEnv.txt
  
  var_names <- c(
    "PlotNumber",
    "Elevation",
    "SlopeGradient",
    "MoistureRegime",
    "StrataCoverTree"
  )
  
  formatted <- format_env_var_names(var_names)
  
  expect_equal(formatted[1], "Plot")
  expect_equal(formatted[2], "Elevation (m)")
  expect_equal(formatted[3], "Slope Gradient (%)")
  expect_equal(formatted[4], "Moisture Regime")
  expect_equal(formatted[5], "Strata Cover Tree (%)")
})

test_that("build_env_summary_by_su returns complete summary", {
  skip_if_not_installed("duckdb")
  
  con <- dbConnect(duckdb(), dbdir = ":memory:")
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Create test tables
  dbExecute(con, "
    CREATE TABLE Sample_SU (
      PlotNumber VARCHAR,
      SiteUnit VARCHAR
    )
  ")
  
  dbExecute(con, "
    INSERT INTO Sample_SU VALUES
    ('001', 'SU1'),
    ('002', 'SU1'),
    ('003', 'SU2')
  ")
  
  dbExecute(con, "
    CREATE TABLE Sample_Env (
      PlotNumber VARCHAR,
      Elevation INTEGER,
      SlopeGradient INTEGER,
      MoistureRegime VARCHAR
    )
  ")
  
  dbExecute(con, "
    INSERT INTO Sample_Env VALUES
    ('001', 450, 15, '5'),
    ('002', 520, 25, '6'),
    ('003', 380, 10, '5')
  ")
  
  summary <- build_env_summary_by_su(
    con,
    site_unit = "SU1",
    numeric_vars = c("Elevation", "SlopeGradient"),
    categorical_vars = c("MoistureRegime")
  )
  
  expect_true(!is.null(summary$numeric_summary))
  expect_true(!is.null(summary$categorical_summary))
  expect_equal(summary$plot_count, 2) # SU1 has 2 plots
  
  # Check numeric summary
  elev_stats <- summary$numeric_summary[summary$numeric_summary$Variable == "Elevation", ]
  expect_equal(elev_stats$Mean, round(mean(c(450, 520)), 2))
})

test_that("transpose_env_for_report handles empty data", {
  env_df <- data.frame(
    PlotNumber = character(),
    Elevation = numeric(),
    stringsAsFactors = FALSE
  )
  
  result <- transpose_env_for_report(env_df)
  
  expect_equal(nrow(result), 0)
})

test_that("summarize_env_numeric handles all NA column", {
  env_df <- data.frame(
    PlotNumber = c("001", "002", "003"),
    Elevation = c(NA, NA, NA),
    stringsAsFactors = FALSE
  )
  
  stats <- summarize_env_numeric(env_df, numeric_vars = "Elevation")
  
  expect_equal(nrow(stats), 1)
  expect_true(is.na(stats$Mean[1]))
  expect_equal(stats$N[1], 0)
})
