# Environment validation ----------------------------------------------------

vpro_environment_validation_empty <- function() {
  data.frame(
    list_name = character(),
    field = character(),
    PlotNumber = character(),
    value = character(),
    stringsAsFactors = FALSE
  )
}

vpro_environment_validation_skipped <- function() {
  data.frame(
    list_name = character(),
    field = character(),
    reason = character(),
    stringsAsFactors = FALSE
  )
}

vpro_environment_reference <- function(path) {
  if (length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("VPRO list-reference database does not exist: ", path, call. = FALSE)
  }
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!DBI::dbExistsTable(con, "USysTableOfLists")) {
    stop("VPRO list-reference table does not exist: USysTableOfLists", call. = FALSE)
  }
  required <- c("ListName", "Item", "FieldUsedIn", "ValidateLoops", "Validate")
  missing <- setdiff(required, DBI::dbListFields(con, "USysTableOfLists"))
  if (length(missing) > 0L) {
    stop(
      "VPRO list-reference table is missing required fields: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  normalizePath(path)
}

vpro_environment_definitions <- function(con) {
  DBI::dbGetQuery(
    con,
    paste(
      'SELECT MIN("ListName") AS "ListName",',
      'MIN("FieldUsedIn") AS "FieldUsedIn", "ValidateLoops"',
      'FROM "vpro_list_reference"."USysTableOfLists"',
      'WHERE "Validate" <> 0',
      'GROUP BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"',
      'ORDER BY "ListName" COLLATE NOCASE, "FieldUsedIn" COLLATE NOCASE, "ValidateLoops"'
    )
  )
}

vpro_environment_fields <- function(definition) {
  list_name <- definition$ListName[[1]]
  field <- definition$FieldUsedIn[[1]]
  loops <- definition$ValidateLoops[[1]]
  if (is.na(list_name) || trimws(list_name) == "") {
    return(list(fields = character(), reason = "ListName is null or blank."))
  }
  if (is.na(field) || trimws(field) == "") {
    return(list(fields = character(), reason = "FieldUsedIn is null or blank."))
  }
  if (is.na(loops) || trimws(as.character(loops)) == "") {
    return(list(fields = field, reason = NULL))
  }
  numeric_loops <- suppressWarnings(as.numeric(loops))
  if (is.na(numeric_loops) || !is.finite(numeric_loops) || numeric_loops != trunc(numeric_loops)) {
    return(list(fields = character(), reason = "ValidateLoops is not an integer."))
  }
  if (numeric_loops <= 0) {
    return(list(fields = field, reason = NULL))
  }
  list(fields = paste0(field, seq_len(numeric_loops)), reason = NULL)
}

vpro_environment_validation_attach <- function(con, path, alias) {
  DBI::dbExecute(
    con,
    paste(
      "ATTACH DATABASE",
      DBI::dbQuoteString(con, normalizePath(path)),
      "AS",
      DBI::dbQuoteIdentifier(con, alias)
    )
  )
  invisible(TRUE)
}

vpro_environment_source <- function(con, context, project, use_active_su) {
  env_table <- vpro_project_table(project$project, "Env")
  admin_table <- vpro_project_table(project$project, "Admin")
  env <- DBI::dbQuoteIdentifier(con, env_table)
  admin <- DBI::dbQuoteIdentifier(con, admin_table)
  joins <- paste(
    "FROM",
    env,
    "AS env INNER JOIN",
    admin,
    'AS admin ON env."PlotNumber" = admin."Plot"'
  )

  if (use_active_su && !is.null(context$active_su)) {
    su_record <- context$active_su
    if (normalizePath(su_record$path) == normalizePath(project$path)) {
      su <- DBI::dbQuoteIdentifier(con, su_record$table)
    } else {
      vpro_environment_validation_attach(con, su_record$path, "vpro_active_su")
      su <- paste(
        DBI::dbQuoteIdentifier(con, "vpro_active_su"),
        DBI::dbQuoteIdentifier(con, su_record$table),
        sep = "."
      )
    }
    joins <- paste(
      joins,
      "INNER JOIN",
      su,
      'AS su ON env."PlotNumber" = su."PlotNumber"'
    )
  }

  list(
    joins = joins,
    env_fields = DBI::dbListFields(con, env_table),
    admin_fields = DBI::dbListFields(con, admin_table)
  )
}

vpro_environment_field_expression <- function(con, field, source) {
  env_match <- match(tolower(field), tolower(source$env_fields))
  admin_match <- match(tolower(field), tolower(source$admin_fields))
  if (!is.na(env_match) && !is.na(admin_match)) {
    return(list(expression = NULL, reason = "Field is ambiguous across Env and Admin."))
  }
  if (is.na(env_match) && is.na(admin_match)) {
    return(list(expression = NULL, reason = "Field does not exist in the active environment schema."))
  }
  if (!is.na(env_match)) {
    actual <- source$env_fields[[env_match]]
    return(list(
      expression = paste0("env.", DBI::dbQuoteIdentifier(con, actual)),
      reason = NULL
    ))
  }
  actual <- source$admin_fields[[admin_match]]
  list(
    expression = paste0("admin.", DBI::dbQuoteIdentifier(con, actual)),
    reason = NULL
  )
}

#' Find environment codes absent from configured VPRO lists
#'
#' Reproduces `V7mdlReportsValidateEnvData.ValidateEnvData` and its field-level
#' `ReportData` checks. Enabled definitions in `USysTableOfLists` identify either
#' one environment field or a numbered field series through `ValidateLoops`.
#' Null and empty environment values are ignored, matching Access; whitespace is
#' not trimmed.
#'
#' Matching uses SQLite `NOCASE` collation as a portable approximation of Access
#' database text comparison. The active SU restricts the Env-Admin join by
#' default, matching the current `USysEnv` query. Results are deterministic and
#' replace Excel automation. Definitions that cannot be checked are returned in
#' `skipped` instead of being hidden behind field-level modal errors.
#'
#' @param context A VPRO project context with an active project.
#' @param reference_path Path to a SQLite database containing
#'   `USysTableOfLists`. Defaults to the bundled VLists database.
#' @param use_active_su Whether to restrict validation through the active SU when
#'   one is selected. Set to `FALSE` to validate the complete active project.
#'
#' @return A list with `findings` and `skipped` data frames. Findings contain
#'   `list_name`, `field`, `PlotNumber`, and `value`. Skipped definitions contain
#'   `list_name`, `field`, and `reason`.
#' @export
vpro_validate_environment_codes <- function(
  context,
  reference_path = vpro_bundled_file("extdata", "VLists.db"),
  use_active_su = TRUE
) {
  project <- vpro_plot_active(context)
  reference_path <- vpro_environment_reference(reference_path)
  use_active_su <- vpro_vegetation_validation_flag(use_active_su, "use_active_su")

  con <- DBI::dbConnect(RSQLite::SQLite(), project$path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  vpro_environment_validation_attach(con, reference_path, "vpro_list_reference")
  source <- vpro_environment_source(con, context, project, use_active_su)
  definitions <- vpro_environment_definitions(con)
  findings <- list()
  skipped <- list()
  finding_index <- 0L
  skipped_index <- 0L

  for (row in seq_len(nrow(definitions))) {
    definition <- definitions[row, , drop = FALSE]
    expanded <- vpro_environment_fields(definition)
    if (!is.null(expanded$reason)) {
      skipped_index <- skipped_index + 1L
      skipped[[skipped_index]] <- data.frame(
        list_name = ifelse(is.na(definition$ListName[[1]]), NA_character_, definition$ListName[[1]]),
        field = ifelse(is.na(definition$FieldUsedIn[[1]]), NA_character_, definition$FieldUsedIn[[1]]),
        reason = expanded$reason,
        stringsAsFactors = FALSE
      )
      next
    }

    for (field in expanded$fields) {
      resolved <- vpro_environment_field_expression(con, field, source)
      if (!is.null(resolved$reason)) {
        skipped_index <- skipped_index + 1L
        skipped[[skipped_index]] <- data.frame(
          list_name = definition$ListName[[1]],
          field = field,
          reason = resolved$reason,
          stringsAsFactors = FALSE
        )
        next
      }

      reference <- paste(
        DBI::dbQuoteIdentifier(con, "vpro_list_reference"),
        DBI::dbQuoteIdentifier(con, "USysTableOfLists"),
        sep = "."
      )
      sql <- paste(
        'SELECT DISTINCT CAST(env."PlotNumber" AS TEXT) AS "PlotNumber",',
        "CAST(",
        resolved$expression,
        'AS TEXT) AS "value"',
        source$joins,
        "WHERE",
        resolved$expression,
        "IS NOT NULL",
        "AND",
        resolved$expression,
        "<> ''",
        "AND NOT EXISTS (SELECT 1 FROM",
        reference,
        "AS lists",
        'WHERE lists."ListName" = ? COLLATE NOCASE AND',
        resolved$expression,
        '= lists."Item" COLLATE NOCASE)',
        'ORDER BY "PlotNumber", "value"'
      )
      result <- DBI::dbGetQuery(con, sql, params = list(definition$ListName[[1]]))
      if (nrow(result) > 0L) {
        finding_index <- finding_index + 1L
        findings[[finding_index]] <- data.frame(
          list_name = definition$ListName[[1]],
          field = field,
          PlotNumber = result$PlotNumber,
          value = result$value,
          stringsAsFactors = FALSE
        )
      }
    }
  }

  findings <- if (length(findings) == 0L) {
    vpro_environment_validation_empty()
  } else {
    result <- do.call(rbind, findings)
    rownames(result) <- NULL
    result
  }
  skipped <- if (length(skipped) == 0L) {
    vpro_environment_validation_skipped()
  } else {
    result <- do.call(rbind, skipped)
    rownames(result) <- NULL
    result
  }
  list(findings = findings, skipped = skipped)
}
