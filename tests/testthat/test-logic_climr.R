# Tests for ClimR integration (R/logic_climr.R)

# Ensure CLIMR logic is available when running tests from repo
source(here::here("R", "logic_climr.R"), local = TRUE)

test_that("climr availability check works", {
  # This function should return TRUE or FALSE, never error
  result <- check_climr_availability(silent = TRUE)
  expect_type(result, "logical")
  expect_length(result, 1)
  expect_false(is.na(result))
  
  # Second call should use cached result
  result2 <- check_climr_availability(silent = TRUE)
  expect_identical(result, result2)
})

test_that("coordinate cache key generation works", {
  # Internal function test
  key1 <- get_coord_cache_key(50.6745, -120.3273)
  expect_type(key1, "character")
  expect_match(key1, "^[0-9.]+_-[0-9.]+$")
  
  # Should round to 4 decimal places
  key2 <- get_coord_cache_key(50.67449999, -120.32729999)
  expect_identical(key1, key2)
  
  # Different coordinates = different keys
  key3 <- get_coord_cache_key(49.2827, -123.1207)
  expect_false(key1 == key3)
})

test_that("climate data fetch handles invalid inputs", {
  # NA coordinates
  result <- get_climate_data(NA, -120.3273, silent = TRUE)
  expect_null(result)
  
  result <- get_climate_data(50.6745, NA, silent = TRUE)
  expect_null(result)
  
  # Non-numeric coordinates
  result <- get_climate_data("fifty", -120.3273, silent = TRUE)
  expect_null(result)
  
  # Out of BC bounds
  result <- get_climate_data(30.0, -120.0, silent = TRUE)  # Too far south
  expect_null(result)
  
  result <- get_climate_data(50.0, -80.0, silent = TRUE)   # Too far east
  expect_null(result)
})

test_that("climate data fetch returns proper structure (if climr available)", {
  skip_if_not(check_climr_availability(silent = TRUE), "ClimR not available")
  
  # Known BC location: Kamloops
  climate <- get_climate_data(50.6745, -120.3273, silent = TRUE)
  
  # May be NULL if climr not fully configured (stub implementation)
  skip_if(is.null(climate), "ClimR returned NULL (possibly stub implementation)")
  
  # Check structure
  expect_type(climate, "list")
  
  # Check required fields
  expected_fields <- c(
    "MAT", "MAP", "MWMT", "MCMT", "TD", "AHM", "SHM",
    "DD_0", "DD_5", "DD_18", "NFFD", "PAS", "MSP",
    "Eref", "CMD", "elevation", "period", "fetch_time"
  )
  
  expect_true(all(expected_fields %in% names(climate)))
  
  # Numeric fields
  numeric_fields <- setdiff(expected_fields, c("period", "fetch_time"))
  for (field in numeric_fields) {
    expect_type(climate[[field]], "double")
  }
  
  # Period should be character
  expect_type(climate$period, "character")
  
  # Fetch time should be POSIXct
  expect_s3_class(climate$fetch_time, "POSIXct")
})

test_that("climate data caching works", {
  skip_if_not(check_climr_availability(silent = TRUE), "ClimR not available")
  
  # Clear cache first
  clear_climr_cache(silent = TRUE)
  
  # First fetch
  climate1 <- get_climate_data(50.6745, -120.3273, use_cache = TRUE, silent = TRUE)
  
  # Second fetch should be cached (same timestamp)
  climate2 <- get_climate_data(50.6745, -120.3273, use_cache = TRUE, silent = TRUE)
  
  if (!is.null(climate1) && !is.null(climate2)) {
    expect_identical(climate1$fetch_time, climate2$fetch_time)
  }
  
  # With use_cache = FALSE, should get new fetch (different timestamp)
  Sys.sleep(0.1)  # Ensure time difference
  climate3 <- get_climate_data(50.6745, -120.3273, use_cache = FALSE, silent = TRUE)
  
  if (!is.null(climate1) && !is.null(climate3)) {
    # May have different timestamp if re-fetched
    # But structure should be identical
    expect_equal(names(climate1), names(climate3))
  }
})

test_that("cache clearing works", {
  skip_if_not(check_climr_availability(silent = TRUE), "ClimR not available")
  
  # Populate cache
  get_climate_data(50.6745, -120.3273, use_cache = TRUE, silent = TRUE)
  get_climate_data(49.2827, -123.1207, use_cache = TRUE, silent = TRUE)
  
  # Clear cache
  clear_climr_cache(silent = TRUE)
  
  # Cache should be empty (internal check)
  cache_env <- .climr_cache
  expect_equal(length(names(cache_env)), 0)
})

test_that("BEC prediction handles invalid inputs", {
  # NA coordinates
  result <- predict_bec_classification(NA, -120.3273, silent = TRUE)
  expect_null(result)
  
  result <- predict_bec_classification(50.6745, NA, silent = TRUE)
  expect_null(result)
})

