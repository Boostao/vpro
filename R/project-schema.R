# Project schema comparison -------------------------------------------------

vpro_schema_empty <- function() {
  data.frame(
    table = character(),
    field = character(),
    difference = character(),
    expected = character(),
    actual = character(),
    stringsAsFactors = FALSE
  )
}

vpro_schema_declared_type <- function(type) {
  type <- toupper(trimws(type))
  size <- rep(NA_integer_, length(type))
  has_size <- grepl("\\([[:space:]]*[0-9]+[[:space:]]*\\)$", type)
  size[has_size] <- as.integer(sub(
    ".*\\([[:space:]]*([0-9]+)[[:space:]]*\\)$",
    "\\1",
    type[has_size]
  ))
  base <- trimws(sub("\\([[:space:]]*[0-9]+[[:space:]]*\\)$", "", type))
  aliases <- c(
    "INT" = "INTEGER",
    "CHARACTER VARYING" = "VARCHAR",
    "VARYING CHARACTER" = "VARCHAR",
    "NVARCHAR" = "VARCHAR",
    "NCHAR" = "VARCHAR",
    "CHARACTER" = "VARCHAR",
    "CHAR" = "VARCHAR",
    "BOOL" = "BOOLEAN",
    "DOUBLE PRECISION" = "DOUBLE",
    "DATETIME" = "TIMESTAMP"
  )
  matched <- match(base, names(aliases))
  base[!is.na(matched)] <- unname(aliases[matched[!is.na(matched)]])
  data.frame(type = base, size = size, stringsAsFactors = FALSE)
}

vpro_schema_table <- function(con, table) {
  info <- DBI::dbGetQuery(
    con,
    paste0("PRAGMA table_info(", DBI::dbQuoteString(con, table), ")")
  )
  if (nrow(info) == 0L) {
    return(data.frame(
      field = character(),
      key = character(),
      type = character(),
      size = integer(),
      stringsAsFactors = FALSE
    ))
  }
  declared <- vpro_schema_declared_type(info$type)
  data.frame(
    field = info$name,
    key = tolower(info$name),
    type = declared$type,
    size = declared$size,
    stringsAsFactors = FALSE
  )
}

vpro_schema_difference <- function(table, field, difference, expected, actual) {
  data.frame(
    table = table,
    field = field,
    difference = difference,
    expected = expected,
    actual = actual,
    stringsAsFactors = FALSE
  )
}

vpro_schema_compare_table <- function(
  project_con,
  template_con,
  project_table,
  template_table
) {
  if (!DBI::dbExistsTable(template_con, template_table)) {
    stop("VPRO template table does not exist: ", template_table, call. = FALSE)
  }
  if (!DBI::dbExistsTable(project_con, project_table)) {
    return(vpro_schema_difference(
      project_table,
      NA_character_,
      "Missing table",
      template_table,
      NA_character_
    ))
  }

  expected <- vpro_schema_table(template_con, template_table)
  actual <- vpro_schema_table(project_con, project_table)
  differences <- list()
  index <- 0L
  for (row in seq_len(nrow(expected))) {
    match_row <- match(expected$key[[row]], actual$key)
    if (is.na(match_row)) {
      index <- index + 1L
      differences[[index]] <- vpro_schema_difference(
        project_table,
        expected$field[[row]],
        "Missing",
        expected$field[[row]],
        NA_character_
      )
      next
    }
    if (!identical(expected$type[[row]], actual$type[[match_row]])) {
      index <- index + 1L
      differences[[index]] <- vpro_schema_difference(
        project_table,
        expected$field[[row]],
        "Type",
        expected$type[[row]],
        actual$type[[match_row]]
      )
    }
    if (!identical(expected$size[[row]], actual$size[[match_row]])) {
      index <- index + 1L
      differences[[index]] <- vpro_schema_difference(
        project_table,
        expected$field[[row]],
        "Size",
        ifelse(is.na(expected$size[[row]]), NA_character_, expected$size[[row]]),
        ifelse(is.na(actual$size[[match_row]]), NA_character_, actual$size[[match_row]])
      )
    }
  }
  if (length(differences) == 0L) {
    return(vpro_schema_empty())
  }
  do.call(rbind, differences)
}

#' Compare a VPRO project with a schema template
#'
#' Reproduces the field checks in
#' `V7mdlCompareTablesToTemplate.CheckThisProject` for the eight core project
#' tables. Template fields are checked for presence, normalized declared type,
#' and declared size. Project-only fields are ignored, matching Access. Missing
#' project tables are reported explicitly rather than causing a DAO error.
#'
#' The default template is the bundled VP08 `Sample` project. Callers may supply
#' another SQLite database and project prefix. The comparison is read-only and
#' returns structured differences instead of opening Excel.
#'
#' @param path Path to the SQLite database containing the project to check.
#' @param project Project prefix to check.
#' @param template_path Path to a SQLite database containing the template
#'   project. Defaults to the bundled Sample database.
#' @param template_project Project prefix in `template_path`.
#'
#' @return A data frame with `table`, `field`, `difference`, `expected`, and
#'   `actual` columns. A conforming project returns an empty data frame.
#' @export
vpro_project_compare_schema <- function(
  path,
  project,
  template_path = vpro_bundled_file("extdata", "projects", "Sample.db"),
  template_project = "Sample"
) {
  project <- vpro_project_name(project)
  template_project <- vpro_project_name(template_project)
  if (length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("VPRO project database does not exist: ", path, call. = FALSE)
  }
  if (length(template_path) != 1L || is.na(template_path) || !file.exists(template_path)) {
    stop("VPRO template database does not exist: ", template_path, call. = FALSE)
  }

  project_con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(project_con), add = TRUE)
  template_con <- DBI::dbConnect(RSQLite::SQLite(), template_path)
  on.exit(DBI::dbDisconnect(template_con), add = TRUE)

  differences <- lapply(.vpro_core_project_suffixes, function(suffix) {
    vpro_schema_compare_table(
      project_con,
      template_con,
      vpro_project_table(project, suffix),
      vpro_project_table(template_project, suffix)
    )
  })
  differences <- differences[vapply(differences, nrow, integer(1)) > 0L]
  if (length(differences) == 0L) {
    return(vpro_schema_empty())
  }
  result <- do.call(rbind, differences)
  rownames(result) <- NULL
  result
}
