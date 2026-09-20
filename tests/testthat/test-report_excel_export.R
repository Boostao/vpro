library(testthat)

source(here::here("R", "logic_reports_veg.R"))
source(here::here("R", "logic_report_export.R"))

test_that("Excel export writes workbook for short veg report", {
  skip_if_not_installed("writexl")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE vw_USysAllVeg (
      PlotNumber TEXT,
      MyLayer TEXT,
      Species TEXT,
      Cover TEXT
    )
  ")

  DBI::dbExecute(
    con,
    "INSERT INTO vw_USysAllVeg (PlotNumber, MyLayer, Species, Cover) VALUES (?, ?, ?, ?)",
    list("P1", "A", "AB", "10")
  )
  DBI::dbExecute(
    con,
    "INSERT INTO vw_USysAllVeg (PlotNumber, MyLayer, Species, Cover) VALUES (?, ?, ?, ?)",
    list("P1", "A", "FD", "20")
  )

  params <- list(
    plot_number = "P1",
    plot_numbers = "",
    site_unit = "",
    project_id = "",
    group_by = "layer",
    order_by = "species",
    presence_min = 0,
    cover_min = 0,
    value_limit = 0,
    avg_type = "mean",
    show_common = "none",
    apply_lumping = FALSE,
    constancy_format = FALSE,
    display_value = "standard"
  )

  data_list <- build_excel_report_data(con, "short_veg.qmd", params)
  expect_true(is.list(data_list))
  expect_true("Vegetation" %in% names(data_list))
  expect_gt(nrow(data_list$Vegetation), 0)

  tmp_file <- tempfile(fileext = ".xlsx")
  on.exit(unlink(tmp_file), add = TRUE)

  writexl::write_xlsx(data_list, path = tmp_file)
  expect_true(file.exists(tmp_file))
  expect_gt(file.info(tmp_file)$size, 0)

  entries <- utils::unzip(tmp_file, list = TRUE)
  expect_true(any(grepl("^xl/worksheets/sheet1\\.xml$", entries$Name)))
})

test_that("Excel export splits long environment by site unit", {
  skip_if_not_installed("writexl")

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE Env (
      PlotNumber TEXT,
      SitePlotQuality TEXT,
      Zone TEXT,
      SubZone TEXT,
      Elevation DOUBLE
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE SU (
      PlotNumber TEXT,
      SiteUnit TEXT
    )
  ")

  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, SitePlotQuality, Zone, SubZone, Elevation) VALUES (?, ?, ?, ?, ?)",
    list("P1", "Good", "BWBS", "dk", 100)
  )
  DBI::dbExecute(
    con,
    "INSERT INTO Env (PlotNumber, SitePlotQuality, Zone, SubZone, Elevation) VALUES (?, ?, ?, ?, ?)",
    list("P2", "Good", "BWBS", "dk", 120)
  )
  DBI::dbExecute(
    con,
    "INSERT INTO SU (PlotNumber, SiteUnit) VALUES (?, ?)",
    list("P1", "SU01")
  )
  DBI::dbExecute(
    con,
    "INSERT INTO SU (PlotNumber, SiteUnit) VALUES (?, ?)",
    list("P2", "SU02")
  )

  params <- list(
    plot_number = "",
    plot_numbers = "P1,P2",
    site_unit = "",
    project_id = ""
  )

  data_list <- build_excel_report_data(con, "long_env.qmd", params)
  expect_true(is.list(data_list))
  expect_true(all(c("SU01", "SU02") %in% names(data_list)))
  expect_gt(nrow(data_list[["SU01"]]), 0)
})
