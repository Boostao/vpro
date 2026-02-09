# Tests for vegetation data retrieval

library(dplyr)

source(here::here("R", "logic_veg_data.R"))

setup_veg_tables <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE Sample_SU (
      siteunit TEXT,
      plotnumber TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE vw_Sample_Veg_Long (
      plotnumber TEXT,
      species_code TEXT,
      layer TEXT,
      cover_value TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE SppList (
      code TEXT,
      scientificname TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE LayerCode (
      layer1234567 TEXT,
      layertext TEXT
    )
  ")

  DBI::dbExecute(
    con,
    "INSERT INTO Sample_SU (siteunit, plotnumber) VALUES (?, ?)",
    list("SU-1", "P1")
  )
  DBI::dbExecute(
    con,
    "INSERT INTO Sample_SU (siteunit, plotnumber) VALUES (?, ?)",
    list("SU-1", "P2")
  )

  DBI::dbExecute(
    con,
    "INSERT INTO vw_Sample_Veg_Long (plotnumber, species_code, layer, cover_value) VALUES (?, ?, ?, ?)",
    list("P1", "AB", "T", "10")
  )
  DBI::dbExecute(
    con,
    "INSERT INTO vw_Sample_Veg_Long (plotnumber, species_code, layer, cover_value) VALUES (?, ?, ?, ?)",
    list("P2", "ZZ", "S", "+")
  )

  DBI::dbExecute(
    con,
    "INSERT INTO SppList (code, scientificname) VALUES (?, ?)",
    list("AB", "Abies lasiocarpa")
  )

  DBI::dbExecute(
    con,
    "INSERT INTO LayerCode (layer1234567, layertext) VALUES (?, ?)",
    list("T", "Trees")
  )
  DBI::dbExecute(
    con,
    "INSERT INTO LayerCode (layer1234567, layertext) VALUES (?, ?)",
    list("S", "Shrubs")
  )
}

test_that("get_vegetation_data returns empty data frame for blank site unit", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  result <- get_vegetation_data(con, "")
  expect_equal(nrow(result), 0)
})

test_that("get_vegetation_data joins lookup tables and coalesces names", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_veg_tables(con)

  result <- get_vegetation_data(con, "SU-1")

  expect_equal(nrow(result), 2)
  expect_equal(result$scientific_name, c("Abies lasiocarpa", "ZZ"))
  expect_equal(result$layer_desc, c("Trees", "Shrubs"))
  expect_equal(result$cover, c("10", "+"))
})
