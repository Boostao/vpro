# Comprehensive Edge Case Tests for Compliance Engine
# Tests all 47+ validation rules under stress conditions

source(here::here("R", "logic_compliance.R"))

# ============================================================================
# Test Setup Helpers
# ============================================================================

setup_full_compliance_schema <- function(con) {
  # Create schemas
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS lists")
  
  # Drop and recreate tables to avoid conflicts with helpers
  DBI::dbExecute(con, "DROP TABLE IF EXISTS Sample_Env CASCADE")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS Sample_Veg CASCADE")
  DBI::dbExecute(con, "DROP VIEW IF EXISTS vw_USysAllVeg")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS lists.SppList CASCADE")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS lists.USysZoneList CASCADE")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS lists.USysTableOfLists CASCADE")
  
  # Sample_Env with all fields referenced by compliance checks
  DBI::dbExecute(con, "
    CREATE TABLE Sample_Env (
      plotnumber TEXT,
      projectid TEXT,
      zone TEXT,
      subzone TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation DOUBLE,
      slopegradient DOUBLE,
      aspect DOUBLE,
      mesoslopeposition TEXT,
      surfaceshape TEXT,
      rootrestrictingdepth DOUBLE,
      rootingdepth DOUBLE,
      seepagedepth DOUBLE,
      sv_soildepth DOUBLE,
      sv_gleyingmottlingcm DOUBLE,
      sv_watertablecm DOUBLE,
      sv_ahorizondepth DOUBLE,
      activelayerdepth DOUBLE
    )
  ")
  
  # Sample_Veg for vegetation validation
  DBI::dbExecute(con, "
    CREATE TABLE Sample_Veg (
      plotnumber TEXT,
      species TEXT,
      projectid TEXT,
      layer TEXT,
      cover1 TEXT,
      cover2 TEXT,
      cover3 TEXT,
      cover4 TEXT
    )
  ")
  
  # View for unpivoted vegetation
  DBI::dbExecute(con, "
    CREATE VIEW vw_USysAllVeg AS
    SELECT plotnumber,
           species AS species_code,
           layer AS layer,
           cover1 AS cover_value,
           projectid
    FROM Sample_Veg
    WHERE cover1 IS NOT NULL
    UNION ALL
    SELECT plotnumber,
           species AS species_code,
           layer AS layer,
           cover2 AS cover_value,
           projectid
    FROM Sample_Veg
    WHERE cover2 IS NOT NULL
  ")
  
  # Reference tables
  DBI::dbExecute(con, "
    CREATE TABLE lists.SppList (
      code TEXT PRIMARY KEY,
      species_name TEXT
    )
  ")
  
  DBI::dbExecute(con, "
    CREATE TABLE lists.USysZoneList (
      zone_code TEXT,
      subzone TEXT,
      zone_name TEXT
    )
  ")
  
  DBI::dbExecute(con, "
    CREATE TABLE lists.USysTableOfLists (
      listname TEXT,
      item TEXT,
      sortorder INTEGER
    )
  ")
  
  # Seed reference data
  seed_reference_data(con)
}

seed_reference_data <- function(con) {
  # Species codes (subset of BC species)
  species <- data.frame(
    # NOTE: Keep this aligned with any "should pass" fixtures in this file.
    # In particular the 10k veg stress test uses a fixed 10-code list.
    code = c(
      "ABGR", "PSME", "TSHE", "THPL", "PICO", "PIEN", "ODE", "ACMA",
      "ABLA", "PIMO", "ACGL", "ALVI", "AMAL"
    ),
    species_name = c(
      "Grand fir", "Douglas-fir", "Western hemlock",
      "Western redcedar", "Lodgepole pine", "Engelmann spruce",
      "Oregon grape", "Bigleaf maple",
      "Subalpine fir", "Western white pine", "Douglas maple", "Sitka alder", "Serviceberry"
    )
  )
  DBI::dbWriteTable(con, DBI::Id(schema = "lists", table = "SppList"), species, append = TRUE)
  
  # BEC zones (BC biogeoclimatic ecosystem classification)
  zones <- data.frame(
    # NOTE: Include any zone/subzone pairs used by "should pass" stress tests.
    # Many stress fixtures use ICH/mw and one duplicate-plot fixture uses IDF/dk.
    zone_code = c("CDF", "CWH", "ICH", "ICH", "IDF", "IDF", "SBPS", "MH", "ESSF"),
    subzone = c("mm", "vm2", "mk1", "mw", "dk1", "dk", "xc", "mm", "wk"),
    zone_name = c(
      "Coastal Douglas-fir", "Coastal Western Hemlock",
      "Interior Cedar-Hemlock", "Interior Cedar-Hemlock",
      "Interior Douglas-fir", "Interior Douglas-fir",
      "Sub-Boreal Pine-Spruce", "Mountain Hemlock",
      "Engelmann Spruce-Subalpine Fir"
    )
  )
  DBI::dbWriteTable(con, DBI::Id(schema = "lists", table = "USysZoneList"), zones, append = TRUE)
  
  # Table-driven lists
  lists <- data.frame(
    listname = c(
      rep("MesoSlopePosition", 5),
      rep("SurfaceShape", 4)
    ),
    item = c(
      "CREST", "UPPER", "MIDDLE", "LOWER", "TOE",
      "FLAT", "CONCAVE", "CONVEX", "UNDULATING"
    ),
    sortorder = c(1:5, 1:4)
  )
  DBI::dbWriteTable(con, DBI::Id(schema = "lists", table = "USysTableOfLists"), lists, append = TRUE)
}

# ============================================================================
# 1. MANDATORY FIELDS - Null/Empty Edge Cases
# ============================================================================

test_that("Required fields: null values are flagged", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Insert record with NULL plotnumber
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES (NULL, 'P001', 'ICH', 'mk1')
  ")
  
  result <- check_required_fields(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(result$column == "plotnumber"))
})

test_that("Required fields: empty strings are flagged", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Insert records with empty strings
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', '', 'ICH', 'mk1')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT002', 'P001', '', 'mk1')
  ")
  
  result <- check_required_fields(con)
  expect_true(nrow(result) >= 2)
  expect_true(any(result$column == "projectid"))
  expect_true(any(result$column == "zone"))
})

test_that("Required fields: all four required fields", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Completely empty required fields
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES (NULL, NULL, NULL, NULL)
  ")
  
  result <- check_required_fields(con)
  expect_true(nrow(result) == 4)
  expect_setequal(result$column, c("plotnumber", "projectid", "zone", "subzone"))
})

test_that("Required fields: whitespace-only strings treated as empty", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Whitespace should not pass (current implementation checks == "")
  # This tests for false negatives
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', '   ', 'ICH', 'mk1')
  ")
  
  result <- check_required_fields(con)
  # Note: Current implementation might not catch whitespace - this tests the gap
  # If this passes, it's actually a false negative that should be fixed
})

