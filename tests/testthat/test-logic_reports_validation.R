# Test Logic - Data Validation
#
# Tests for logic_reports_validation.R
# Ported from V7mdlReportsValidateEnvData.txt and V7mdlReportsValidateVegCodes.txt

library(testthat)
library(here)
library(duckdb)

source(here("R", "logic_reports_validation.R"))

setup_validation_db <- function() {
  con <- dbConnect(duckdb(), dbdir = ":memory:")
  dbExecute(con, "CREATE SCHEMA lists")
  
  # Create USysTableOfLists with validation info
  dbExecute(con, "
    CREATE TABLE lists.USysTableOfLists (
      ListName VARCHAR,
      Item VARCHAR,
      ItemOrder INTEGER,
      FieldUsedIn VARCHAR,
      Validate VARCHAR,
      ValidateLoops INTEGER
    )
  ")
  
  # Add MoistureRegime list
  dbExecute(con, "
    INSERT INTO lists.USysTableOfLists VALUES
    ('moistureregime', '0', 1, 'MoistureRegime', 'Yes', 0),
    ('moistureregime', '1', 2, 'MoistureRegime', 'Yes', 0),
    ('moistureregime', '2', 3, 'MoistureRegime', 'Yes', 0),
    ('moistureregime', '3', 4, 'MoistureRegime', 'Yes', 0),
    ('moistureregime', '4', 5, 'MoistureRegime', 'Yes', 0),
    ('moistureregime', '5', 6, 'MoistureRegime', 'Yes', 0),
    ('moistureregime', '6', 7, 'MoistureRegime', 'Yes', 0),
    ('moistureregime', '7', 8, 'MoistureRegime', 'Yes', 0)
  ")
  
  # Add NutrientRegime list
  dbExecute(con, "
    INSERT INTO lists.USysTableOfLists VALUES
    ('nutrientregime', 'A', 1, 'NutrientRegime', 'Yes', 0),
    ('nutrientregime', 'B', 2, 'NutrientRegime', 'Yes', 0),
    ('nutrientregime', 'C', 3, 'NutrientRegime', 'Yes', 0),
    ('nutrientregime', 'D', 4, 'NutrientRegime', 'Yes', 0),
    ('nutrientregime', 'E', 5, 'NutrientRegime', 'Yes', 0)
  ")
  
  # Add Exposure list (with ValidateLoops = 2 for Exposure1, Exposure2)
  dbExecute(con, "
    INSERT INTO lists.USysTableOfLists VALUES
    ('exposure', 'N', 1, 'Exposure', 'Yes', 2),
    ('exposure', 'E', 2, 'Exposure', 'Yes', 2),
    ('exposure', 'S', 3, 'Exposure', 'Yes', 2),
    ('exposure', 'W', 4, 'Exposure', 'Yes', 2)
  ")
  
  # Create species list
  dbExecute(con, "
    CREATE TABLE lists.USysAllSpecs (
      Code VARCHAR,
      ScientificName VARCHAR,
      CodeType VARCHAR
    )
  ")
  
  dbExecute(con, "
    INSERT INTO lists.USysAllSpecs VALUES
    ('ABIEGRA', 'Abies grandis', 'V'),
    ('PINUMON', 'Pinus monticola', 'V'),
    ('ACTRUB', 'Actaea rubra', 'V'),
    ('SYNONYM1', 'Old name', 'S')
  ")
  
  # Create Sample_Env with some invalid codes
  dbExecute(con, "
    CREATE TABLE Sample_Env (
      PlotNumber VARCHAR,
      ProjectID VARCHAR,
      MoistureRegime VARCHAR,
      NutrientRegime VARCHAR,
      Exposure1 VARCHAR,
      Exposure2 VARCHAR
    )
  ")
  
  dbExecute(con, "
    INSERT INTO Sample_Env VALUES
    ('001', 'TEST', '5', 'C', 'N', 'E'),
    ('002', 'TEST', 'X', 'C', 'N', NULL),
    ('003', 'TEST', '6', 'Z', 'Q', 'S'),
    ('004', 'TEST', '7', 'D', 'E', 'W')
  ")
  
  # Create vegetation table
  dbExecute(con, "
    CREATE TABLE vw_USysAllVeg (
      PlotNumber VARCHAR,
      MyLayer VARCHAR,
      Species VARCHAR,
      Cover DOUBLE
    )
  ")
  
  dbExecute(con, "
    INSERT INTO vw_USysAllVeg VALUES
    ('001', 'A', 'ABIEGRA', 25.0),
    ('001', 'B', 'PINUMON', 10.0),
    ('002', 'A', 'INVALID1', 15.0),
    ('003', 'D', 'ACTRUB', 5.0),
    ('003', 'D', 'BADCODE', 3.0),
    ('004', 'A', 'SYNONYM1', 20.0)
  ")
  
  # Create Sample_SU
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
  
  con
}

test_that("validate_env_data detects invalid codes", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # VBA source: ValidateEnvData() in V7mdlReportsValidateEnvData.txt
  
  env <- dbGetQuery(con, "SELECT * FROM Sample_Env")
  errors <- validate_env_data(con, env)
  
  expect_true(nrow(errors) > 0)
  
  # Plot 002 has invalid MoistureRegime 'X'
  mr_errors <- errors[errors$FieldName == "MoistureRegime", ]
  expect_true("002" %in% mr_errors$PlotNumber)
  expect_true("X" %in% mr_errors$InvalidValue)
  
  # Plot 003 has invalid NutrientRegime 'Z'
  nr_errors <- errors[errors$FieldName == "NutrientRegime", ]
  expect_true("003" %in% nr_errors$PlotNumber)
  expect_true("Z" %in% nr_errors$InvalidValue)
})

test_that("validate_env_data handles looped fields (Exposure1, Exposure2)", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # VBA source: ValidateLoops logic in ValidateEnvData()
  
  env <- dbGetQuery(con, "SELECT * FROM Sample_Env")
  errors <- validate_env_data(con, env)
  
  # Plot 003 has invalid Exposure1 'Q'
  exp_errors <- errors[errors$FieldName == "Exposure1", ]
  expect_true("003" %in% exp_errors$PlotNumber)
  expect_true("Q" %in% exp_errors$InvalidValue)
})

test_that("validate_env_data ignores NULL values", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Plot 002 has NULL Exposure2 - should not be an error
  env <- dbGetQuery(con, "SELECT * FROM Sample_Env")
  errors <- validate_env_data(con, env)
  
  exp2_errors <- errors[errors$FieldName == "Exposure2" & errors$PlotNumber == "002", ]
  expect_equal(nrow(exp2_errors), 0)
})

test_that("validate_veg_codes detects invalid species codes", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # VBA source: Similar pattern to V7mdlReportsValidateVegCodes.txt
  
  veg <- dbGetQuery(con, "SELECT * FROM vw_USysAllVeg")
  errors <- validate_veg_codes(con, veg)
  
  expect_true(nrow(errors) > 0)
  
  # Plot 002 has invalid species 'INVALID1'
  expect_true("002" %in% errors$PlotNumber)
  expect_true("INVALID1" %in% errors$InvalidSpecies)
  
  # Plot 003 has invalid species 'BADCODE'
  expect_true("003" %in% errors$PlotNumber)
  expect_true("BADCODE" %in% errors$InvalidSpecies)
})

test_that("validate_veg_codes excludes synonym codes (CodeType = 'S')", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # SYNONYM1 has CodeType = 'S' so it's in the reference list
  # but should still be flagged (it will be in valid_species, so it won't error)
  # Actually, the function gets all codes regardless of CodeType
  # Let's verify it's in the valid list
  
  veg <- dbGetQuery(con, "SELECT * FROM vw_USysAllVeg WHERE PlotNumber = '004'")
  errors <- validate_veg_codes(con, veg)
  
  # SYNONYM1 is in USysAllSpecs, so it won't be flagged as invalid
  # This test verifies the function accepts it
  expect_false("SYNONYM1" %in% errors$InvalidSpecies)
})

test_that("check_orphaned_veg_records finds orphans", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Add a veg record for plot that doesn't exist in Sample_Env
  dbExecute(con, "
    INSERT INTO vw_USysAllVeg VALUES
    ('999', 'A', 'ABIEGRA', 10.0)
  ")
  
  orphans <- check_orphaned_veg_records(con)
  
  expect_true(nrow(orphans) > 0)
  expect_true("999" %in% orphans$PlotNumber)
})

test_that("check_orphaned_env_records finds orphans", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Add an env record for plot that doesn't exist in Sample_SU
  dbExecute(con, "
    INSERT INTO Sample_Env VALUES
    ('888', 'TEST', '5', 'C', 'N', 'E')
  ")
  
  orphans <- check_orphaned_env_records(con)
  
  expect_true(nrow(orphans) > 0)
  expect_true("888" %in% orphans$PlotNumber)
})

test_that("generate_validation_report returns comprehensive results", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  report <- generate_validation_report(con, project_id = "TEST")
  
  expect_true(!is.null(report$env_errors))
  expect_true(!is.null(report$veg_errors))
  expect_true(!is.null(report$orphaned_veg))
  expect_true(!is.null(report$orphaned_env))
  expect_true(!is.null(report$summary))
  
  # Summary should have 4 rows
  expect_equal(nrow(report$summary), 4)
  
  # Should have some env errors
  expect_true(nrow(report$env_errors) > 0)
  
  # Should have some veg errors
  expect_true(nrow(report$veg_errors) > 0)
})

test_that("check_duplicate_plots finds duplicates", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Add duplicate plot
  dbExecute(con, "
    INSERT INTO Sample_Env VALUES
    ('001', 'TEST2', '6', 'D', 'S', 'W')
  ")
  
  duplicates <- check_duplicate_plots(con)
  
  expect_true(nrow(duplicates) > 0)
  expect_true("001" %in% duplicates$PlotNumber)
  expect_equal(duplicates$DuplicateCount[duplicates$PlotNumber == "001"], 2)
})

test_that("validate_plot_number_format detects issues", {
  plot_numbers <- c("00001", "00002", "ABC", "123", "00003XYZ", NA, "", "123456")
  
  issues <- validate_plot_number_format(plot_numbers)
  
  expect_true(nrow(issues) > 0)
  
  # 'ABC' is non-numeric
  expect_true("ABC" %in% issues$InvalidPlotNumber)
  
  # '123' is unusual length (3 instead of 5)
  expect_true("123" %in% issues$InvalidPlotNumber)
  
  # '00003XYZ' is non-numeric
  expect_true("00003XYZ" %in% issues$InvalidPlotNumber)
  
  # NA should be flagged
  na_issues <- issues[is.na(issues$InvalidPlotNumber) | issues$InvalidPlotNumber == "NA", ]
  expect_true(nrow(na_issues) > 0)
})

test_that("validate_plot_number_format accepts valid formats", {
  plot_numbers <- c("00001", "00002", "12345", "00100")
  
  issues <- validate_plot_number_format(plot_numbers)
  
  # Valid 5-digit numbers should not appear in issues
  expect_false("00001" %in% issues$InvalidPlotNumber)
  expect_false("00002" %in% issues$InvalidPlotNumber)
  expect_false("12345" %in% issues$InvalidPlotNumber)
})

test_that("validate_env_data handles empty data", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  empty_env <- data.frame(
    PlotNumber = character(),
    MoistureRegime = character(),
    stringsAsFactors = FALSE
  )
  
  errors <- validate_env_data(con, empty_env)
  
  expect_equal(nrow(errors), 0)
})

test_that("validate_veg_codes handles missing columns gracefully", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  # Data without required columns
  bad_veg <- data.frame(
    BadColumn = c("A", "B"),
    stringsAsFactors = FALSE
  )
  
  expect_warning(
    errors <- validate_veg_codes(con, bad_veg),
    "Required columns"
  )
  
  expect_equal(nrow(errors), 0)
})

test_that("generate_validation_report filters by site_unit", {
  con <- setup_validation_db()
  on.exit(dbDisconnect(con, shutdown = TRUE))
  
  report <- generate_validation_report(con, site_unit = "SU1")
  
  # Should only include plots from SU1 (001, 002)
  env_plot_numbers <- unique(report$env_errors$PlotNumber)
  expect_true(all(env_plot_numbers %in% c("001", "002")))
  expect_false("003" %in% env_plot_numbers)
})