test_that("BEC prediction returns proper structure (if climr available)", {
  skip_if_not(check_climr_availability(silent = TRUE), "ClimR not available")
  
  # Known BC location
  bec <- predict_bec_classification(50.6745, -120.3273, silent = TRUE)
  
  # May be NULL if climr BEC not implemented (stub)
  skip_if(is.null(bec), "BEC prediction returned NULL (possibly stub)")
  
  # Check structure
  expect_type(bec, "list")
  
  expected_fields <- c("zone", "subzone", "variant", "bgc_unit", "confidence")
  expect_true(all(expected_fields %in% names(bec)))
  
  # Character fields
  expect_type(bec$zone, "character")
  expect_type(bec$subzone, "character")
  expect_type(bec$variant, "character")
  expect_type(bec$bgc_unit, "character")
  
  # Confidence should be numeric
  expect_type(bec$confidence, "double")
})

test_that("elevation fetch handles invalid inputs", {
  # NA coordinates
  result <- get_elevation(NA, -120.3273, silent = TRUE)
  expect_true(is.na(result))
  
  result <- get_elevation(50.6745, NA, silent = TRUE)
  expect_true(is.na(result))
})

test_that("elevation fetch returns numeric (if climr available)", {
  skip_if_not(check_climr_availability(silent = TRUE), "ClimR not available")
  
  elev <- get_elevation(50.6745, -120.3273, silent = TRUE)
  
  # Should be numeric (may be NA if not implemented)
  expect_type(elev, "double")
  
  # If not NA, should be sensible range for Kamloops (~300-400m)
  if (!is.na(elev)) {
    expect_true(elev > 200 && elev < 600)
  }
})

test_that("batch climate fetch handles invalid inputs", {
  # Not a data frame
  result <- get_climate_batch(list(a = 1), silent = TRUE)
  expect_null(result)
  
  # Missing required columns
  df_bad <- data.frame(plotnumber = "P001", lat = 50.6745)
  result <- get_climate_batch(df_bad, silent = TRUE)
  expect_null(result)
  
  # Empty data frame
  df_empty <- data.frame(
    plotnumber = character(0),
    latitude = numeric(0),
    longitude = numeric(0)
  )
  result <- get_climate_batch(df_empty, silent = TRUE)
  expect_null(result)
})

test_that("batch climate fetch filters invalid coordinates", {
  skip_if_not(check_climr_availability(silent = TRUE), "ClimR not available")
  
  df <- data.frame(
    plotnumber = c("P001", "P002", "P003", "P004"),
    latitude = c(50.6745, NA, 30.0, 49.2827),        # 2nd is NA, 3rd out of bounds
    longitude = c(-120.3273, -120.0, -120.0, -123.1207)
  )
  
  result <- get_climate_batch(df, silent = TRUE)
  
  # May be NULL if stub implementation
  skip_if(is.null(result), "Batch fetch returned NULL (possibly stub)")
  
  # Should have at most 2 rows (P001 and P004)
  expect_true(nrow(result) <= 2)
  
  # Should have plotnumber column
  expect_true("plotnumber" %in% names(result))
  
  # Should not have P002 or P003
  if (nrow(result) > 0) {
    expect_false("P002" %in% result$plotnumber)
    expect_false("P003" %in% result$plotnumber)
  }
})

test_that("batch climate fetch returns proper structure (if climr available)", {
  skip_if_not(check_climr_availability(silent = TRUE), "ClimR not available")
  
  df <- data.frame(
    plotnumber = c("P001", "P002"),
    latitude = c(50.6745, 49.2827),
    longitude = c(-120.3273, -123.1207)
  )
  
  result <- get_climate_batch(df, silent = TRUE)
  
  skip_if(is.null(result), "Batch fetch returned NULL (possibly stub)")
  
  # Should be a data frame
  expect_s3_class(result, "data.frame")
  
  # Should have plotnumber + climate columns
  expect_true("plotnumber" %in% names(result))
  expect_true("MAT" %in% names(result))
  expect_true("MAP" %in% names(result))
  
  # Each plot should have one row
  expect_equal(nrow(result), 2)
})