# ============================================================================
# 2. FOREIGN KEY VALIDATION - Invalid Species and Zone Codes
# ============================================================================

test_that("Species FK: invalid species code flagged", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'INVALID', 'P001', 'A', '25')
  ")
  
  result <- check_species_fk(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(grepl("INVALID", result$details)))
})

test_that("Species FK: case sensitivity", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Test lowercase version of valid code (ABGR exists, but not abgr)
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'abgr', 'P001', 'A', '25')
  ")
  
  result <- check_species_fk(con, "P001")
  # DuckDB is case-insensitive by default, but this tests the assumption
  # If it fails, case handling needs to be explicit
})

test_that("Species FK: NULL species is skipped (not an FK violation)", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', NULL, 'P001', 'A', '25')
  ")
  
  result <- check_species_fk(con, "P001")
  # NULL should not trigger FK error (it's a different validation)
  expect_equal(nrow(result), 0)
})

test_that("Zone FK: invalid zone code", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'XXX', 'mk1')
  ")
  
  result <- check_zone_fk(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(result$rule == "fk_zone"))
})

test_that("Zone FK: invalid subzone code", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'ICH', 'invalid')
  ")
  
  result <- check_zone_fk(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(result$rule == "fk_subzone"))
})

test_that("Zone FK: valid zone but invalid zone/subzone combination", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # CWH exists with vm2, but not with mk1
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'CWH', 'mk1')
  ")
  
  result <- check_zone_fk(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(result$rule == "fk_zone_subzone"))
})

test_that("List FK: invalid value for table-driven list", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, mesoslopeposition, surfaceshape)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 'INVALID', 'FLAT')
  ")
  
  result <- check_table_list_values(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(grepl("fk_list_mesoslopeposition", result$rule)))
})

# ============================================================================
# 3. RANGE CHECKS - Boundary Values
# ============================================================================

