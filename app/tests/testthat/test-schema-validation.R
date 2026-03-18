testthat::context("schema-validation")
source(here::here("tests", "testthat", "setup.R"))
source(here::here("tests", "testthat", "helpers.R"))
source(here::here("R", "db_connections.R"))

# Set PG env vars for schema validation tests
if (!nzchar(Sys.getenv("PGPORT")))              Sys.setenv(PGPORT              = "5433")
if (!nzchar(Sys.getenv("PGHOST")))              Sys.setenv(PGHOST              = "localhost")
if (!nzchar(Sys.getenv("PGDATABASE")))          Sys.setenv(PGDATABASE          = "becmaster")
if (!nzchar(Sys.getenv("VPRO_PG_APP_PASSWORD"))) Sys.setenv(VPRO_PG_APP_PASSWORD = "testpass")
if (!nzchar(Sys.getenv("VPRO_PG_APP_USER")))    Sys.setenv(VPRO_PG_APP_USER    = "vpro_app")

# ---- Helper Functions ----

#' Normalize column type names across databases
normalize_column_type <- function(type) {
  type <- tolower(trimws(type))
  type <- gsub("character varying(\\s*\\(.*\\))?", "text", type)
  type <- gsub("varchar(\\s*\\(.*\\))?", "text", type)
  type <- gsub("^numeric(\\s*\\(.*\\))?$", "numeric", type)
  type <- gsub("^decimal(\\s*\\(.*\\))?$", "numeric", type)
  type <- gsub("double precision", "numeric", type)  # Treat as numeric
  type <- gsub("^double$", "numeric", type)  # DuckDB double → numeric
  type <- gsub("^float$", "real", type)  # DuckDB float → real
  type <- gsub("^real$", "real", type)  # PG real → real
  type <- gsub("timestamp(\\s|$|.*)", "timestamp", type)
  type <- gsub("jsonb(\\s|$|\\(.*\\))?", "jsonb", type)
  type <- gsub("^json$", "jsonb", type)
  type <- gsub("^serial$", "integer", type)
  return(type)
}

#' Get schema via information_schema
get_table_schema <- function(con, catalog, schema, table) {
  tryCatch({
    if (nzchar(catalog)) {
      query <- sprintf(
        "SELECT column_name, data_type FROM %s.information_schema.columns 
         WHERE table_schema = '%s' AND table_name = '%s'
         ORDER BY ordinal_position",
        catalog, schema, table
      )
    } else {
      query <- sprintf(
        "SELECT column_name, data_type FROM information_schema.columns 
         WHERE table_schema = '%s' AND table_name = '%s'
         ORDER BY ordinal_position",
        schema, table
      )
    }
    result <- DBI::dbGetQuery(con, query)
    if (nrow(result) == 0) {
      return(data.frame(column_name = character(0), column_type = character(0)))
    }
    data.frame(
      column_name = tolower(result$column_name),
      column_type = result$data_type,
      stringsAsFactors = FALSE
    )
  }, error = function(e) {
    warning("Error getting schema: ", e$message)
    data.frame(column_name = character(0), column_type = character(0))
  })
}

#' Compare two schemas
compare_schemas <- function(schema1, schema2, table_name) {
  result <- list(
    table = table_name,
    match = TRUE,
    cols1 = nrow(schema1),
    cols2 = nrow(schema2),
    missing_in_2 = character(0),
    missing_in_1 = character(0),
    type_mismatches = character(0)
  )
  
  if (nrow(schema1) == 0 || nrow(schema2) == 0) {
    result$match <- FALSE
    return(result)
  }
  
  schema1$column_name <- tolower(schema1$column_name)
  schema2$column_name <- tolower(schema2$column_name)
  schema1$column_type <- normalize_column_type(schema1$column_type)
  schema2$column_type <- normalize_column_type(schema2$column_type)
  
  missing_in_2 <- setdiff(schema1$column_name, schema2$column_name)
  missing_in_1 <- setdiff(schema2$column_name, schema1$column_name)
  
  if (length(missing_in_2) > 0) {
    result$match <- FALSE
    result$missing_in_2 <- missing_in_2
  }
  if (length(missing_in_1) > 0) {
    result$match <- FALSE
    result$missing_in_1 <- missing_in_1
  }
  
  common_cols <- intersect(schema1$column_name, schema2$column_name)
  for (col in common_cols) {
    type1 <- schema1$column_type[schema1$column_name == col]
    type2 <- schema2$column_type[schema2$column_name == col]
    if (type1 != type2) {
      result$match <- FALSE
      result$type_mismatches <- c(result$type_mismatches, 
                                   paste0(col, " (DuckDB: ", type1, " vs PG: ", type2, ")"))
    }
  }
  
  return(result)
}

