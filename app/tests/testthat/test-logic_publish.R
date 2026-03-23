test_that("build_download_log_query handles empty filters", {
  query <- build_download_log_query(list())
  expect_true(grepl("FROM master.public_export.download_log", query$sql))
  expect_false(grepl("WHERE", query$sql))
  expect_length(query$params, 0)
})

test_that("build_download_log_query builds parameter order", {
  from_time <- as.POSIXct("2026-02-01 00:00:00", tz = "UTC")
  to_time <- as.POSIXct("2026-02-02 00:00:00", tz = "UTC")
  query <- build_download_log_query(
    filters = list(
      user = "bob",
      dataset = "veg",
      format = "rds",
      status = "failed",
      from = from_time,
      to = to_time
    ),
    limit = 25
  )

  expect_true(grepl("username ILIKE \\?", query$sql))
  expect_true(grepl("dataset_name ILIKE \\?", query$sql))
  expect_true(grepl("format = \\?", query$sql))
  expect_true(grepl("download_status = \\?", query$sql))
  expect_true(grepl("timestamp_utc >= \\?", query$sql))
  expect_true(grepl("timestamp_utc <= \\?", query$sql))
  expect_true(grepl("LIMIT 25", query$sql))

  expect_equal(length(query$params), 6)
  expect_equal(query$params[[1]], "%bob%")
  expect_equal(query$params[[2]], "%veg%")
  expect_equal(query$params[[3]], "rds")
  expect_equal(query$params[[4]], "failed")
  expect_equal(query$params[[5]], from_time)
  expect_equal(query$params[[6]], to_time)
})

test_that("publish_project_dataset writes BEC Map contract files (RDS/CSV) and registry", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")

  source(here::here("app", "R", "logic", "00.db.R"), local = TRUE)
  source(here::here("R", "logic_compliance.R"), local = TRUE)
  source(here::here("R", "logic_publish.R"), local = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Env (plotnumber TEXT, projectid TEXT, date_sampled DATE, latitude DOUBLE, longitude DOUBLE, bec_zone TEXT, bec_subzone TEXT, bec_site_series TEXT, _location TEXT)")
  DBI::dbExecute(con, "CREATE TABLE SU (plotnumber TEXT, dataquality TEXT)")
  DBI::dbExecute(con, "CREATE TABLE USysProjectMetadata (projectid TEXT, projecttitle TEXT, ispublic TEXT, beczone TEXT, description TEXT)")
  DBI::dbExecute(con, "CREATE TABLE vw_USysAllVeg (plotnumber TEXT, projectid TEXT, code TEXT, layer TEXT, cover TEXT)")
  DBI::dbExecute(con, "CREATE TABLE Lump (sppcode TEXT, lumpcode TEXT, _use INTEGER)")

  DBI::dbExecute(con, "INSERT INTO USysProjectMetadata VALUES ('P1', 'Project One', 'True', 'IDF', 'Test project')")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('PLOT-001', 'P1', DATE '2024-06-01', 49.1234567, -120.7654321, 'IDF', 'xh', '01', 'Near Somewhere')")
  DBI::dbExecute(con, "INSERT INTO SU VALUES ('PLOT-001', 'Good')")

  DBI::dbExecute(con, "INSERT INTO vw_USysAllVeg VALUES ('PLOT-001', 'P1', 'FD', 'A', '50')")
  DBI::dbExecute(con, "INSERT INTO vw_USysAllVeg VALUES ('PLOT-001', 'P1', 'HW', 'A', '20')")
  DBI::dbExecute(con, "INSERT INTO Lump VALUES ('HW', 'FD', 1)")

  out_dir <- tempfile("published_")
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  res <- publish_project_dataset(
    project_id = "P1",
    output_dir = out_dir,
    formats = c("rds", "csv"),
    apply_lumping = TRUE,
    con = con,
    coordinate_round_digits = 5,
    is_public = TRUE,
    overwrite = TRUE
  )

  expect_equal(res$project_id, "P1")
  expect_true(file.exists(file.path(out_dir, "P1_environment.rds")))
  expect_true(file.exists(file.path(out_dir, "P1_vegetation.rds")))
  expect_true(file.exists(file.path(out_dir, "P1_metadata.rds")))
  expect_true(file.exists(file.path(out_dir, "P1_environment.csv")))
  expect_true(file.exists(file.path(out_dir, "P1_vegetation.csv")))
  expect_true(file.exists(file.path(out_dir, "P1_metadata.csv")))

  env <- readRDS(file.path(out_dir, "P1_environment.rds"))
  veg <- readRDS(file.path(out_dir, "P1_vegetation.rds"))
  meta <- readRDS(file.path(out_dir, "P1_metadata.rds"))

  expect_true(all(c("plotnumber", "date_sampled", "latitude", "longitude") %in% names(env)))
  expect_equal(env$latitude, round(49.1234567, 5))
  expect_equal(env$longitude, round(-120.7654321, 5))
  expect_true("data_quality" %in% names(env))

  expect_true(all(c("plot_id", "species_code", "layer", "cover") %in% names(veg)))
  expect_true(is.character(veg$cover))
  expect_equal(unique(veg$species_code), "FD")

  expect_true(all(c("project_id", "project_name", "is_public") %in% names(meta)))
  expect_true(isTRUE(meta$is_public[1]))

  reg_path <- file.path(out_dir, "publication_registry.csv")
  expect_true(file.exists(reg_path))
  reg <- read.csv(reg_path, stringsAsFactors = FALSE)
  expect_true(nrow(reg) >= 1)
  expect_equal(reg$project_id[nrow(reg)], "P1")
})