test_that("save climate to db handles missing data", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Create Env table
  DBI::dbExecute(con, "
    CREATE TABLE Env (
      plotnumber TEXT PRIMARY KEY,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation DOUBLE
    )
  ")
  
  DBI::dbExecute(con, "
    INSERT INTO Env (plotnumber, latitude, longitude)
    VALUES ('P001', 50.6745, -120.3273)
  ")
  
  # NULL climate data
  result <- save_climate_to_db(con, "P001", NULL, silent = TRUE)
  expect_false(result)
})

test_that("save climate to db creates columns and saves data", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Create Env table
  DBI::dbExecute(con, "
    CREATE TABLE Env (
      plotnumber TEXT PRIMARY KEY,
      latitude DOUBLE,
      longitude DOUBLE
    )
  ")
  
  DBI::dbExecute(con, "
    INSERT INTO Env (plotnumber, latitude, longitude)
    VALUES ('P001', 50.6745, -120.3273)
  ")
  
  # Mock climate data
  climate_data <- list(
    MAT = 8.3,
    MAP = 280.5,
    MWMT = 17.2,
    MCMT = -1.5,
    TD = 18.7,
    AHM = 25.3,
    SHM = 45.2,
    DD_0 = 1200,
    DD_5 = 1800,
    DD_18 = 250,
    NFFD = 180,
    PAS = 85.2,
    MSP = 120.3,
    Eref = 450.5,
    CMD = 170.2,
    elevation = 345.0,
    period = "Normal_1991_2020",
    fetch_time = Sys.time()
  )
  
  # Save to DB
  result <- save_climate_to_db(con, "P001", climate_data, overwrite = TRUE, silent = TRUE)
  
  # Should succeed
  expect_true(result)
  
  # Verify columns were created
  cols <- tolower(DBI::dbListFields(con, "Env"))
  expect_true("climr_mat" %in% cols)
  expect_true("climr_map" %in% cols)
  expect_true("climr_period" %in% cols)
  
  # Verify data was saved
  saved <- DBI::dbGetQuery(con, "
    SELECT climr_mat, climr_map, climr_elevation, climr_period
    FROM Env
    WHERE plotnumber = 'P001'
  ")
  
  expect_equal(nrow(saved), 1)
  expect_equal(saved$climr_mat[1], 8.3)
  expect_equal(saved$climr_map[1], 280.5)
  expect_equal(saved$climr_elevation[1], 345.0)
  expect_equal(saved$climr_period[1], "Normal_1991_2020")
})

test_that("save climate to db respects overwrite parameter", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Create table with climate columns
  DBI::dbExecute(con, "
    CREATE TABLE Env (
      plotnumber TEXT PRIMARY KEY,
      latitude DOUBLE,
      climr_mat DOUBLE,
      climr_fetch_time TIMESTAMP
    )
  ")
  
  # Insert plot with existing climate data
  DBI::dbExecute(con, "
    INSERT INTO Env (plotnumber, latitude, climr_mat, climr_fetch_time)
    VALUES ('P001', 50.6745, 7.5, '2024-01-01 12:00:00')
  ")
  
  # New climate data
  climate_data <- list(
    MAT = 8.3,
    MAP = 280.5,
    MWMT = 17.2,
    MCMT = -1.5,
    TD = 18.7,
    AHM = 25.3,
    SHM = 45.2,
    DD_0 = 1200,
    DD_5 = 1800,
    DD_18 = 250,
    NFFD = 180,
    PAS = 85.2,
    MSP = 120.3,
    Eref = 450.5,
    CMD = 170.2,
    elevation = 345.0,
    period = "Normal_1991_2020",
    fetch_time = Sys.time()
  )
  
  # Try to save without overwrite (should fail due to existing data)
  result <- save_climate_to_db(con, "P001", climate_data, overwrite = FALSE, silent = TRUE)
  expect_false(result)
  
  # Original value should be unchanged
  mat_old <- DBI::dbGetQuery(con, "SELECT climr_mat FROM Env WHERE plotnumber = 'P001'")$climr_mat[1]
  expect_equal(mat_old, 7.5)
  
  # Save with overwrite = TRUE (should succeed)
  result <- save_climate_to_db(con, "P001", climate_data, overwrite = TRUE, silent = TRUE)
  expect_true(result)
  
  # Value should be updated
  mat_new <- DBI::dbGetQuery(con, "SELECT climr_mat FROM Env WHERE plotnumber = 'P001'")$climr_mat[1]
  expect_equal(mat_new, 8.3)
})

test_that("climate data sensibility checks (if actual data available)", {
  skip_if_not(check_climr_availability(silent = TRUE), "ClimR not available")
  
  # Kamloops, BC - known climate
  climate <- get_climate_data(50.6745, -120.3273, silent = TRUE)
  
  skip_if(is.null(climate), "Climate fetch returned NULL")
  skip_if(is.na(climate$MAT), "Climate data is stub implementation")
  
  # Kamloops is semi-arid interior BC
  # Expected ranges (approximate):
  # MAT: 7-9°C
  # MAP: 250-350mm
  # MWMT: 16-19°C
  # MCMT: -3 to 0°C
  
  expect_true(climate$MAT > 5 && climate$MAT < 12, 
              info = sprintf("MAT out of expected range: %.2f", climate$MAT))
  
  expect_true(climate$MAP > 200 && climate$MAP < 400,
              info = sprintf("MAP out of expected range: %.2f", climate$MAP))
  
  expect_true(climate$MWMT > 14 && climate$MWMT < 22,
              info = sprintf("MWMT out of expected range: %.2f", climate$MWMT))
  
  expect_true(climate$MCMT > -5 && climate$MCMT < 2,
              info = sprintf("MCMT out of expected range: %.2f", climate$MCMT))
})
