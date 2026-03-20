db_id <- function(tb, db = NULL, prj = FALSE) {
  if (prj) {
    tb <- sprintf("%s_%s", db, tb)
  }
  DBI::Id(db, tb)
}

# No table description concept in duckdb, so we hash the entire table to detect changes.
db_hash <- function(con, tb, db = NULL, prj = FALSE) {
  q <- sprintf(
    "SELECT bit_xor(hash(*columns(*)))::VARCHAR AS h FROM %s;",
    DBI::dbQuoteIdentifier(con, db_id(tb, db, prj))
  )
  result <- DBI::dbGetQuery(con, q)
  result$h
}

db_con <- function(db = ":memory:") {
  DBI::dbConnect(duckdb::duckdb(), db)
}

db_close <- function(con) {
  DBI::dbDisconnect(con, shutdown = TRUE)
  # I want to rm the object passed to con from the parent frame
  rm(list = deparse(substitute(con)), envir = parent.frame())
}

db_attach <- function(con, db) {
  # Check if databases files exist before trying to attach them, error handling if they don't exist
  exist_d <- db[file.exists(db)]
  miss_d <- setdiff(db, db)
  if (length(miss_d) > 0) {
    stop(
      "Missing databases detected.\nThe following databases were expected but not found: [",
      paste0(miss_d, collapse = ", "),
      "]\nPlease check that the expected databases are in place and try again."
    )
  }
  # Check for already attached databases
  atta_db <- db_query(con, "SHOW databases;")$database_name
  # Attach databases
  for (d in exist_d) {
    if ({d |> basename() |> tools::file_path_sans_ext()} %in% atta_db) {
      next
    }
    DBI::dbExecute(con, sprintf("ATTACH %s (TYPE sqlite);", DBI::dbQuoteLiteral(con, d)))
  }
}

db_insert <- function(con, tb, ..., db = NULL, prj = FALSE) {
  DBI::dbAppendTable(con, db_id(tb, db, prj), data.frame(...))
}

db_fields <- function(con, tb, db = NULL, prj = FALSE) {
  DBI::dbListFields(con, db_id(tb, db, prj))
}

db_query <- function(con, q, ...) {
  DBI::dbGetQuery(con, q, ...)
}

db_run <- function(con, q, ...) {
  DBI::dbExecute(con, q, ...)
}

db_rename <- function(con, tb, old_name, new_name, db = NULL, prj = FALSE) {
  DBI::dbExecute(
    con,
    sprintf(
      "ALTER TABLE %s RENAME COLUMN %s TO %s;",
      DBI::dbQuoteIdentifier(con, db_id(tb, db, prj)),
      DBI::dbQuoteIdentifier(con, old_name),
      DBI::dbQuoteIdentifier(con, new_name)
    )
  )
}

db_path <- function(loc, ..., db, ext = "db") {
  file.path(loc, "data", ..., paste0(db, ".", ext)) |> unique()
}

db_rename_fix01 <- function(con) {
  if ("JustEnglishName" %in% db_fields(con, "USysAllSpecs", "VLists")) {
    db_rename(con, "USysAllSpecs", "EnglishName", "CombinedEnglishName", "VLists")
    db_rename(con, "USysAllSpecs", "JustEnglishName", "EnglishName", "VLists")
  }
}