test_that("validate_for_publishing flags missing/zero coordinates", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")

  source(here::here("app", "R", "logic", "00.db.R"), local = TRUE)
  source(here::here("R", "logic_compliance.R"), local = TRUE)
  source(here::here("R", "logic_publish.R"), local = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE Env (plotnumber TEXT, projectid TEXT, latitude DOUBLE, longitude DOUBLE)")
  DBI::dbExecute(con, "INSERT INTO Env VALUES ('PLOT-001', 'P2', 0, NULL)")

  v <- validate_for_publishing(con, "P2")
  expect_false(v$passed)
  expect_true(any(v$detail_tibble$rule %in% c("publish_bad_coords")))
})

test_that("publish_project_dataset can write XLSX via existing exporter (optional)", {
  skip_if_not_installed("openxlsx")
  skip_if_not(file.exists("data/vpro.duckdb"), "Local DuckDB file not present")

  source(here::here("app", "R", "logic", "00.db.R"), local = TRUE)
  source(here::here("R", "logic_compliance.R"), local = TRUE)
  source(here::here("R", "logic_publish.R"), local = TRUE)

  con <- db_con("data/vpro.duckdb")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Find a publishable project id with valid coordinates
  pid <- tryCatch({
    res <- DBI::dbGetQuery(
      con,
      paste(
        "SELECT projectid AS project_id",
        "FROM Env",
        "WHERE latitude IS NOT NULL AND longitude IS NOT NULL",
        "AND latitude <> 0 AND longitude <> 0",
        "LIMIT 1"
      )
    )
    if (nrow(res) == 0) NA_character_ else as.character(res$project_id[1])
  }, error = function(e) NA_character_)

  skip_if(is.na(pid), "No publishable project with coordinates in local DB")

  out_dir <- tempfile("published_")
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  res <- publish_project_dataset(
    project_id = pid,
    output_dir = out_dir,
    formats = c("rds", "xlsx"),
    apply_lumping = FALSE,
    con = con,
    overwrite = TRUE,
    fail_on_validation = FALSE
  )

  expect_true(file.exists(file.path(out_dir, paste0(pid, "_combined.xlsx"))))
})
