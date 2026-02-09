# Tests for soil grid persistence helpers

source(here::here("R", "mod_site_env.R"))

setup_soil_tables <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE Sample_Humus (
      id INTEGER,
      plotnumber TEXT,
      horizon TEXT,
      upperdepth DOUBLE,
      lowerdepth DOUBLE,
      humusstructuredegree TEXT,
      humusstructurekind TEXT,
      humusformph DOUBLE,
      _comment TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE Sample_Mineral (
      id INTEGER,
      plotnumber TEXT,
      horizon TEXT,
      upperdepth DOUBLE,
      lowerdepth DOUBLE,
      texture TEXT,
      percentcoarsefragstotal DOUBLE,
      mineralstructureclass TEXT,
      colour TEXT,
      _comments TEXT
    )
  ")

  DBI::dbExecute(
    con,
    "INSERT INTO Sample_Humus (id, plotnumber, horizon, upperdepth, lowerdepth, humusformph) VALUES (?, ?, ?, ?, ?, ?)",
    list(1, "P1", "H", 5.0, 10.0, 4.5)
  )
  DBI::dbExecute(
    con,
    "INSERT INTO Sample_Mineral (id, plotnumber, horizon, upperdepth, lowerdepth, percentcoarsefragstotal) VALUES (?, ?, ?, ?, ?, ?)",
    list(2, "P1", "A", 0.0, 15.0, 20.0)
  )
}

test_that("save_soil_cell updates numeric and text values", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_soil_tables(con)

  save_soil_cell(con, "Sample_Humus", 1, "upperdepth", coerce_soil_value("Sample_Humus", "upperdepth", "12.5"))
  save_soil_cell(con, "Sample_Humus", 1, "_comment", coerce_soil_value("Sample_Humus", "_comment", "note"))

  saved <- DBI::dbGetQuery(con, "SELECT upperdepth, _comment FROM Sample_Humus WHERE id = 1")
  expect_equal(saved$upperdepth[1], 12.5)
  expect_equal(saved$`_comment`[1], "note")
})

test_that("coerce_soil_value casts numeric columns", {
  expect_equal(coerce_soil_value("Sample_Mineral", "percentcoarsefragstotal", "33"), 33)
  expect_true(is.na(coerce_soil_value("Sample_Mineral", "percentcoarsefragstotal", "")))
})
