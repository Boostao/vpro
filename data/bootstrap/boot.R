library(DBI)
library(RSQLite)
library(mdbtoolr)
library(data.table)

validate <- FALSE

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
  fk_info <- DBI::dbGetQuery(
    con,
    sprintf('PRAGMA foreign_key_list("%s");', table_name)
  )
  index_list <- DBI::dbGetQuery(
    con,
    sprintf('PRAGMA index_list("%s");', table_name)
  )

  text_fields <- table_info$name[grepl("CHAR|CLOB|TEXT", table_info$type, ignore.case = TRUE)]
  fk_fields <- unique(fk_info$from)
  unique_index_names <- index_list$name[index_list$unique == 1]
  unique_fields <- unique(unlist(lapply(unique_index_names, function(index_name) {
    DBI::dbGetQuery(
      con,
      sprintf('PRAGMA index_info("%s");', index_name)
    )$name
  })))
  blank_as_null_fields <- unique(c(text_fields, fk_fields, intersect(text_fields, unique_fields)))
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

source("data/bootstrap/projects/bootstrap.R")
source("data/bootstrap/pics/bootstrap.R")
source("data/bootstrap/messages/bootstrap.R")
source("data/bootstrap/lists/bootstrap.R")