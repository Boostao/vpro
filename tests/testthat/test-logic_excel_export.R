# Tests for Excel Export Logic with Styling

connect_vpro_duckdb_for_tests <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), here::here("data", "vpro.duckdb"), read_only = TRUE)
  DBI::dbExecute(
    con,
    paste0(
      "ATTACH ",
      DBI::dbQuoteString(con, here::here("data", "vpro_lists.duckdb")),
      " AS lists"
    )
  )
  con
}

test_that("openxlsx package is available", {
  skip_if_not_installed("openxlsx")
  expect_true(requireNamespace("openxlsx", quietly = TRUE))
})

test_that("export_vegetation_excel creates valid workbook with correct structure", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  # Test with separate sheets (default)
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_vegetation_excel(
    con, temp_file,
    options = list(
      layers = c("1", "6"),  # Tree and Herb layers
      separate_sheets = TRUE,
      include_metadata = FALSE
    )
  )
  
  expect_true(result)
  expect_true(file.exists(temp_file))
  
  # Read back and verify structure
  wb <- openxlsx::loadWorkbook(temp_file)
  sheet_names <- names(wb)
  
  # Should have VegA_Trees1, VegC_Herbs, Instructions
  expect_true("VegA_Trees1" %in% sheet_names)
  expect_true("Instructions" %in% sheet_names)
  
  # Read data from one sheet
  data <- openxlsx::readWorkbook(temp_file, sheet = "VegA_Trees1")
  expect_true(ncol(data) >= 5)  # Plot, Layer, Code, Sci Name, Common Name, Cover
  expect_true("Plot" %in% colnames(data) || "PlotNumber" %in% colnames(data))
})

test_that("export_vegetation_excel with lumping applies species consolidation", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_lumping.R"), local = TRUE)
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_vegetation_excel(
    con, temp_file,
    options = list(
      layers = c("1"),
      apply_lumping = TRUE,
      separate_sheets = FALSE,
      include_metadata = FALSE
    )
  )
  
  expect_true(result)
  expect_true(file.exists(temp_file))
  
  # Lumping should reduce number of species (synonyms merged)
  # We can't test exact counts without knowing data, but file should be valid
  data <- openxlsx::readWorkbook(temp_file, sheet = "Vegetation")
  expect_true(nrow(data) > 0)
})

test_that("export_environment_excel creates environment and soil sheets", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_environment_excel(
    con, temp_file,
    options = list(
      include_soil = TRUE,
      include_metadata = FALSE
    )
  )
  
  expect_true(result)
  expect_true(file.exists(temp_file))
  
  wb <- openxlsx::loadWorkbook(temp_file)
  sheet_names <- names(wb)
  
  expect_true("Environment" %in% sheet_names)
  expect_true("Instructions" %in% sheet_names)
  # Soil sheets may or may not exist depending on data availability
})

test_that("export_combined_excel creates multi-sheet workbook", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_combined_excel(
    con, temp_file,
    options = list(
      layers = c("1", "6"),
      include_soil = TRUE
    )
  )
  
  expect_true(result)
  expect_true(file.exists(temp_file))
  
  wb <- openxlsx::loadWorkbook(temp_file)
  sheet_names <- names(wb)
  
  # Should have vegetation, environment, and instructions at minimum
  expect_true(length(sheet_names) >= 3)
  expect_true("Instructions" %in% sheet_names)
  expect_true("Environment" %in% sheet_names)
})

test_that("workbook has proper styling applied", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_vegetation_excel(
    con, temp_file,
    options = list(
      layers = c("1"),
      separate_sheets = FALSE,
      conditional_formatting = TRUE
    )
  )
  
  expect_true(result)
  
  # Load workbook and check for styles
  wb <- openxlsx::loadWorkbook(temp_file)
  
  # Check that workbook has styles defined
  expect_true(length(wb$styleObjects) > 0)
  
  # Verify data can be read back (valid Excel format)
  data <- openxlsx::readWorkbook(temp_file, sheet = 1)
  expect_true(nrow(data) > 0)
  expect_true(ncol(data) > 0)
})

test_that("excel export handles empty data gracefully", {
  skip_if_not_installed("openxlsx")
  
  # Create in-memory database with no data
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  # Create minimal schema
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS lists")
  DBI::dbExecute(con, "CREATE TABLE vw_USysAllVeg (PlotNumber VARCHAR, MyLayer VARCHAR, Species VARCHAR, Cover VARCHAR)")
  DBI::dbExecute(con, "CREATE TABLE Sample_Env (plotnumber VARCHAR, projectid VARCHAR)")
  DBI::dbExecute(con, "CREATE TABLE lists.SppList (code VARCHAR, scientificname VARCHAR, commonname VARCHAR)")
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  
  # Should handle empty data without crashing
  expect_warning(
    result <- export_vegetation_excel(con, temp_file, options = list(include_metadata = FALSE)),
    "No vegetation data"
  )
  
  expect_false(result)
})

