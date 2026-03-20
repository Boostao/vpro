# Tests for compliance checks

source(here::here("R", "logic_compliance.R"))

setup_compliance_tables <- function(con) {
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS lists")
  DBI::dbExecute(con, "
    CREATE TABLE Env (
      plotnumber TEXT,
      projectid TEXT,
      zone TEXT,
      subzone TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation DOUBLE,
      mesoslopeposition TEXT,
      surfaceshape TEXT,
      slopegradient DOUBLE,
      aspect DOUBLE,
      rootingdepth DOUBLE
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE Veg (
      plotnumber TEXT,
      species TEXT,
      projectid TEXT,
      cover TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.SppList (
      code TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE VIEW vw_USysAllVeg AS
    SELECT plotnumber,
           species AS species_code,
           'A'::TEXT AS layer,
          cover AS cover_value,
           projectid
    FROM Veg
  ")

  DBI::dbExecute(con, "DROP TABLE IF EXISTS lists.USysZoneList")
  DBI::dbExecute(con, "
    CREATE TABLE lists.USysZoneList (
      zone_code TEXT,
      subzone TEXT
    )
  ")

  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P1', 'PRJ', 'BAD', 'BAD', 62, -150, 5000, 'BAD', 'BAD', 150, 400, -5)")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P1', 'PRJ', 'BAD', 'BAD', 55, -120, 100, 'BAD', 'OK', 10, 180, 10)")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('P2', 'PRJ', 'ICH', 'vm', 55, -120, 100, 'BAD', 'OK', 10, 180, 10)")
  DBI::dbExecute(con, "INSERT INTO Veg VALUES ('P1', 'BAD', 'PRJ', 'BADCODE')")
  DBI::dbExecute(con, "INSERT INTO Veg VALUES ('P1', 'BAD', 'PRJ', '20')")
  DBI::dbExecute(con, "INSERT INTO Veg VALUES ('P2', 'OK', 'PRJ', '200')")
  if ("code" %in% DBI::dbListFields(con, DBI::Id(schema = "lists", table = "SppList"))) {
    DBI::dbExecute(con, "INSERT INTO lists.SppList (code) VALUES ('OK')")
  }
  zone_fields <- DBI::dbListFields(con, DBI::Id(schema = "lists", table = "USysZoneList"))
  if (all(c("zone_code", "subzone") %in% zone_fields)) {
    DBI::dbExecute(con, "INSERT INTO lists.USysZoneList (zone_code, subzone) VALUES ('ICH', 'wk')")
    DBI::dbExecute(con, "INSERT INTO lists.USysZoneList (zone_code, subzone) VALUES ('CWH', 'vm')")
  } else if ("zone_code" %in% zone_fields) {
    DBI::dbExecute(con, "INSERT INTO lists.USysZoneList (zone_code) VALUES ('ICH')")
  }

  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS lists.USysTableOfLists (listname TEXT, item TEXT)")
  DBI::dbExecute(con, "INSERT INTO lists.USysTableOfLists (listname, item) VALUES ('MesoSlopePosition', 'MID')")
  DBI::dbExecute(con, "INSERT INTO lists.USysTableOfLists (listname, item) VALUES ('SurfaceShape', 'OK')")
}

test_that("run_compliance_checks returns rule summaries", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_compliance_tables(con)

  result <- run_compliance_checks(con)

  expect_false(result$passed)
  expect_true(nrow(result$summary_tibble) > 0)
  expect_true(nrow(result$detail_tibble) > 0)
  expect_true(any(grepl("^fk_list_", result$detail_tibble$rule)))
  expect_true(any(result$detail_tibble$rule == "code_cover"))
  expect_true(any(result$detail_tibble$rule == "range_cover"))
  expect_true(any(result$detail_tibble$rule == "range_lat"))
  expect_true(any(result$detail_tibble$rule == "range_lon"))
  expect_true(any(result$detail_tibble$rule == "range_elev"))
  expect_true(any(result$detail_tibble$rule == "range_slope"))
  expect_true(any(result$detail_tibble$rule == "range_aspect"))
  expect_true(any(result$detail_tibble$rule == "fk_zone_subzone"))
  expect_true(any(result$detail_tibble$rule == "dup_plot"))
  expect_true(any(result$detail_tibble$rule == "dup_veg"))
  expect_true(any(grepl("^range_nonneg_", result$detail_tibble$rule)))
})

test_that("required fields flag missing values", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_compliance_tables(con)

  DBI::dbExecute(
    con,
    "INSERT INTO Env (plotnumber, projectid, zone, subzone, latitude, longitude, elevation, mesoslopeposition, slopegradient, aspect, rootingdepth)
     VALUES ('P3', 'PRJ', NULL, '', 55, -120, 100, 'MID', 10, 180, 10)"
  )
  missing <- check_required_fields(con, project_id = "PRJ")

  expect_true(any(missing$column == "zone"))
  expect_true(any(missing$column == "subzone"))
})