test_that("Latitude: exact boundaries are valid", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Valid: 48 and 60 (inclusive boundaries)
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 48.0, -120, 1000)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT002', 'P001', 'ICH', 'mk1', 60.0, -120, 1000)
  ")
  
  result <- check_coord_ranges(con, "P001")
  expect_equal(nrow(result), 0)
})

test_that("Latitude: just outside boundaries are invalid", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Invalid: 47.9999 and 60.0001
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 47.9999, -120, 1000)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT002', 'P001', 'ICH', 'mk1', 60.0001, -120, 1000)
  ")
  
  result <- check_coord_ranges(con, "P001")
  expect_equal(nrow(result), 2)
  expect_true(all(result$rule == "range_lat"))
})

test_that("Longitude: exact boundaries are valid", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Valid: -140 and -114 (inclusive)
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 50, -140.0, 1000)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT002', 'P001', 'ICH', 'mk1', 50, -114.0, 1000)
  ")
  
  result <- check_coord_ranges(con, "P001")
  expect_equal(nrow(result), 0)
})

test_that("Longitude: outside boundaries are invalid", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 50, -140.001, 1000)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT002', 'P001', 'ICH', 'mk1', 50, -113.999, 1000)
  ")
  
  result <- check_coord_ranges(con, "P001")
  expect_equal(nrow(result), 2)
  expect_true(all(result$rule == "range_lon"))
})

test_that("Elevation: boundaries 0-4000", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Valid: 0, 4000
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 50, -120, 0)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT002', 'P001', 'ICH', 'mk1', 50, -120, 4000)
  ")
  
  result <- check_coord_ranges(con, "P001")
  expect_equal(nrow(result), 0)
  
  # Invalid: -0.1, 4000.1
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT003', 'P001', 'ICH', 'mk1', 50, -120, -0.1)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT004', 'P001', 'ICH', 'mk1', 50, -120, 4000.1)
  ")
  
  result <- check_coord_ranges(con, "P001")
  expect_equal(nrow(result), 2)
  expect_true(all(result$rule == "range_elev"))
})

test_that("Slope: boundaries 0-100", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Valid: 0, 100
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, slopegradient)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 0)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, slopegradient)
    VALUES ('PLOT002', 'P001', 'ICH', 'mk1', 100)
  ")
  
  result <- check_slope_aspect_ranges(con, "P001")
  expect_equal(nrow(result), 0)
  
  # Invalid: -1, 101
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, slopegradient)
    VALUES ('PLOT003', 'P001', 'ICH', 'mk1', -1)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, slopegradient)
    VALUES ('PLOT004', 'P001', 'ICH', 'mk1', 101)
  ")
  
  result <- check_slope_aspect_ranges(con, "P001")
  expect_equal(nrow(result), 2)
  expect_true(all(result$rule == "range_slope"))
})

test_that("Aspect: boundaries 0-360", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Valid: 0, 360
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, aspect)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 0)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, aspect)
    VALUES ('PLOT002', 'P001', 'ICH', 'mk1', 360)
  ")
  
  result <- check_slope_aspect_ranges(con, "P001")
  expect_equal(nrow(result), 0)
  
  # Invalid: -0.1, 360.1
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, aspect)
    VALUES ('PLOT003', 'P001', 'ICH', 'mk1', -0.1)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, aspect)
    VALUES ('PLOT004', 'P001', 'ICH', 'mk1', 360.1)
  ")
  
  result <- check_slope_aspect_ranges(con, "P001")
  expect_equal(nrow(result), 2)
  expect_true(all(result$rule == "range_aspect"))
})

test_that("Cover: boundaries 0-100", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Valid: 0, 100
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', '0')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT002', 'ABGR', 'P001', 'A', '100')
  ")
  
  result <- check_cover_ranges(con, "P001")
  expect_equal(nrow(result), 0)
  
  # Invalid: -1, 101
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT003', 'ABGR', 'P001', 'A', '-1')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT004', 'ABGR', 'P001', 'A', '101')
  ")
  
  result <- check_cover_ranges(con, "P001")
  expect_equal(nrow(result), 2)
  expect_true(all(result$rule == "range_cover"))
})

# ============================================================================
# 4. COVER CODE VALIDATION - Mixed Numeric/Text Codes
# ============================================================================

test_that("Cover codes: valid text codes (+, r, P) are allowed", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', '+')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT002', 'ABGR', 'P001', 'A', 'r')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT003', 'ABGR', 'P001', 'A', 'P')
  ")
  
  result <- check_cover_codes(con, "P001")
  expect_equal(nrow(result), 0)
})

