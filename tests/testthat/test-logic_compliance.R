# Tests for compliance checks

source(here::here("R", "logic_compliance.R"))

setup_compliance_tables <- function(con) {
  DBI::dbExecute(con, "CREATE SCHEMA IF NOT EXISTS lists")
  DBI::dbExecute(con, "
    CREATE TABLE Sample_Env (
      plotnumber TEXT,
      projectid TEXT,
      zone TEXT,
      subzone TEXT,
      latitude DOUBLE,
      longitude DOUBLE,
      elevation DOUBLE
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE Sample_Veg (
      plotnumber TEXT,
      species TEXT,
      projectid TEXT
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
           NULL::TEXT AS cover_value,
           projectid
    FROM Sample_Veg
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS lists.USysZoneList (
      zone_code TEXT,
      subzone TEXT
    )
  ")

  DBI::dbExecute(con, "INSERT INTO Sample_Env VALUES ('P1', 'PRJ', 'BAD', 'BAD', 62, -150, 5000)")
  DBI::dbExecute(con, "INSERT INTO Sample_Env VALUES ('P1', 'PRJ', 'BAD', 'BAD', 55, -120, 100)")
  DBI::dbExecute(con, "INSERT INTO Sample_Veg VALUES ('P1', 'BAD', 'PRJ')")
  DBI::dbExecute(con, "INSERT INTO Sample_Veg VALUES ('P1', 'BAD', 'PRJ')")
  if ("code" %in% DBI::dbListFields(con, DBI::Id(schema = "lists", table = "SppList"))) {
    DBI::dbExecute(con, "INSERT INTO lists.SppList (code) VALUES ('OK')")
  }
  zone_fields <- DBI::dbListFields(con, DBI::Id(schema = "lists", table = "USysZoneList"))
  if (all(c("zone_code", "subzone") %in% zone_fields)) {
    DBI::dbExecute(con, "INSERT INTO lists.USysZoneList (zone_code, subzone) VALUES ('ICH', 'wk')")
  } else if ("zone_code" %in% zone_fields) {
    DBI::dbExecute(con, "INSERT INTO lists.USysZoneList (zone_code) VALUES ('ICH')")
  }
}

test_that("run_compliance_checks returns rule summaries", {
  con <- test_connect_duckdb()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  setup_compliance_tables(con)

  result <- run_compliance_checks(con)

  expect_false(result$passed)
  expect_true(nrow(result$summary_tibble) > 0)
  expect_true(nrow(result$detail_tibble) > 0)
})
