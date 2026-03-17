library(DBI)
library(RSQLite)
library(mdbtoolr)
library(data.table)

validate <- TRUE
outputdir <- file.path(getwd(), "data/bootstrap/output")
dir.create(outputdir, recursive = TRUE, showWarnings = FALSE)

read_sql_statements <- function(path) {
  lines <- readLines(path, warn = FALSE)
  statements <- character()
  buffer <- character()
  in_block_comment <- FALSE

  for (line in lines) {
    trimmed <- trimws(line)

    if (in_block_comment) {
      if (grepl("\\*/", trimmed)) {
        in_block_comment <- FALSE
      }
      next
    }

    if (!nzchar(trimmed) || grepl("^--", trimmed)) {
      next
    }

    if (grepl("^/\\*", trimmed)) {
      if (!grepl("\\*/", trimmed)) {
        in_block_comment <- TRUE
      }
      next
    }

    buffer <- c(buffer, line)

    if (grepl(";\\s*$", trimmed)) {
      statements <- c(statements, paste(buffer, collapse = "\n"))
      buffer <- character()
    }
  }

  remainder <- trimws(paste(buffer, collapse = "\n"))
  if (nzchar(remainder)) {
    statements <- c(statements, remainder)
  }

  statements
}

load_csv_into_table <- function(con, table_name, data_path) {
  table_info <- DBI::dbGetQuery(
    con,
    sprintf('PRAGMA table_info("%s");', table_name)
  )

  text_fields <- table_info$name[grepl("CHAR|CLOB|TEXT", table_info$type, ignore.case = TRUE)]
  header <- names(
    utils::read.csv(
      data_path,
      nrows = 0,
      check.names = FALSE,
      stringsAsFactors = FALSE,
      na.strings = ""
    )
  )
  col_classes <- rep(NA_character_, length(header))
  names(col_classes) <- header
  col_classes[intersect(header, text_fields)] <- "character"

  df <- utils::read.csv(
    data_path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    colClasses = col_classes,
    na.strings = ""
  )

  table_fields <- DBI::dbListFields(con, table_name)
  extra_fields <- setdiff(names(df), table_fields)

  if (length(extra_fields) > 0) {
    stop(
      sprintf(
        "CSV %s contains columns not present in table %s: %s",
        basename(data_path),
        table_name,
        paste(extra_fields, collapse = ", ")
      )
    )
  }

  missing_fields <- setdiff(table_fields, names(df))
  for (field in missing_fields) {
    df[[field]] <- NA
  }

  df <- df[, table_fields, drop = FALSE]
  DBI::dbAppendTable(con, table_name, df)
}

normalize_text_for_compare <- function(x) {
  if (!inherits(x, "character")) {
    return(x)
  }

  vapply(x, function(value) {
    if (is.na(value)) {
      return(NA_character_)
    }

    value <- iconv(value, from = "", to = "UTF-8", sub = "byte")
    value <- gsub("\r\n", "\n", value, fixed = TRUE)
    gsub("\r", "\n", value, fixed = TRUE)
  }, character(1), USE.NAMES = FALSE)
}

harmonize_validation_tables <- function(test1, test2) {
  for (nm in names(test1)) {
    if (inherits(test2[[nm]], "blob") && inherits(test1[[nm]], "character")) {
      test2[, (nm) := vapply(test2[[nm]], function(x) {
        if (is.null(x)) NA_character_ else rawToChar(x)
      }, character(1))]
    } else if (!inherits(test2[[nm]], class(test1[[nm]]))) {
      if (inherits(test1[[nm]], "POSIXct")) {
        test2[, (nm) := mdbtoolr:::.coerce_datetime(test2[[nm]])]
      } else {
        test2[, (nm) := as(test2[[nm]], class(test1[[nm]])[1])]
      }
    }

    if (inherits(test1[[nm]], "character") && inherits(test2[[nm]], "character")) {
      test1[[nm]] <- normalize_text_for_compare(test1[[nm]])
      test2[[nm]] <- normalize_text_for_compare(test2[[nm]])
    }
  }

  list(test1 = test1, test2 = test2)
}

validation_tables_equal <- function(test1, test2) {
  isTRUE(all.equal(test1, test2, ignore.row.order = TRUE)) ||
    isTRUE(all.equal(test1, test2, tolerance = sqrt(.Machine$double.eps) * 100))
}

source("data/bootstrap/projects/bootstrap.R")
source("data/bootstrap/pics/bootstrap.R")
source("data/bootstrap/messages/bootstrap.R")
source("data/bootstrap/lists/bootstrap.R")
source("data/bootstrap/metadata/bootstrap.R")