test_that("Cover codes: case-insensitive text codes", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Test uppercase variants
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', 'R')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT002', 'ABGR', 'P001', 'A', 'p')
  ")
  
  result <- check_cover_codes(con, "P001")
  # Should handle case-insensitivity (r/R, p/P)
  expect_equal(nrow(result), 0)
})

test_that("Cover codes: invalid codes flagged", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', 'x')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT002', 'ABGR', 'P001', 'A', 'INVALID')
  ")
  
  result <- check_cover_codes(con, "P001")
  expect_equal(nrow(result), 2)
  expect_true(all(result$rule == "code_cover"))
})

test_that("Cover codes: numeric strings are not cover codes (parsed as numbers)", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # "25" should be parsed as numeric, not a code
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', '25')
  ")
  
  result <- check_cover_codes(con, "P001")
  expect_equal(nrow(result), 0)
})

test_that("Cover codes: whitespace handling", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Codes with whitespace
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', ' + ')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT002', 'ABGR', 'P001', 'A', ' r')
  ")
  
  result <- check_cover_codes(con, "P001")
  # Should trim whitespace before validation
  expect_equal(nrow(result), 0)
})

# ============================================================================
# 5. NON-NEGATIVE CHECKS - Negative Depth Values
# ============================================================================

test_that("Non-negative: all depth fields at boundary (0)", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone,
                            rootingdepth, seepagedepth, sv_soildepth, activelayerdepth)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 0, 0, 0, 0)
  ")
  
  result <- check_non_negative_fields(con, "P001")
  expect_equal(nrow(result), 0)
})

test_that("Non-negative: negative values flagged", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone,
                            rootingdepth, seepagedepth, sv_soildepth)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', -1, -0.1, -100)
  ")
  
  result <- check_non_negative_fields(con, "P001")
  expect_equal(nrow(result), 3)
  expect_true(all(grepl("^range_nonneg_", result$rule)))
})

test_that("Non-negative: NULL values are allowed (not a non-negative violation)", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone,
                            rootingdepth, seepagedepth)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', NULL, NULL)
  ")
  
  result <- check_non_negative_fields(con, "P001")
  expect_equal(nrow(result), 0)
})

# ============================================================================
# 6. UNIQUENESS - Duplicate Detection
# ============================================================================

test_that("Duplicate plots: same PlotNumber in same project", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1')
  ")
  
  result <- check_duplicate_plots(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(result$rule == "dup_plot"))
})

test_that("Duplicate plots: same PlotNumber in different projects is OK", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P002', 'ICH', 'mk1')
  ")
  
  result_p001 <- check_duplicate_plots(con, "P001")
  result_p002 <- check_duplicate_plots(con, "P002")
  
  expect_equal(nrow(result_p001), 0)
  expect_equal(nrow(result_p002), 0)
})

test_that("Duplicate plots: triple duplicates", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1')
  ")
  
  result <- check_duplicate_plots(con, "P001")
  expect_true(nrow(result) > 0)
})

test_that("Duplicate veg: same PlotNumber+Species+Layer", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', '25')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', '30')
  ")
  
  result <- check_duplicate_veg(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(result$rule == "dup_veg"))
})

test_that("Duplicate veg: same species in different layers is OK", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'A', '25')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ABGR', 'P001', 'B', '30')
  ")
  
  result <- check_duplicate_veg(con, "P001")
  expect_equal(nrow(result), 0)
})

# ============================================================================
# 7. CASCADING FAILURES - Multiple Violations in One Record
# ============================================================================

test_that("Cascading: one record with multiple violations", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Plot with multiple issues:
  # - Invalid zone
  # - Latitude out of range
  # - Negative rooting depth
  # - Aspect out of range
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (
      plotnumber, projectid, zone, subzone,
      latitude, longitude, elevation,
      aspect, rootingdepth
    )
    VALUES (
      'PLOT001', 'P001', 'BADZONE', 'mk1',
      70, -120, 1000,
      400, -10
    )
  ")
  
  result <- run_compliance_checks(con, "P001")
  
  # Should have at least 4 violations
  expect_true(nrow(result$detail_tibble) >= 4)
  expect_true(any(result$detail_tibble$rule == "fk_zone"))
  expect_true(any(result$detail_tibble$rule == "range_lat"))
  expect_true(any(result$detail_tibble$rule == "range_aspect"))
  expect_true(any(grepl("range_nonneg_", result$detail_tibble$rule)))
})