#' Format comparison error
format_comparison_error <- function(comp, db1 = "DuckDB", db2 = "PostgreSQL") {
  parts <- c(sprintf("%s: schemas don't match", comp$table))
  if (comp$cols1 > 0 || comp$cols2 > 0) {
    parts <- c(parts, sprintf("  %s columns: %d, %s columns: %d", 
                              db1, comp$cols1, db2, comp$cols2))
  }
  if (length(comp$missing_in_2) > 0) {
    parts <- c(parts, sprintf("  Missing in %s: %s", db2, paste(comp$missing_in_2, collapse = ", ")))
  }
  if (length(comp$missing_in_1) > 0) {
    parts <- c(parts, sprintf("  Missing in %s: %s", db1, paste(comp$missing_in_1, collapse = ", ")))
  }
  if (length(comp$type_mismatches) > 0) {
    parts <- c(parts, sprintf("  Type mismatches: %s", paste(comp$type_mismatches, collapse = ", ")))
  }
  paste(parts, collapse = "\n")
}

# ---- Test Helper ----
run_schema_test <- function(schema, table) {
  testthat::skip_if_not(pg_available())
  
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  attach_cloud(con, fail_on_error = TRUE)
  
  duck_schema <- get_table_schema(con, "", schema, table)
  pg_schema <- get_table_schema(con, "master", schema, table)
  
  comp <- compare_schemas(duck_schema, pg_schema, paste0(schema, ".", table))
  testthat::expect_true(comp$match, label = format_comparison_error(comp))
}

# ---- Core Tables Tests ----
testthat::test_that("core.admin table schema matches", { run_schema_test("core", "admin") })
testthat::test_that("core.metadata table schema matches", { run_schema_test("core", "metadata") })
testthat::test_that("core.hierarchy table schema matches", { run_schema_test("core", "hierarchy") })
testthat::test_that("core.env table schema matches", { run_schema_test("core", "env") })
testthat::test_that("core.humus table schema matches", { run_schema_test("core", "humus") })
testthat::test_that("core.mineral table schema matches", { run_schema_test("core", "mineral") })
testthat::test_that("core.other table schema matches", { run_schema_test("core", "other") })
testthat::test_that("core.veg table schema matches", { run_schema_test("core", "veg") })
testthat::test_that("core.herbarium table schema matches", { run_schema_test("core", "herbarium") })
testthat::test_that("core.su table schema matches", { run_schema_test("core", "su") })
testthat::test_that("core.profile table schema matches", { run_schema_test("core", "profile") })
testthat::test_that("core.veg_profile table schema matches", { run_schema_test("core", "veg_profile") })
testthat::test_that("core.lump table schema matches", { run_schema_test("core", "lump") })
testthat::test_that("core.theme table schema matches", { run_schema_test("core", "theme") })
testthat::test_that("core.audit table schema matches", { run_schema_test("core", "audit") })

