hierarchy_sidebar_normalize_key <- function(value) {
  value <- as.character(value %||% "")
  value[is.na(value)] <- ""
  trimws(gsub("[[:space:]]+", " ", value))
}

hierarchy_sidebar_match_col <- function(fields, candidates) {
  if (length(fields) == 0 || length(candidates) == 0) return(NA_character_)
  idx <- match(tolower(candidates), tolower(fields), nomatch = 0L)
  idx <- idx[idx > 0L]
  if (length(idx) == 0) return(NA_character_)
  fields[[idx[[1]]]]
}

hierarchy_sidebar_quote <- function(con, identifier) {
  as.character(DBI::dbQuoteIdentifier(con, identifier))
}

read_project_site_unit_scope <- function(con, project_id) {
  empty <- data.frame(
    plotnumber = character(0),
    siteunit = character(0),
    stringsAsFactors = FALSE
  )

  project_id <- hierarchy_sidebar_normalize_key(project_id)
  if (!nzchar(project_id)) return(empty)
  if (!DBI::dbExistsTable(con, "Env") || !DBI::dbExistsTable(con, "SU")) return(empty)

  su_fields <- tryCatch(DBI::dbListFields(con, "SU"), error = function(e) character(0))
  env_fields <- tryCatch(DBI::dbListFields(con, "Env"), error = function(e) character(0))

  su_plot_col <- hierarchy_sidebar_match_col(su_fields, c("PlotNumber", "plotnumber"))
  su_site_col <- hierarchy_sidebar_match_col(su_fields, c("SiteUnit", "siteunit"))
  env_plot_col <- hierarchy_sidebar_match_col(env_fields, c("PlotNumber", "plotnumber"))
  env_project_col <- hierarchy_sidebar_match_col(env_fields, c("ProjectID", "projectid"))

  if (any(is.na(c(su_plot_col, su_site_col, env_plot_col, env_project_col)))) return(empty)

  sql <- paste(
    "SELECT DISTINCT",
    sprintf("s.%s AS plotnumber, s.%s AS siteunit", hierarchy_sidebar_quote(con, su_plot_col), hierarchy_sidebar_quote(con, su_site_col)),
    "FROM",
    sprintf("%s s", hierarchy_sidebar_quote(con, "SU")),
    "INNER JOIN (",
    sprintf(
      "SELECT DISTINCT %s AS plotnumber FROM %s WHERE %s = ? AND %s IS NOT NULL AND trim(CAST(%s AS VARCHAR)) <> ''",
      hierarchy_sidebar_quote(con, env_plot_col),
      hierarchy_sidebar_quote(con, "Env"),
      hierarchy_sidebar_quote(con, env_project_col),
      hierarchy_sidebar_quote(con, env_plot_col),
      hierarchy_sidebar_quote(con, env_plot_col)
    ),
    ") env ON env.plotnumber = s.plotnumber",
    "WHERE s.plotnumber IS NOT NULL",
    "AND trim(CAST(s.plotnumber AS VARCHAR)) <> ''",
    "AND s.siteunit IS NOT NULL",
    "AND trim(CAST(s.siteunit AS VARCHAR)) <> ''",
    "ORDER BY s.siteunit, s.plotnumber"
  )

  scope <- tryCatch(DBI::dbGetQuery(con, sql, list(project_id)), error = function(e) empty)
  if (nrow(scope) == 0) return(empty)

  scope$plotnumber <- as.character(scope$plotnumber)
  scope$siteunit <- trimws(as.character(scope$siteunit))
  unique(scope[, c("plotnumber", "siteunit"), drop = FALSE])
}

