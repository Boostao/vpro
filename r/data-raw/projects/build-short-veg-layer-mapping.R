# Build the versioned short-vegetation layer mapping outside package runtime.
# Run from the package root with:
# source("data-raw/projects/build-short-veg-layer-mapping.R")
# build_short_veg_layer_mapping()

short_veg_layer_mapping_root <- function() {
  script_path <- tryCatch(
    normalizePath(sys.frame(1)$ofile, winslash = "/"),
    error = function(e) NA_character_
  )
  candidates <- c(
    if (!is.na(script_path)) file.path(dirname(script_path), "..", ".."),
    getwd(), file.path(getwd(), ".."), file.path(getwd(), "..", "..")
  )
  candidates <- unique(normalizePath(candidates, mustWork = FALSE, winslash = "/"))
  match <- candidates[file.exists(file.path(candidates, "data-raw", "vpro", "LayerCode.csv"))]
  if (length(match)) return(match[[1L]])
  stop("Cannot locate the package root containing data-raw/vpro/LayerCode.csv.", call. = FALSE)
}

short_veg_layer_mapping_project_root <- short_veg_layer_mapping_root()

short_veg_layer_mapping_sha256 <- function(path) {
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(file = path, algo = "sha256"))
  }

  sha256sum <- Sys.which("sha256sum")
  if (nzchar(sha256sum)) {
    return(strsplit(system2(sha256sum, shQuote(path), stdout = TRUE), "[[:space:]]+")[[1L]][1L])
  }

  stop("A SHA-256 implementation is required (install digest or provide sha256sum).", call. = FALSE)
}

short_veg_layer_mapping_source_path <- function(path) {
  root <- normalizePath(short_veg_layer_mapping_project_root, winslash = "/")
  path <- normalizePath(path, winslash = "/")
  prefix <- paste0(root, "/")
  if (!startsWith(path, prefix)) {
    stop("LayerCode CSV must be located within the package repository.", call. = FALSE)
  }
  substring(path, nchar(prefix) + 1L)
}

short_veg_layer_mapping_read_csv <- function(path) {
  source_lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  nonblank_lines <- source_lines[nzchar(source_lines)]
  if (length(nonblank_lines) != 18L) {
    stop("LayerCode CSV must contain 18 nonblank physical rows including its header.", call. = FALSE)
  }
  value <- utils::read.csv(
    path,
    colClasses = "character",
    na.strings = "",
    check.names = FALSE,
    strip.white = FALSE,
    stringsAsFactors = FALSE
  )
  value[] <- lapply(value, function(column) {
    column[column == ""] <- NA_character_
    enc2utf8(column)
  })
  value
}

short_veg_layer_mapping_validate_sql <- function(path, expected_columns) {
  sql <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (!grepl('CREATE TABLE "LayerCode"', sql, fixed = TRUE) ||
      !grepl('uidx_LayerCode_LayerCode', sql, fixed = TRUE) ||
      !grepl('uidx_LayerCode_Layer1234567', sql, fixed = TRUE)) {
    stop("LayerCode SQL does not define the expected Access table and unique indexes.", call. = FALSE)
  }
  for (column in expected_columns) {
    if (!grepl(sprintf('"%s"', column), sql, fixed = TRUE)) {
      stop("LayerCode SQL is missing expected column: ", column, call. = FALSE)
    }
  }
  invisible(sql)
}

short_veg_layer_mapping_validate <- function(mapping) {
  expected_columns <- c(
    "LayerCode", "Layer1234567", "LayerCompact", "Layer", "LayerText",
    "Strata", "StrataNum", "Lifeform"
  )
  if (!identical(names(mapping), expected_columns)) {
    stop("LayerCode CSV columns do not match the Access table definition.", call. = FALSE)
  }
  # The supplied CSV has 18 physical lines including its header: 17 data rows
  # and one terminal blank line. read.csv correctly excludes the blank record.
  if (nrow(mapping) != 17L) {
    stop("LayerCode CSV must contain exactly 17 nonblank data rows.", call. = FALSE)
  }
  if (anyNA(mapping$LayerCode) || any(mapping$LayerCode == "") || anyDuplicated(mapping$LayerCode)) {
    stop("LayerCode values must be nonempty and unique.", call. = FALSE)
  }
  nonnull_layer_keys <- mapping$Layer1234567[!is.na(mapping$Layer1234567)]
  if (any(nonnull_layer_keys == "") || anyDuplicated(nonnull_layer_keys)) {
    stop("Non-null Layer1234567 values must be unique.", call. = FALSE)
  }

  report_keys <- c(as.character(1:10), "5a", "5b", "5c")
  if (!setequal(nonnull_layer_keys, report_keys)) {
    stop("Layer1234567 must contain report keys 1 through 10 and 5a, 5b, 5c.", call. = FALSE)
  }
  expected_padded <- sprintf("%02d", 1:10)
  actual_padded <- mapping$LayerCode[match(as.character(1:10), mapping$Layer1234567)]
  if (!identical(actual_padded, expected_padded)) {
    stop("LayerCode must preserve leading-zero text for report keys 1 through 10.", call. = FALSE)
  }

  expected_strata <- c(
    "1" = "A", "2" = "A", "3" = "A", "4" = "B", "5" = "B",
    "5a" = "B", "5b" = "B", "5c" = "B", "6" = "C", "7" = "D"
  )
  observed_strata <- mapping$Strata[match(names(expected_strata), mapping$Layer1234567)]
  if (!identical(unname(observed_strata), unname(expected_strata))) {
    stop("Layer1234567 report keys do not have the expected A/B/C/D strata mapping.", call. = FALSE)
  }
  invisible(mapping)
}

