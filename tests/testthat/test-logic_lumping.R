# Tests for species lumping logic

library(dplyr)

source(here::here("R", "logic_lumping.R"))

test_that("apply_lumping returns input when Sample_Lump missing", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  df <- data.frame(
    plotnumber = c("P1", "P1"),
    species = c("AB", "FD"),
    cover_num = c(10, 20)
  )

  result <- expect_warning(
    apply_lumping(con, df, group_cols = c("plotnumber"), measure_cols = c("cover_num")),
    "Sample_Lump table not found"
  )

  expect_equal(result, df)
})

test_that("apply_lumping replaces and aggregates lumped species", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE Sample_Lump (
      sppcode TEXT,
      lumpcode TEXT,
      _use INTEGER
    )
  ")
  DBI::dbExecute(
    con,
    "INSERT INTO Sample_Lump (sppcode, lumpcode, _use) VALUES (?, ?, ?)",
    list("AB", "ABIE", 1)
  )
  DBI::dbExecute(
    con,
    "INSERT INTO Sample_Lump (sppcode, lumpcode, _use) VALUES (?, ?, ?)",
    list("FD", "ABIE", 1)
  )

  df <- data.frame(
    plotnumber = c("P1", "P1", "P2"),
    species = c("AB", "FD", "FD"),
    cover_num = c(10, 20, NA)
  )

  result <- apply_lumping(con, df, group_cols = c("plotnumber"), measure_cols = c("cover_num"))
  result <- arrange(result, plotnumber, species)

  expect_equal(nrow(result), 2)
  expect_equal(result$species, c("ABIE", "ABIE"))
  expect_equal(result$cover_num, c(30, 0))
})