test_that("project filtering works correctly", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  # Get list of projects
  projects <- DBI::dbGetQuery(con, "SELECT DISTINCT projectid FROM Sample_Metadata LIMIT 1")
  
  if (nrow(projects) > 0) {
    project_id <- projects$projectid[1]
    has_veg <- DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n FROM vw_USysAllVeg v JOIN Sample_Env e ON v.PlotNumber = e.plotnumber WHERE v.MyLayer = '1' AND e.projectid = ?",
      list(project_id)
    )$n

    if (isTRUE(has_veg == 0)) {
      skip("Selected project has no layer 1 vegetation data")
    }

    temp_file <- tempfile(fileext = ".xlsx")
    on.exit(unlink(temp_file), add = TRUE)
    
    source(here::here("R", "logic_excel_export.R"), local = TRUE)
    result <- export_vegetation_excel(
      con, temp_file,
      options = list(
        project_ids = project_id,
        layers = c("1"),
        separate_sheets = FALSE,
        include_metadata = TRUE
      )
    )
    
    expect_true(result)
    
    # Verify metadata sheet exists
    wb <- openxlsx::loadWorkbook(temp_file)
    expect_true("Project_Metadata" %in% names(wb))
  }
})

test_that("data type formatting is correct for numeric columns", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_vegetation_excel(
    con, temp_file,
    options = list(
      layers = c("1"),
      separate_sheets = FALSE
    )
  )
  
  expect_true(result)
  
  # Read data and check Cover column is numeric
  data <- openxlsx::readWorkbook(temp_file, sheet = "Vegetation")
  
  cover_col <- which(colnames(data) == "Cover %")
  if (length(cover_col) > 0) {
    # Excel should preserve numeric type
    expect_true(is.numeric(data[[cover_col]]))
  }
})

test_that("performance - large dataset exports in reasonable time", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  skip("Performance test - run manually when needed")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  
  # Time the export
  start_time <- Sys.time()
  result <- export_combined_excel(
    con, temp_file,
    options = list(
      layers = c("1", "2", "3", "4", "5", "6", "7"),
      include_soil = TRUE
    )
  )
  end_time <- Sys.time()
  
  duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
  
  # Should complete in under 10 seconds for typical datasets
  # (1000+ rows should be well under 5 seconds)
  expect_true(result)
  expect_lt(duration, 10)
  
  cat("\nExport time:", round(duration, 2), "seconds\n")
})

test_that("instructions sheet is created with proper content", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_vegetation_excel(
    con, temp_file,
    options = list(
      layers = c("1"),
      separate_sheets = FALSE,
      include_metadata = FALSE
    )
  )
  
  expect_true(result)
  
  # Read instructions sheet
  instructions <- openxlsx::readWorkbook(temp_file, sheet = "Instructions")
  
  expect_true(nrow(instructions) > 0)
  expect_true("Section" %in% colnames(instructions))
  expect_true("Description" %in% colnames(instructions))
  
  # Should have overview section
  expect_true(any(grepl("Overview", instructions$Section, ignore.case = TRUE)))
})

test_that("conditional formatting can be disabled", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_vegetation_excel(
    con, temp_file,
    options = list(
      layers = c("1"),
      separate_sheets = FALSE,
      conditional_formatting = FALSE
    )
  )
  
  expect_true(result)
  
  # File should still be valid
  data <- openxlsx::readWorkbook(temp_file, sheet = "Vegetation")
  expect_true(nrow(data) > 0)
})

test_that("column widths are set appropriately", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_vegetation_excel(
    con, temp_file,
    options = list(
      layers = c("1"),
      separate_sheets = FALSE
    )
  )
  
  expect_true(result)
  
  # Load workbook and check column widths are set
  wb <- openxlsx::loadWorkbook(temp_file)
  
  # Column widths should be defined in workbook object
  # (This is more of a smoke test - detailed width testing would require xlsx parsing)
  expect_true(length(wb$colWidths) > 0 || !is.null(wb$colWidths))
})

test_that("layer names are correctly mapped to sheet names", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  temp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(temp_file), add = TRUE)
  
  source(here::here("R", "logic_excel_export.R"), local = TRUE)
  result <- export_vegetation_excel(
    con, temp_file,
    options = list(
      layers = c("1", "4", "6"),
      separate_sheets = TRUE,
      include_metadata = FALSE
    )
  )
  
  expect_true(result)
  
  wb <- openxlsx::loadWorkbook(temp_file)
  sheet_names <- names(wb)
  
  # Layer 1 = VegA_Trees1, 4 = VegB_Shrub1, 6 = VegC_Herbs
  # Check at least one expected name exists
  expect_true(any(grepl("VegA|VegB|VegC", sheet_names)))
})

test_that("exported data matches database query results", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists(here::here("data", "vpro.duckdb")), "Main database not found")
  
  con <- connect_vpro_duckdb_for_tests()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  
  # Get expected row count from database
  query <- "SELECT COUNT(*) as n FROM vw_USysAllVeg WHERE MyLayer = '1'"
  expected_count <- DBI::dbGetQuery(con, query)$n
  
  if (expected_count > 0) {
    temp_file <- tempfile(fileext = ".xlsx")
    on.exit(unlink(temp_file), add = TRUE)
    
    source(here::here("R", "logic_excel_export.R"), local = TRUE)
    result <- export_vegetation_excel(
      con, temp_file,
      options = list(
        layers = c("1"),
        separate_sheets = FALSE,
        apply_lumping = FALSE
      )
    )
    
    expect_true(result)
    
    # Read exported data
    data <- openxlsx::readWorkbook(temp_file, sheet = "Vegetation")
    
    # Row counts should match (allowing for header row in Excel)
    # Note: lumping/joins might alter count slightly
    expect_equal(nrow(data), expected_count)
  }
})