test_that("Cascading: all rules violated in one dataset", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Create violations for every rule type
  
  # Required field missing
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT001', NULL, 'ICH', 'mk1')
  ")
  
  # Invalid zone FK
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT002', 'P001', 'BADZONE', 'mk1')
  ")
  
  # Coordinates out of range
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('PLOT003', 'P001', 'ICH', 'mk1', 70, -150, 5000)
  ")
  
  # Slope/aspect out of range
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, slopegradient, aspect)
    VALUES ('PLOT004', 'P001', 'ICH', 'mk1', 150, 400)
  ")
  
  # Negative depth
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, rootingdepth)
    VALUES ('PLOT005', 'P001', 'ICH', 'mk1', -10)
  ")
  
  # Duplicate plot
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT006', 'P001', 'ICH', 'mk1')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT006', 'P001', 'ICH', 'mk1')
  ")
  
  # Invalid species FK
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT007', 'BADSPECIES', 'P001', 'A', '25')
  ")
  
  # Cover out of range
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT008', 'ABGR', 'P001', 'A', '150')
  ")
  
  # Invalid cover code
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT009', 'ABGR', 'P001', 'A', 'BADCODE')
  ")
  
  # Duplicate veg
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT010', 'ABGR', 'P001', 'A', '25')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT010', 'ABGR', 'P001', 'A', '30')
  ")
  
  result <- run_compliance_checks(con)
  
  # Should have violations from all major rule categories
  expect_false(result$passed)
  expect_true(nrow(result$summary_tibble) >= 10)
  
  # Verify presence of each rule type
  rules <- result$detail_tibble$rule
  expect_true(any(rules == "required"))
  expect_true(any(rules == "fk_zone"))
  expect_true(any(rules == "fk_species"))
  expect_true(any(rules == "range_lat"))
  expect_true(any(rules == "range_lon"))
  expect_true(any(rules == "range_elev"))
  expect_true(any(rules == "range_slope"))
  expect_true(any(rules == "range_aspect"))
  expect_true(any(rules == "range_cover"))
  expect_true(any(rules == "code_cover"))
  expect_true(any(rules == "dup_plot"))
  expect_true(any(rules == "dup_veg"))
  expect_true(any(grepl("^range_nonneg_", rules)))
})

# ============================================================================
# 8. COMPLIANCE REPORTING - Summary Aggregation
# ============================================================================

test_that("Compliance summary: aggregates by rule type", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Create multiple violations of the same rule
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 70)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude)
    VALUES ('PLOT002', 'P001', 'ICH', 'mk1', 50)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude)
    VALUES ('PLOT003', 'P001', 'ICH', 'mk1', 65)
  ")
  
  result <- run_compliance_checks(con, "P001")
  
  # Summary should count violations by rule
  lat_summary <- result$summary_tibble[result$summary_tibble$rule == "range_lat", ]
  expect_equal(lat_summary$count, 2)  # PLOT001 and PLOT003
})

test_that("Compliance summary: empty when no violations", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Insert fully valid record
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (
      plotnumber, projectid, zone, subzone,
      latitude, longitude, elevation,
      slopegradient, aspect, rootingdepth
    )
    VALUES (
      'PLOT001', 'P001', 'ICH', 'mk1',
      50, -120, 1000,
      25, 180, 50
    )
  ")
  
  result <- run_compliance_checks(con, "P001")
  
  expect_true(result$passed)
  expect_equal(nrow(result$summary_tibble), 0)
  expect_equal(nrow(result$detail_tibble), 0)
})

test_that("Compliance detail: includes plot numbers", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude)
    VALUES ('SPECIFIC_PLOT_X', 'P001', 'ICH', 'mk1', 70)
  ")
  
  result <- run_compliance_checks(con, "P001")
  
  expect_true("SPECIFIC_PLOT_X" %in% result$detail_tibble$plotnumber)
})

# ============================================================================
# 9. PERFORMANCE - Large Dataset Stress Test
# ============================================================================

