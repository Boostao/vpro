# Test Logic - Quality Control Filtering
#
# Tests for logic_reports_qc.R
# Ported from V7mdlReportsQualityControl.txt

library(testthat)
library(here)
library(duckdb)

source(here("R", "logic_reports_qc.R"))

# Test database setup
setup_test_db <- function() {
  con <- dbConnect(duckdb(), dbdir = ":memory:")
  dbExecute(con, "CREATE SCHEMA lists")
  
  # Create quality list
  dbExecute(con, "
    CREATE TABLE lists.USysTableOfLists (
      ListName VARCHAR,
      Item VARCHAR,
      ItemOrder INTEGER,
      FieldUsedIn VARCHAR,
      Validate VARCHAR
    )
  ")
  
  dbExecute(con, "
    INSERT INTO lists.USysTableOfLists VALUES
    ('dataquality', 'Poor', 1, 'SitePlotQuality', 'Yes'),
    ('dataquality', 'Fair', 2, 'VegPlotQuality', 'Yes'),
    ('dataquality', 'Good', 3, 'SoilPlotQuality', 'Yes'),
    ('dataquality', 'Excellent', 4, '', 'Yes')
  ")
  
  # Create SU
  dbExecute(con, "
    CREATE TABLE SU (
      PlotNumber VARCHAR,
      SiteUnit VARCHAR
    )
  ")
  
  dbExecute(con, "
    INSERT INTO SU VALUES
    ('00001', 'SU1'),
    ('00002', 'SU1'),
    ('00003', 'SU2'),
    ('00004', 'SU2'),
    ('00005', 'SU3')
  ")
  
  # Create Env with quality fields
  dbExecute(con, "
    CREATE TABLE Env (
      PlotNumber VARCHAR,
      ProjectID VARCHAR,
      SitePlotQuality VARCHAR,
      VegPlotQuality VARCHAR,
      SoilPlotQuality VARCHAR,
      BEC_Use VARCHAR
    )
  ")
  
  dbExecute(con, "
    INSERT INTO Env VALUES
    ('00001', 'TEST', 'Excellent', 'Good', 'Good', 'A'),
    ('00002', 'TEST', 'Good', 'Fair', 'Good', 'B'),
    ('00003', 'TEST', 'Fair', 'Good', 'Poor', 'C'),
    ('00004', 'TEST', NULL, 'Good', 'Good', NULL),
    ('00005', 'OTHER', 'Poor', 'Poor', 'Poor', 'D')
  ")
  
  con
}

test_that("quality_to_order maps quality text correctly", {
  # VBA source: LevelAsNumber() in V7mdlReportsQualityControl.txt
  
  expect_equal(quality_to_order("Poor"), 1L)
  expect_equal(quality_to_order("Fair"), 2L)
  expect_equal(quality_to_order("Good"), 3L)
  expect_equal(quality_to_order("Excellent"), 4L)
  
  # Handle NULL/NA
  expect_equal(quality_to_order(NA), NA_integer_)
  expect_equal(quality_to_order(""), NA_integer_)
  expect_equal(quality_to_order("Unknown"), NA_integer_)
})

test_that("filter_plots_by_quality filters correctly with all criteria", {
  con <- setup_test_db()
  on.exit(dbDisconnect(con))
  
  # VBA source: QC() in V7mdlReportsQualityControl.txt
  
  # Filter with Good minimum, allowing NULLs
  result <- filter_plots_by_quality(
    con,
    project_id = "TEST",
    site_quality_min = "Good",
    veg_quality_min = "Good",
    soil_quality_min = "Good",
    site_allow_null = TRUE,
    veg_allow_null = TRUE,
    soil_allow_null = TRUE
  )
  
  # Should include: 00001 (all Good or better), 00002 (site Good, veg Fair - fails),
  # 00004 (NULL allowed)
  # Should exclude: 00003 (soil Poor)
  expect_true("00001" %in% result$PlotNumber)
  expect_true("00004" %in% result$PlotNumber) # NULL allowed
  expect_false("00002" %in% result$PlotNumber) # Veg is Fair
  expect_false("00003" %in% result$PlotNumber) # Soil is Poor
})

test_that("filter_plots_by_quality respects null handling", {
  con <- setup_test_db()
  on.exit(dbDisconnect(con))
  
  # Don't allow NULLs - should exclude plot 00004
  result <- filter_plots_by_quality(
    con,
    project_id = "TEST",
    site_quality_min = "Good",
    veg_quality_min = "Good",
    soil_quality_min = "Good",
    site_allow_null = FALSE,
    veg_allow_null = TRUE,
    soil_allow_null = TRUE
  )
  
  expect_false("00004" %in% result$PlotNumber)
  expect_true("00001" %in% result$PlotNumber)
})

test_that("filter_plots_by_quality with enforce_filter=FALSE returns all plots", {
  con <- setup_test_db()
  on.exit(dbDisconnect(con))
  
  # VBA source: If DataQualityFilterEnforce = False logic
  
  result <- filter_plots_by_quality(
    con,
    project_id = "TEST",
    enforce_filter = FALSE
  )
  
  # Should return all 4 plots from TEST project
  expect_equal(nrow(result), 4)
  expect_true(all(c("00001", "00002", "00003", "00004") %in% result$PlotNumber))
})

test_that("identify_removed_plots correctly identifies removal reasons", {
  con <- setup_test_db()
  on.exit(dbDisconnect(con))
  
  # VBA source: FillRemovedBy() in V7mdlReportsQualityControl.txt
  
  original_plots <- c("00001", "00002", "00003", "00005")
  filtered_plots <- c("00001")
  
  removed <- identify_removed_plots(
    con,
    original_plots,
    filtered_plots,
    site_quality_min = "Good",
    veg_quality_min = "Good",
    soil_quality_min = "Good"
  )
  
  # Check that removed plots are identified
  expect_true("00002" %in% removed$PlotNumber) # Fair veg
  expect_true("00003" %in% removed$PlotNumber) # Poor soil
  expect_true("00005" %in% removed$PlotNumber) # All Poor
  
  # Check reasons
  veg_removed <- removed[removed$PlotNumber == "00002", ]
  expect_equal(veg_removed$RemovedBy, "Veg")
  
  soil_removed <- removed[removed$PlotNumber == "00003", ]
  expect_true(soil_removed$RemovedBy %in% c("Soil", "Mixed")) # Could be soil or mixed with site
  
  mixed_removed <- removed[removed$PlotNumber == "00005", ]
  expect_equal(mixed_removed$RemovedBy, "Mixed") # All three are Poor
})

test_that("get_quality_summary returns correct counts", {
  con <- setup_test_db()
  on.exit(dbDisconnect(con))
  
  summary <- get_quality_summary(con)
  
  expect_true(nrow(summary) > 0)
  expect_true("SitePlotQuality" %in% names(summary))
  expect_true("Count" %in% names(summary))
})

test_that("filter_plots_by_quality handles site_unit filter", {
  con <- setup_test_db()
  on.exit(dbDisconnect(con))
  
  result <- filter_plots_by_quality(
    con,
    site_unit = "SU1",
    site_quality_min = "Good",
    veg_quality_min = "Fair",
    soil_quality_min = "Good"
  )
  
  # SU1 has plots 00001 and 00002
  # 00001: Excellent/Good/Good - passes
  # 00002: Good/Fair/Good - passes (Fair >= Fair)
  expect_true(all(result$PlotNumber %in% c("00001", "00002")))
  expect_equal(nrow(result), 2)
})

test_that("filter_plots_by_quality handles plot_list parameter", {
  con <- setup_test_db()
  on.exit(dbDisconnect(con))
  
  result <- filter_plots_by_quality(
    con,
    plot_list = c("00001", "00003", "00005"),
    site_quality_min = "Good",
    veg_quality_min = "Good",
    soil_quality_min = "Good",
    site_allow_null = FALSE,
    veg_allow_null = FALSE,
    soil_allow_null = FALSE
  )
  
  # Only 00001 should pass (Excellent/Good/Good)
  expect_equal(nrow(result), 1)
  expect_equal(result$PlotNumber[1], "00001")
})

test_that("build_quality_filter constructs correct SQL fragments", {
  con <- setup_test_db()
  on.exit(dbDisconnect(con))
  
  qc <- build_quality_filter(
    con,
    site_quality_min = "Good",
    veg_quality_min = "Fair",
    soil_quality_min = "Good",
    site_allow_null = TRUE,
    veg_allow_null = FALSE,
    soil_allow_null = TRUE,
    bec_use_min = "B",
    bec_allow_null = FALSE
  )
  
  expect_equal(qc$site_order, 3L)
  expect_equal(qc$veg_order, 2L)
  expect_equal(qc$soil_order, 3L)
  expect_equal(qc$site_null_sql, " OR")
  expect_equal(qc$veg_null_sql, " AND NOT")
  expect_equal(qc$soil_null_sql, " OR")
  expect_true(grepl("BEC_Use >= 'B'", qc$bec_filter))
  expect_true(grepl("IS NOT NULL", qc$bec_filter))
})