# ---- Staging Tables Tests ----
testthat::test_that("staging.admin table schema matches", { run_schema_test("staging", "admin") })
testthat::test_that("staging.metadata table schema matches", { run_schema_test("staging", "metadata") })
testthat::test_that("staging.hierarchy table schema matches", { run_schema_test("staging", "hierarchy") })
testthat::test_that("staging.env table schema matches", { run_schema_test("staging", "env") })
testthat::test_that("staging.humus table schema matches", { run_schema_test("staging", "humus") })
testthat::test_that("staging.mineral table schema matches", { run_schema_test("staging", "mineral") })
testthat::test_that("staging.other table schema matches", { run_schema_test("staging", "other") })
testthat::test_that("staging.veg table schema matches", { run_schema_test("staging", "veg") })
testthat::test_that("staging.herbarium table schema matches", { run_schema_test("staging", "herbarium") })
testthat::test_that("staging.su table schema matches", { run_schema_test("staging", "su") })
testthat::test_that("staging.profile table schema matches", { run_schema_test("staging", "profile") })
testthat::test_that("staging.veg_profile table schema matches", { run_schema_test("staging", "veg_profile") })
testthat::test_that("staging.lump table schema matches", { run_schema_test("staging", "lump") })
testthat::test_that("staging.theme table schema matches", { run_schema_test("staging", "theme") })
testthat::test_that("staging.audit table schema matches", { run_schema_test("staging", "audit") })

# ---- Lists Tables Tests ----
testthat::test_that("lists.spplist table schema matches", { run_schema_test("lists", "spplist") })
testthat::test_that("lists.layercode table schema matches", { run_schema_test("lists", "layercode") })
testthat::test_that("lists.usyszonelist table schema matches", { run_schema_test("lists", "usyszonelist") })
testthat::test_that("lists.usyssubzonelist table schema matches", { run_schema_test("lists", "usyssubzonelist") })
testthat::test_that("lists.usystableoflists table schema matches", { run_schema_test("lists", "usystableoflists") })
testthat::test_that("lists.usyssppattributes table schema matches", { run_schema_test("lists", "usyssppattributes") })

# ---- Summary Test ----
testthat::test_that("All core, staging, and list tables have matching schemas", {
  testthat::skip_if_not(pg_available())
  
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  attach_cloud(con, fail_on_error = TRUE)
  
  tables <- list(
    # Core Sample_ tables
    list(schema = "core", table = "admin"),
    list(schema = "core", table = "metadata"),
    list(schema = "core", table = "hierarchy"),
    list(schema = "core", table = "env"),
    list(schema = "core", table = "humus"),
    list(schema = "core", table = "mineral"),
    list(schema = "core", table = "other"),
    list(schema = "core", table = "veg"),
    list(schema = "core", table = "herbarium"),
    list(schema = "core", table = "su"),
    list(schema = "core", table = "profile"),
    list(schema = "core", table = "veg_profile"),
    list(schema = "core", table = "lump"),
    list(schema = "core", table = "theme"),
    list(schema = "core", table = "audit"),
    # Staging tables
    list(schema = "staging", table = "admin"),
    list(schema = "staging", table = "metadata"),
    list(schema = "staging", table = "hierarchy"),
    list(schema = "staging", table = "env"),
    list(schema = "staging", table = "humus"),
    list(schema = "staging", table = "mineral"),
    list(schema = "staging", table = "other"),
    list(schema = "staging", table = "veg"),
    list(schema = "staging", table = "herbarium"),
    list(schema = "staging", table = "su"),
    list(schema = "staging", table = "profile"),
    list(schema = "staging", table = "veg_profile"),
    list(schema = "staging", table = "lump"),
    list(schema = "staging", table = "theme"),
    list(schema = "staging", table = "audit"),
    # Lists tables
    list(schema = "lists", table = "spplist"),
    list(schema = "lists", table = "layercode"),
    list(schema = "lists", table = "usyszonelist"),
    list(schema = "lists", table = "usyssubzonelist"),
    list(schema = "lists", table = "usystableoflists"),
    list(schema = "lists", table = "usyssppattributes")
  )
  
  all_pass <- TRUE
  error_msgs <- c()
  
  for (tbl in tables) {
    duck_schema <- get_table_schema(con, "", tbl$schema, tbl$table)
    pg_schema <- get_table_schema(con, "master", tbl$schema, tbl$table)
    comp <- compare_schemas(duck_schema, pg_schema, paste0(tbl$schema, ".", tbl$table))
    if (!comp$match) {
      all_pass <- FALSE
      error_msgs <- c(error_msgs, format_comparison_error(comp))
    }
  }
  
  if (!all_pass) {
    error_msg <- paste(c("Schema validation failures:", error_msgs), collapse = "\n\n")
  } else {
    error_msg <- ""
  }
  
  testthat::expect_true(all_pass, label = error_msg)
})
