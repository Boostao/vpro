# Tests for Vegetation Sample module

source(here::here("R", "logic_state.R"))
source(here::here("R", "mod_veg_sample.R"))

setup_veg_sample_tables <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE Veg (
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
    "INSERT INTO Veg (id, plotnumber, species, cover1, height1) VALUES (?, ?, ?, ?, ?)",
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
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setup_veg_sample_tables(con)

  save_veg_cell(con, 1, "cover1", "+")

  saved <- DBI::dbGetQuery(con, "SELECT cover1 FROM Veg WHERE id = 1")
  expect_equal(saved$cover1[1], "+")
})

test_that("sum_numeric_or_na handles mixed cover inputs", {
  expect_true(is.na(sum_numeric_or_na(c(NA, NA))))
  expect_equal(sum_numeric_or_na(c("10", "", NA)), 10)
  expect_equal(sum_numeric_or_na(data.frame(a = c("5", "5"))), 10)
})

test_that("detect_hot_changes returns changed cells", {
  old_df <- data.frame(species = c("AB", "FD"), cover1 = c("10", "20"))
  new_df <- data.frame(species = c("AB", "FD"), cover1 = c("10", "25"))

  changes <- detect_hot_changes(old_df, new_df)
  expect_equal(length(changes), 1)
  expect_equal(changes[[1]]$row, 2)
  expect_equal(changes[[1]]$col, "cover1")
  expect_equal(changes[[1]]$value, "25")
})
