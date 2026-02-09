# Tests for Vegetation Sample module

source(here::here("R", "logic_state.R"))
source(here::here("R", "mod_veg_sample.R"))

setup_veg_sample_tables <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE Sample_Veg (
      id INTEGER,
      plotnumber TEXT,
      species TEXT,
      cover1 TEXT,
      height1 DOUBLE,
      totala DOUBLE,
      heighta DOUBLE
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE SppList (
      code TEXT,
      scientificname TEXT
    )
  ")

  DBI::dbExecute(
    con,
    "INSERT INTO Sample_Veg (id, plotnumber, species, cover1, height1) VALUES (?, ?, ?, ?, ?)",
    list(1, "P1", "AB", "10", 5.0)
  )
  DBI::dbExecute(
    con,
    "INSERT INTO SppList (code, scientificname) VALUES (?, ?)",
    list("AB", "Abies lasiocarpa")
  )
}

test_that("mod_veg_sample preserves cover codes as text", {
  testthat::skip_if_not_installed("rhandsontable")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_veg_sample_tables(con)

  save_veg_cell(con, 1, "cover1", "+")

  saved <- DBI::dbGetQuery(con, "SELECT cover1 FROM Sample_Veg WHERE id = 1")
  expect_equal(saved$cover1[1], "+")
})