hierarchy_sidebar_reassign_plot <- function(con,
                                            plot_number,
                                            to_site_unit,
                                            user,
                                            fallback_project = NULL,
                                            allowed_site_units = NULL) {
  plot_number <- hierarchy_sidebar_normalize_key(plot_number)
  to_site_unit <- hierarchy_sidebar_normalize_key(to_site_unit)
  user <- if (nzchar(hierarchy_sidebar_normalize_key(user))) user else "Unknown"

  if (!nzchar(plot_number)) stop("PlotNumber is required.")
  if (!nzchar(to_site_unit)) stop("Target site unit is required.")
  if (!DBI::dbExistsTable(con, "SU")) stop("SU table is not available.")

  if (!is.null(allowed_site_units)) {
    allowed_keys <- hierarchy_sidebar_normalize_key(allowed_site_units)
    if (!(to_site_unit %in% allowed_keys)) {
      stop("Target site unit is not available in the current hierarchy scope.")
    }
  }

  su_fields <- tryCatch(DBI::dbListFields(con, "SU"), error = function(e) character(0))
  su_plot_col <- hierarchy_sidebar_match_col(su_fields, c("PlotNumber", "plotnumber"))
  su_site_col <- hierarchy_sidebar_match_col(su_fields, c("SiteUnit", "siteunit"))
  su_modified_col <- hierarchy_sidebar_match_col(su_fields, c("local_modified_utc"))

  if (any(is.na(c(su_plot_col, su_site_col)))) stop("SU table is missing required columns.")

  current_sql <- sprintf(
    "SELECT rowid, %s AS plotnumber, %s AS siteunit FROM %s WHERE %s = ? ORDER BY rowid",
    hierarchy_sidebar_quote(con, su_plot_col),
    hierarchy_sidebar_quote(con, su_site_col),
    hierarchy_sidebar_quote(con, "SU"),
    hierarchy_sidebar_quote(con, su_plot_col)
  )
  current_row <- DBI::dbGetQuery(con, current_sql, list(plot_number))

  from_site_unit <- if (nrow(current_row) == 0) "" else hierarchy_sidebar_normalize_key(current_row$siteunit[[1]])
  if (identical(from_site_unit, to_site_unit)) {
    return(list(
      ok = TRUE,
      changed = FALSE,
      plot_number = plot_number,
      from_site_unit = from_site_unit,
      to_site_unit = to_site_unit,
      env_field = NA_character_
    ))
  }

  project_id <- resolve_project_id_for_plot(con, plot_number, fallback_project)
  env_field <- NA_character_

  if (DBI::dbExistsTable(con, "Env")) {
    env_fields <- tryCatch(DBI::dbListFields(con, "Env"), error = function(e) character(0))
    env_field <- hierarchy_sidebar_match_col(env_fields, c("UserSiteUnit", "user_site_unit", "SiteUnit", "siteunit"))
    env_plot_col <- hierarchy_sidebar_match_col(env_fields, c("PlotNumber", "plotnumber"))
    env_modified_col <- hierarchy_sidebar_match_col(env_fields, c("local_modified_utc"))
    env_current_row <- if (!is.na(env_plot_col)) {
      tryCatch(
        DBI::dbGetQuery(
          con,
          sprintf(
            "SELECT * FROM %s WHERE %s = ? LIMIT 1",
            hierarchy_sidebar_quote(con, "Env"),
            hierarchy_sidebar_quote(con, env_plot_col)
          ),
          list(plot_number)
        ),
        error = function(e) data.frame()
      )
    } else {
      data.frame()
    }
  } else {
    env_plot_col <- NA_character_
    env_modified_col <- NA_character_
    env_current_row <- data.frame()
  }

  result <- DBI::dbWithTransaction(con, {
    if (nrow(current_row) == 0) {
      insert_cols <- c(hierarchy_sidebar_quote(con, su_plot_col), hierarchy_sidebar_quote(con, su_site_col))
      insert_vals <- c("?", "?")
      params <- list(plot_number, to_site_unit)
      if (!is.na(su_modified_col)) {
        insert_cols <- c(insert_cols, hierarchy_sidebar_quote(con, su_modified_col))
        insert_vals <- c(insert_vals, "CURRENT_TIMESTAMP")
      }
      insert_sql <- sprintf(
        "INSERT INTO %s (%s) VALUES (%s)",
        hierarchy_sidebar_quote(con, "SU"),
        paste(insert_cols, collapse = ", "),
        paste(insert_vals, collapse = ", ")
      )
      DBI::dbExecute(con, insert_sql, params)
      sync_record_local_change(
        con,
        table_name = "su",
        pk_value = plot_number,
        project_id = project_id,
        change_type = "insert"
      )
    } else {
      set_parts <- sprintf("%s = ?", hierarchy_sidebar_quote(con, su_site_col))
      if (!is.na(su_modified_col)) {
        set_parts <- c(set_parts, sprintf("%s = CURRENT_TIMESTAMP", hierarchy_sidebar_quote(con, su_modified_col)))
      }
      update_sql <- sprintf(
        "UPDATE %s SET %s WHERE %s = ?",
        hierarchy_sidebar_quote(con, "SU"),
        paste(set_parts, collapse = ", "),
        hierarchy_sidebar_quote(con, su_plot_col)
      )
      DBI::dbExecute(con, update_sql, list(to_site_unit, plot_number))
      sync_record_local_change(
        con,
        table_name = "su",
        pk_value = plot_number,
        project_id = project_id,
        change_type = "update",
        prior_payload = as.list(current_row[1, , drop = FALSE])
      )

      if (nrow(current_row) > 1) {
        dup_rowids <- current_row$rowid[-1]
        placeholders <- paste(rep("?", length(dup_rowids)), collapse = ", ")
        DBI::dbExecute(
          con,
          sprintf("DELETE FROM %s WHERE rowid IN (%s)", hierarchy_sidebar_quote(con, "SU"), placeholders),
          as.list(dup_rowids)
        )
      }
    }

    if (!is.na(env_field) && !is.na(env_plot_col)) {
      env_set_parts <- sprintf("%s = ?", hierarchy_sidebar_quote(con, env_field))
      if (!is.na(env_modified_col)) {
        env_set_parts <- c(env_set_parts, sprintf("%s = CURRENT_TIMESTAMP", hierarchy_sidebar_quote(con, env_modified_col)))
      }
      env_sql <- sprintf(
        "UPDATE %s SET %s WHERE %s = ?",
        hierarchy_sidebar_quote(con, "Env"),
        paste(env_set_parts, collapse = ", "),
        hierarchy_sidebar_quote(con, env_plot_col)
      )
      DBI::dbExecute(con, env_sql, list(to_site_unit, plot_number))
      sync_record_local_change(
        con,
        table_name = "env",
        pk_value = plot_number,
        project_id = project_id,
        change_type = if (nrow(env_current_row) == 0) "insert" else "update",
        prior_payload = if (nrow(env_current_row) > 0) as.list(env_current_row[1, , drop = FALSE]) else NULL
      )
    }

    invisible(TRUE)
  })

  if (isTRUE(result)) {
    log_audit_change(
      con,
      project_id,
      user,
      plot_number,
      "SU",
      "SiteUnit",
      if (nzchar(from_site_unit)) from_site_unit else NA,
      to_site_unit
    )

    if (!is.na(env_field)) {
      log_audit_change(
        con,
        project_id,
        user,
        plot_number,
        "Env",
        env_field,
        if (nzchar(from_site_unit)) from_site_unit else NA,
        to_site_unit
      )
    }
  }

  list(
    ok = TRUE,
    changed = TRUE,
    plot_number = plot_number,
    from_site_unit = from_site_unit,
    to_site_unit = to_site_unit,
    env_field = env_field
  )
}