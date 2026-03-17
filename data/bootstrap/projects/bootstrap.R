library(DBI)
library(RSQLite)
library(mdbtoolr)
library(data.table)
accdb_path <- file.path(getwd(), "../VPRO_ACCESS/VPro64/VPro64.accdb")

# Assuming working directory is the root of the project vpro.git
workdir <- file.path(getwd(), "data/bootstrap/projects")
views_sql_path <- file.path(workdir, "views.sql")

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

# Listing project prefixes
projects <- list.files(workdir, pattern = "\\.csv$") |>
  tools::file_path_sans_ext() |>
  strsplit(split = "_") |>
  vapply(`[`, 1, FUN.VALUE = character(1)) |>
  unique() |>
  sort()

for (p in projects) {
  output <- file.path(workdir, sprintf("%s.db", p))
  unlink(output, force = TRUE)

  con <- DBI::dbConnect(RSQLite::SQLite(), output)

  DBI::dbExecute(con, "PRAGMA foreign_keys = ON;")

  tbs <- list.files(workdir, pattern = paste0("^", p, ".*\\.csv$")) |>
    tools::file_path_sans_ext() |>
    unique()

  env_tb <- sprintf("%s_Env", p)
  if (env_tb %in% tbs) {
    tbs <- c(env_tb, setdiff(tbs, env_tb))
  }

  for (tb in tbs) {
    sql_path <- file.path(workdir, sprintf("%s.sql", tb))
    statements <- read_sql_statements(sql_path)

    for (statement in statements) {
      DBI::dbExecute(con, statement)
    }
  }

  for (tb in tbs) {
    data_path <- file.path(workdir, sprintf("%s.csv", tb))
    table_name <- sub(paste0("^", p, "_"), "", tb)
    load_csv_into_table(con, table_name, data_path)

    if (FALSE) {
      # Validate against original Access DB
      test1 <- DBI::dbReadTable(DBI::dbConnect(mdbtoolr::mdb(), accdb_path), tb) |> data.table::setDT()
      test2 <- DBI::dbReadTable(con, table_name) |> data.table::setDT()
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
      }
      if (!isTRUE(all.equal(test1, test2, ignore.row.order = TRUE)) &&
          !isTRUE(all.equal(test1, test2, tolerance = sqrt(.Machine$double.eps) * 100))) {
        browser()
        stop(sprintf("Data mismatch for table %s in project %s", table_name, p))
      }
    }

  }

  for (statement in read_sql_statements(views_sql_path)) {
    DBI::dbExecute(con, statement)
  }

  DBI::dbDisconnect(con)
}
