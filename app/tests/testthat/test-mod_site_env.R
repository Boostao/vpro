# Tests for Site & Environment module

source(here::here("R", "logic_state.R"))
source(here::here("R", "logic_audit.R"))
source(here::here("R", "mod_site_env.R"))

setup_site_env_tables <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE Env (
      plotnumber TEXT PRIMARY KEY,
      _location TEXT,
      date TEXT,
      sitesurveyor TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      utmeasting TEXT,
      utmnorthing TEXT,
      elevation DOUBLE,
      slopegradient DOUBLE,
      aspect DOUBLE,
      mesoslopeposition TEXT,
      surfaceshape TEXT,
      moistureregime TEXT,
      nutrientregime TEXT,
      sitenotes TEXT,
      standage DOUBLE,
      sv_standheight DOUBLE,
      structuralstage TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE Humus (
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
    CREATE TABLE Mineral (
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
  DBI::dbExecute(con, "
    CREATE TABLE lists.USysTableOfLists (
      listname TEXT,
      item TEXT,
      itemdescription TEXT,
      itemorder INTEGER
    )
  ")

  DBI::dbExecute(
    con,
    "INSERT INTO Env (plotnumber, _location, latitude, longitude) VALUES (?, ?, ?, ?)",
    list("P1", "Loc A", 52.1, -119.2)
  )
}

test_that("mod_site_env loads inputs and saves header", {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("DT")

  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_site_env_tables(con)

  save_site_env_header(
    con,
    "P1",
    list(
      `_location` = "Loc B",
      date = NULL,
      sitesurveyor = NULL,
      latitude = 50.0,
      longitude = -120.5,
      utmeasting = NULL,
      utmnorthing = NULL,
      elevation = NULL,
      slopegradient = NULL,
      aspect = NULL,
      mesoslopeposition = NULL,
      surfaceshape = NULL,
      moistureregime = NULL,
      nutrientregime = NULL,
      sitenotes = NULL
    )
  )

  saved <- DBI::dbGetQuery(con, "SELECT _location, latitude, longitude FROM Env WHERE plotnumber = ?", list("P1"))
  expect_equal(saved$`_location`[1], "Loc B")
  expect_equal(saved$latitude[1], 50.0)
  expect_equal(saved$longitude[1], -120.5)
})

test_that("mod_site_env DMS apply and fill update inputs", {
  lat <- parse_dms_value("49 12 00 N", TRUE)
  lon <- parse_dms_value("123 30 00 W", FALSE)

  expect_equal(lat, 49.2)
  expect_equal(lon, -123.5)

  expect_match(format_dms_value(49.2, TRUE), "^49 12")
  expect_match(format_dms_value(-123.5, FALSE), "^123 30")
})