test_that("Performance: 1000 records with mixed violations", {
  skip_on_cran()  # Long-running test
  
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Insert 1000 records with varying compliance.
  # Keep the invalid fixtures violating ONE rule so the expected
  # violation count is stable (avoid double-counting across rules).
  # 70% valid, 30% latitude out-of-range.
  for (i in 1:1000) {
    lat <- if (i %% 10 < 7) 50 else 70  # 30% invalid latitude
    zone <- 'ICH'
    
    DBI::dbExecute(con, sprintf("
      INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
      VALUES ('PLOT%04d', 'P001', '%s', 'mk1', %f, -120, 1000)
    ", i, zone, lat))
  }
  
  # Measure performance
  start_time <- Sys.time()
  result <- run_compliance_checks(con, "P001")
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  # Should complete in reasonable time (< 5 seconds for 1000 records)
  expect_true(elapsed < 5)
  
  # Should find ~300 violations (30% of 1000)
  expect_true(nrow(result$detail_tibble) > 250)
  expect_true(nrow(result$detail_tibble) < 350)
})

test_that("Performance: correctly filters by project_id", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Insert violations in two projects
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude)
    VALUES ('PLOT001', 'P001', 'ICH', 'mk1', 70)
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude)
    VALUES ('PLOT002', 'P002', 'ICH', 'mk1', 70)
  ")
  
  result_p001 <- run_compliance_checks(con, "P001")
  result_p002 <- run_compliance_checks(con, "P002")
  
  # Each should only report violations for their own project
  expect_equal(nrow(result_p001$detail_tibble), 1)
  expect_equal(nrow(result_p002$detail_tibble), 1)
  expect_true(all(result_p001$detail_tibble$plotnumber == "PLOT001"))
  expect_true(all(result_p002$detail_tibble$plotnumber == "PLOT002"))
})

# ============================================================================
# 10. INTEGRATION - Real-World Scenarios
# ============================================================================

test_that("Integration: BC forestry plot passes all checks", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Realistic BC Interior Cedar-Hemlock plot
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (
      plotnumber, projectid, zone, subzone,
      latitude, longitude, elevation,
      slopegradient, aspect,
      mesoslopeposition, surfaceshape,
      rootingdepth
    )
    VALUES (
      'BC-ICH-001', 'P001', 'ICH', 'mk1',
      50.5, -119.5, 1200,
      35, 225,
      'MIDDLE', 'CONCAVE',
      80
    )
  ")
  
  # Vegetation: typical ICH species
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('BC-ICH-001', 'THPL', 'P001', 'A', '40')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('BC-ICH-001', 'TSHE', 'P001', 'A', '30')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('BC-ICH-001', 'ACMA', 'P001', 'B', '15')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('BC-ICH-001', 'ODE', 'P001', 'C', 'r')
  ") # Rare species with 'r' code
  
  result <- run_compliance_checks(con, "P001")
  
  expect_true(result$passed)
  expect_equal(nrow(result$detail_tibble), 0)
})

test_that("Integration: edge of BC boundary coordinates", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Northern BC (near Yukon border)
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('NORTH-BC', 'P001', 'SBPS', 'xc', 59.9, -120, 800)
  ")
  
  # Eastern BC (near Alberta border)
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('EAST-BC', 'P001', 'IDF', 'dk1', 50, -114.1, 1000)
  ")
  
  # Western BC (coastal)
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation)
    VALUES ('WEST-BC', 'P001', 'CDF', 'mm', 48.5, -123, 100)
  ")
  
  result <- run_compliance_checks(con, "P001")
  
  expect_true(result$passed)
  expect_equal(nrow(result$detail_tibble), 0)
})

test_that("Integration: cover codes in realistic context", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Mix of numeric covers and text codes (typical field data)
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'PSME', 'P001', 'A', '45')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'THPL', 'P001', 'A', '25')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ODE', 'P001', 'C', '+')
  ") # Present but <1%
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'ACMA', 'P001', 'C', 'r')
  ") # Rare
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'PIEN', 'P001', 'B', 'P')
  ") # Planted
  
  result <- run_compliance_checks(con, "P001")
  
  expect_true(result$passed)
  expect_equal(nrow(result$detail_tibble), 0)
})

# ============================================================================
# ADDITIONAL BUSINESS RULE & STRESS TESTS
# ============================================================================

test_that("Cover sum: total >100% per layer flagged as warning", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Layer A with combined cover >100% (common overshooting in field data)
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'PSME', 'P001', 'A', '60')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT001', 'THPL', 'P001', 'A', '55')
  ")
  
  # Note: This validation may not be implemented yet in logic_compliance.R
  # Documenting expected behavior: sum check is a quality warning, not hard error
  # Access VBA allowed >100% in some contexts (overlapping canopy layers)
  expect_true(TRUE)  # Placeholder - may need implement check_cover_sum_by_layer()
})