build_short_veg_layer_mapping <- function(
    output_path = file.path(short_veg_layer_mapping_project_root, "data-raw", "projects", "short-veg-layer-mapping-v1.sqlite"),
    source_csv = file.path(short_veg_layer_mapping_project_root, "data-raw", "vpro", "LayerCode.csv"),
    source_sql = file.path(short_veg_layer_mapping_project_root, "data-raw", "vpro", "LayerCode.sql")) {
  if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("RSQLite", quietly = TRUE)) {
    stop("Packages DBI and RSQLite are required.", call. = FALSE)
  }
  if (!file.exists(source_csv) || !file.exists(source_sql)) {
    stop("LayerCode CSV and SQL sources must exist.", call. = FALSE)
  }

  expected_columns <- c(
    "LayerCode", "Layer1234567", "LayerCompact", "Layer", "LayerText",
    "Strata", "StrataNum", "Lifeform"
  )
  short_veg_layer_mapping_validate_sql(source_sql, expected_columns)
  mapping <- short_veg_layer_mapping_read_csv(source_csv)
  short_veg_layer_mapping_validate(mapping)
  source_sha256 <- short_veg_layer_mapping_sha256(source_csv)
  source_path <- short_veg_layer_mapping_source_path(source_csv)

  output_path <- normalizePath(output_path, mustWork = FALSE, winslash = "/")
  output_dir <- dirname(output_path)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  temporary_output <- tempfile(
    pattern = paste0(".", basename(output_path), "-"),
    tmpdir = output_dir,
    fileext = ".sqlite"
  )
  on.exit(unlink(temporary_output), add = TRUE)

  con <- DBI::dbConnect(RSQLite::SQLite(), temporary_output)
  on.exit(if (!is.null(con)) DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, paste(
    "CREATE TABLE mapping_set (",
    "version TEXT PRIMARY KEY,",
    "source_sha256 TEXT NOT NULL,",
    "source_path TEXT NOT NULL,",
    "migration_intent TEXT NOT NULL,",
    "created_date TEXT NOT NULL",
    ")"
  ))
  DBI::dbExecute(con, paste(
    "CREATE TABLE layer_mapping (",
    "LayerCode TEXT NOT NULL PRIMARY KEY,",
    "Layer1234567 TEXT UNIQUE,",
    "LayerCompact TEXT,",
    "Layer TEXT,",
    "LayerText TEXT,",
    "Strata TEXT,",
    "StrataNum INTEGER,",
    "Lifeform TEXT",
    ")"
  ))
  DBI::dbExecute(con, 'CREATE INDEX idx_layer_mapping_StrataNum ON layer_mapping (StrataNum)')
  DBI::dbAppendTable(con, "layer_mapping", mapping)
  DBI::dbExecute(
    con,
    "INSERT INTO mapping_set VALUES (?, ?, ?, ?, ?)",
    params = list(
      "access-layercode-v1", source_sha256, source_path,
      "Versioned SQLite mapping for corrected short-vegetation Layer1234567 joins.",
      "2026-09-23"
    )
  )

  if (!identical(DBI::dbGetQuery(con, "PRAGMA integrity_check")[[1L]][[1L]], "ok") ||
      DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM layer_mapping")$n[[1L]] != 17L ||
      DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM mapping_set")$n[[1L]] != 1L) {
    stop("Built layer mapping did not pass SQLite validation.", call. = FALSE)
  }
  DBI::dbDisconnect(con)
  con <- NULL

  if (!file.rename(temporary_output, output_path)) {
    stop("Could not replace the layer mapping output with the validated temporary database.", call. = FALSE)
  }
  invisible(normalizePath(output_path, winslash = "/"))
}