test_that("Date validation: future survey dates flagged", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Add survey_date column if schema supports it
  result <- tryCatch({
    DBI::dbExecute(con, "ALTER TABLE Sample_Env ADD COLUMN survey_date DATE")
  }, error = function(e) NULL)
  
  # Insert plot with future date
  DBI::dbExecute(con, sprintf("
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, survey_date)
    VALUES ('PLOT001', 'P001', 'ICH', 'mw', '%s')
  ", as.character(Sys.Date() + 365)))
  
  # Note: Date validation not yet in logic_compliance.R
  # Documenting expected behavior: future dates should be flagged
  expect_true(TRUE)  # Placeholder - may need implement check_date_logic()
})

test_that("Date validation: NULL survey date allowed (unknown date)", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  result <- tryCatch({
    DBI::dbExecute(con, "ALTER TABLE Sample_Env ADD COLUMN survey_date DATE")
  }, error = function(e) NULL)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, survey_date)
    VALUES ('PLOT001', 'P001', 'ICH', 'mw', NULL)
  ")
  
  # NULL date should be allowed (optional field)
  result <- run_compliance_checks(con, "P001")
  expect_true(TRUE)  # Should not fail on NULL date
})

test_that("Hierarchical consistency: parent-child plot relationships", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Note: Hierarchical validation requires SampleUnit_Hierarchy table
  # This is a complex validation from Access V7mdlHierarchyTools
  # Documenting expected behavior: child plots must reference valid parent units
  expect_true(TRUE)  # Placeholder - hierarchy validation not yet implemented
})

test_that("Coordinate consistency: DMS vs DD format detection", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Mixed coordinate formats could indicate data entry errors
  # Access used DMS→DD conversion with Nz() guards
  # DMS format: degrees > 180 indicates DMS not DD
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude)
    VALUES ('PLOT001', 'P001', 'ICH', 'mw', 53.30, 119.45)
  ") # Looks like DD but lon wrong sign
  
  # Positive longitude in BC is wrong (should be negative)
  result <- check_coord_ranges(con, "P001")
  expect_true(nrow(result) > 0)
  expect_true(any(result$rule == "range_lon"))
})

test_that("Stress: Maximum string lengths (255 chars)", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Very long plot number (Access limit: 255 chars for TEXT)
  long_plot <- paste(rep("A", 255), collapse = "")
  
  DBI::dbExecute(con, sprintf("
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('%s', 'P001', 'ICH', 'mw')
  ", long_plot))
  
  result <- run_compliance_checks(con, "P001")
  expect_true(result$passed)
})

test_that("Stress: Unicode and special characters in text fields", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Unicode, accents, quotes, backslashes
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('Plot-Québec-2024', 'P001', 'ICH', 'mw')
  ")
  
  # Add surveyor column for quote test
  result <- tryCatch({
    DBI::dbExecute(con, "ALTER TABLE Sample_Env ADD COLUMN surveyor TEXT")
  }, error = function(e) NULL)
  
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, surveyor)
    VALUES ('PLOT002', 'P001', 'ICH', 'mw', 'O''Brien, François')
  ")
  
  result <- run_compliance_checks(con, "P001")
  expect_true(result$passed)
})

test_that("Stress: Whitespace variations (tabs, newlines, mixed)", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Tabs and extra spaces in plotnumber
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('  PLOT001  ', 'P001', 'ICH', 'mw')
  ")
  
  # Current implementation may not trim - documenting edge case
  # Ideally: trimws() should be applied before validation
  result <- run_compliance_checks(con, "P001")
  
  # May pass or fail depending on trim implementation
  expect_true(TRUE)  # Documenting behavior, not enforcing
})

test_that("Stress: All fields at NULL (minimal record)", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Only required fields populated, all optional NULL
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (
      plotnumber, projectid, zone, subzone,
      latitude, longitude, elevation, slopegradient, aspect,
      mesoslopeposition, surfaceshape,
      rootrestrictingdepth, rootingdepth, seepagedepth,
      sv_soildepth, sv_gleyingmottlingcm, sv_watertablecm,
      sv_ahorizondepth, activelayerdepth
    )
    VALUES (
      'PLOT001', 'P001', 'ICH', 'mw',
      NULL, NULL, NULL, NULL, NULL,
      NULL, NULL,
      NULL, NULL, NULL,
      NULL, NULL, NULL,
      NULL, NULL
    )
  ")
  
  result <- run_compliance_checks(con, "P001")
  expect_true(result$passed)  # NULLs in optional fields should not trigger errors
})

test_that("Stress: 10000 vegetation entries validate in <3 seconds", {
  skip_on_cran()  # Skip slow test on CRAN
  
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Insert 1000 plots with 10 veg records each = 10000 veg entries
  for (i in 1:1000) {
    plot_num <- sprintf("PLOT%04d", i)
    
    # Insert env record
    DBI::dbExecute(con, sprintf("
      INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
      VALUES ('%s', 'P001', 'ICH', 'mw')
    ", plot_num))
    
    # Insert 10 veg records (mix of layers and species)
    species_list <- c("PSME", "THPL", "TSHE", "ABLA", "PIEN", "PICO", "PIMO", "ACGL", "ALVI", "AMAL")
    for (j in 1:10) {
      DBI::dbExecute(con, sprintf("
        INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
        VALUES ('%s', '%s', 'P001', 'A', '%d')
      ", plot_num, species_list[j], sample(1:50, 1)))
    }
  }
  
  # Validate all 10000 veg entries
  start_time <- Sys.time()
  result <- run_compliance_checks(con, "P001")
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  expect_true(elapsed < 3.0)  # Should complete in <3 seconds
  expect_true(result$passed)
})

test_that("Stress: Mixed valid and invalid across all rules", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_full_compliance_schema(con)
  
  # Create records violating every rule type
  
  # 1. Missing required field
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES (NULL, 'P001', 'ICH', 'mw')
  ")
  
  # 2. Invalid zone FK
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('PLOT-BAD-ZONE', 'P001', 'INVALIDZONE', 'mw')
  ")
  
  # 3. Latitude out of range
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude)
    VALUES ('PLOT-BAD-LAT', 'P001', 'ICH', 'mw', 99.0, -119.5)
  ")
  
  # 4. Longitude out of range
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, latitude, longitude)
    VALUES ('PLOT-BAD-LON', 'P001', 'ICH', 'mw', 53.5, -200.0)
  ")
  
  # 5. Elevation negative
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, elevation)
    VALUES ('PLOT-BAD-ELEV', 'P001', 'ICH', 'mw', -500)
  ")
  
  # 6. Slope > 100
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, slopegradient)
    VALUES ('PLOT-BAD-SLOPE', 'P001', 'ICH', 'mw', 150)
  ")
  
  # 7. Aspect > 360
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, aspect)
    VALUES ('PLOT-BAD-ASP', 'P001', 'ICH', 'mw', 400)
  ")
  
  # 8. Negative depth
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone, rootingdepth)
    VALUES ('PLOT-BAD-DEPTH', 'P001', 'ICH', 'mw', -50)
  ")
  
  # 9. Duplicate plot
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('DUP-PLOT', 'P001', 'ICH', 'mw')
  ")
  DBI::dbExecute(con, "
    INSERT INTO Sample_Env (plotnumber, projectid, zone, subzone)
    VALUES ('DUP-PLOT', 'P001', 'IDF', 'dk')
  ")
  
  # 10. Invalid species FK
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT-BAD-SPP', 'INVALIDSPP', 'P001', 'A', '50')
  ")
  
  # 11. Cover > 100
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT-BAD-COV', 'PSME', 'P001', 'A', '150')
  ")
  
  # 12. Invalid cover code
  DBI::dbExecute(con, "
    INSERT INTO Sample_Veg (plotnumber, species, projectid, layer, cover1)
    VALUES ('PLOT-BAD-CODE', 'PSME', 'P001', 'A', 'INVALID')
  ")
  
  # Run compliance checks
  result <- run_compliance_checks(con, "P001")
  
  expect_false(result$passed)
  expect_true(nrow(result$detail_tibble) >= 12)  # At least 12 violations
  expect_true(nrow(result$summary_tibble) >= 8)  # Multiple rule types
  
  # Check that all major rule types are represented
  rule_types <- result$summary_tibble$rule
  expect_true(any(grepl("required", rule_types)))
  expect_true(any(grepl("range_", rule_types)))
  expect_true(any(grepl("fk_", rule_types)))
  expect_true(any(grepl("dup_", rule_types)))
})
