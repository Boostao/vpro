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

hierarchy_sidebar_resolve_table <- function(con, project_id = NULL, prefer_base = TRUE) {
  project_id <- hierarchy_sidebar_normalize_key(project_id)

  if (!isTRUE(prefer_base) && nzchar(project_id)) {
    prefixed <- resolve_prefixed_table(con, project_id, "_Hierarchy")
    if (!is.null(prefixed) && DBI::dbExistsTable(con, prefixed)) {
      return(prefixed)
    }
  }

  if (DBI::dbExistsTable(con, "Hierarchy")) {
    return("Hierarchy")
  }

  if (nzchar(project_id)) {
    prefixed <- resolve_prefixed_table(con, project_id, "_Hierarchy")
    if (!is.null(prefixed) && DBI::dbExistsTable(con, prefixed)) {
      return(prefixed)
    }
  }

  tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
  hierarchy_tables <- tables[grepl("(^Hierarchy$|_Hierarchy$)", tables, ignore.case = TRUE)]
  if (length(hierarchy_tables) == 0) {
    return(NA_character_)
  }

  hierarchy_tables[[1]]
}

hierarchy_sidebar_hierarchy_columns <- function(con, table_name) {
  if (!nzchar(table_name) || !DBI::dbExistsTable(con, table_name)) {
    return(list())
  }

  fields <- tryCatch(DBI::dbListFields(con, table_name), error = function(e) character(0))
  list(
    id = hierarchy_sidebar_match_col(fields, c("ID", "id")),
    parent = hierarchy_sidebar_match_col(fields, c("Parent", "parent")),
    name = hierarchy_sidebar_match_col(fields, c("Name", "_name", "name")),
    level = hierarchy_sidebar_match_col(fields, c("Level", "_level", "level")),
    myorder = hierarchy_sidebar_match_col(fields, c("MyOrder", "myorder"))
  )
}

hierarchy_sidebar_normalize_id <- function(value) {
  value <- as.character(value %||% "")
  value[is.na(value)] <- ""
  trimws(value)
}

hierarchy_sidebar_read_nodes <- function(con, project_id = NULL, table_name = NULL) {
  target_table <- hierarchy_sidebar_normalize_key(table_name)
  if (!nzchar(target_table)) {
    target_table <- hierarchy_sidebar_resolve_table(con, project_id = project_id)
  }
  if (!nzchar(target_table) || is.na(target_table) || !DBI::dbExistsTable(con, target_table)) {
    return(data.frame(
      ID = character(0),
      Name = character(0),
      Parent = character(0),
      Level = numeric(0),
      MyOrder = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  cols <- hierarchy_sidebar_hierarchy_columns(con, target_table)
  if (any(is.na(c(cols$id, cols$name, cols$parent)) | !nzchar(c(cols$id, cols$name, cols$parent)))) {
    return(data.frame(
      ID = character(0),
      Name = character(0),
      Parent = character(0),
      Level = numeric(0),
      MyOrder = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  select_parts <- c(
    sprintf("%s AS ID", hierarchy_sidebar_quote(con, cols$id)),
    sprintf("%s AS Name", hierarchy_sidebar_quote(con, cols$name))
  )
  if (!is.na(cols$parent) && nzchar(cols$parent)) {
    select_parts <- c(select_parts, sprintf("%s AS Parent", hierarchy_sidebar_quote(con, cols$parent)))
  } else {
    select_parts <- c(select_parts, "NULL AS Parent")
  }
  if (!is.na(cols$level) && nzchar(cols$level)) {
    select_parts <- c(select_parts, sprintf("%s AS Level", hierarchy_sidebar_quote(con, cols$level)))
  } else {
    select_parts <- c(select_parts, "NULL AS Level")
  }
  if (!is.na(cols$myorder) && nzchar(cols$myorder)) {
    select_parts <- c(select_parts, sprintf("%s AS MyOrder", hierarchy_sidebar_quote(con, cols$myorder)))
  } else {
    select_parts <- c(select_parts, "NULL AS MyOrder")
  }

  order_parts <- if (!is.na(cols$myorder) && nzchar(cols$myorder)) {
    c("Parent NULLS FIRST", "MyOrder NULLS LAST", "Name")
  } else {
    c("Parent NULLS FIRST", "Name")
  }

  sql <- sprintf(
    "SELECT %s FROM %s ORDER BY %s",
    paste(select_parts, collapse = ", "),
    hierarchy_sidebar_quote(con, target_table),
    paste(order_parts, collapse = ", ")
  )

  nodes <- tryCatch(DBI::dbGetQuery(con, sql), error = function(e) data.frame())
  if (nrow(nodes) == 0) {
    return(data.frame(
      ID = character(0),
      Name = character(0),
      Parent = character(0),
      Level = numeric(0),
      MyOrder = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  nodes$ID <- hierarchy_sidebar_normalize_id(nodes$ID)
  nodes$Name <- trimws(as.character(nodes$Name %||% ""))
  nodes$Parent <- hierarchy_sidebar_normalize_id(nodes$Parent)
  nodes$Parent[!nzchar(nodes$Parent)] <- NA_character_
  nodes$Level <- suppressWarnings(as.numeric(nodes$Level))
  nodes$MyOrder <- suppressWarnings(as.numeric(nodes$MyOrder))
  nodes <- nodes[nzchar(nodes$ID), , drop = FALSE]

  dup_idx <- duplicated(nodes$ID)
  if (any(dup_idx)) {
    nodes <- nodes[!dup_idx, , drop = FALSE]
  }

  nodes
}

hierarchy_sidebar_get_descendants <- function(df, node_id) {
  if (is.null(df) || nrow(df) == 0) return(character(0))
  node_id <- hierarchy_sidebar_normalize_id(node_id)
  if (!nzchar(node_id)) return(character(0))

  direct <- df$ID[!is.na(df$Parent) & df$Parent == node_id]
  if (length(direct) == 0) return(character(0))

  descendants <- unlist(lapply(direct, function(child_id) hierarchy_sidebar_get_descendants(df, child_id)), use.names = FALSE)
  unique(c(direct, descendants))
}

hierarchy_sidebar_get_path_ids <- function(df, node_id, max_steps = 200L) {
  if (is.null(df) || nrow(df) == 0) return(character(0))
  node_id <- hierarchy_sidebar_normalize_id(node_id)
  if (!nzchar(node_id)) return(character(0))

  ids <- character(0)
  current_id <- node_id
  steps <- 0L

  while (nzchar(current_id) && steps < max_steps) {
    row <- df[df$ID == current_id, , drop = FALSE]
    if (nrow(row) == 0) break
    ids <- c(row$ID[[1]], ids)
    current_id <- hierarchy_sidebar_normalize_id(row$Parent[[1]])
    steps <- steps + 1L
  }

  ids
}

hierarchy_sidebar_get_path_names <- function(df, node_id, max_steps = 200L) {
  path_ids <- hierarchy_sidebar_get_path_ids(df, node_id, max_steps = max_steps)
  if (length(path_ids) == 0) return(character(0))
  vapply(path_ids, function(path_id) {
    row <- df[df$ID == path_id, , drop = FALSE]
    if (nrow(row) == 0) "" else row$Name[[1]]
  }, character(1))
}

hierarchy_sidebar_move_node <- function(con,
                                        node_id,
                                        parent_id = NULL,
                                        project_id = NULL,
                                        table_name = NULL) {
  node_id <- hierarchy_sidebar_normalize_id(node_id)
  parent_id <- hierarchy_sidebar_normalize_id(parent_id)
  if (!nzchar(node_id)) {
    stop("Node id is required.")
  }
  if (identical(node_id, parent_id)) {
    stop("Move blocked: cannot move under self.")
  }

  target_table <- hierarchy_sidebar_normalize_key(table_name)
  if (!nzchar(target_table)) {
    target_table <- hierarchy_sidebar_resolve_table(con, project_id = project_id)
  }
  if (!nzchar(target_table) || is.na(target_table) || !DBI::dbExistsTable(con, target_table)) {
    stop("Hierarchy table is not available.")
  }

  cols <- hierarchy_sidebar_hierarchy_columns(con, target_table)
  if (any(is.na(c(cols$id, cols$name, cols$parent)) | !nzchar(c(cols$id, cols$name, cols$parent)))) {
    stop("Hierarchy table is missing required columns.")
  }

  nodes <- hierarchy_sidebar_read_nodes(con, project_id = project_id, table_name = target_table)
  node_row <- nodes[nodes$ID == node_id, , drop = FALSE]
  if (nrow(node_row) == 0) {
    stop("Selected node was not found in the hierarchy table.")
  }

  parent_row <- data.frame()
  if (nzchar(parent_id)) {
    parent_row <- nodes[nodes$ID == parent_id, , drop = FALSE]
    if (nrow(parent_row) == 0) {
      stop("Target parent was not found in the hierarchy table.")
    }
  }

  descendants <- hierarchy_sidebar_get_descendants(nodes, node_id)
  if (parent_id %in% descendants) {
    stop("Move blocked: cannot move under a descendant.")
  }

  from_parent_id <- hierarchy_sidebar_normalize_id(node_row$Parent[[1]])
  if (identical(from_parent_id, parent_id)) {
    return(list(
      ok = TRUE,
      changed = FALSE,
      node_id = node_id,
      node_name = node_row$Name[[1]],
      from_parent_id = if (nzchar(from_parent_id)) from_parent_id else NA_character_,
      to_parent_id = if (nzchar(parent_id)) parent_id else NA_character_,
      table_name = target_table,
      path = hierarchy_sidebar_get_path_names(nodes, node_id)
    ))
  }

  move_ids <- c(node_id, descendants)
  current_level <- suppressWarnings(as.numeric(node_row$Level[[1]]))
  parent_level <- if (nrow(parent_row) == 0) -1 else suppressWarnings(as.numeric(parent_row$Level[[1]]))
  can_update_levels <- !is.na(cols$level) && nzchar(cols$level) && is.finite(current_level) && is.finite(parent_level)
  level_map <- list()
  if (isTRUE(can_update_levels)) {
    delta <- as.integer(parent_level + 1L - current_level)
    if (!identical(delta, 0L)) {
      for (target_id in move_ids) {
        old_level <- suppressWarnings(as.numeric(nodes$Level[nodes$ID == target_id][[1]]))
        if (is.finite(old_level)) {
          level_map[[target_id]] <- as.integer(old_level + delta)
        }
      }
    }
  }

  DBI::dbWithTransaction(con, {
    set_parts <- sprintf("%s = ?", hierarchy_sidebar_quote(con, cols$parent))
    params <- list(if (nzchar(parent_id)) parent_id else NULL)

    if (!is.na(cols$myorder) && nzchar(cols$myorder)) {
      siblings <- nodes[
        nodes$ID != node_id & (
          (is.na(nodes$Parent) & !nzchar(parent_id)) |
            (!is.na(nodes$Parent) & nodes$Parent == parent_id)
        ),
        , drop = FALSE
      ]
      if (nrow(siblings) == 0 || all(!is.finite(siblings$MyOrder))) {
        order_val <- 1L
      } else {
        order_val <- as.integer(max(siblings$MyOrder[is.finite(siblings$MyOrder)], na.rm = TRUE) + 1L)
      }
      set_parts <- c(set_parts, sprintf("%s = ?", hierarchy_sidebar_quote(con, cols$myorder)))
      params <- c(params, list(order_val))
    }

    update_sql <- sprintf(
      "UPDATE %s SET %s WHERE %s = ?",
      hierarchy_sidebar_quote(con, target_table),
      paste(set_parts, collapse = ", "),
      hierarchy_sidebar_quote(con, cols$id)
    )
    DBI::dbExecute(con, update_sql, c(params, list(node_id)))

    if (length(level_map) > 0) {
      level_sql <- sprintf(
        "UPDATE %s SET %s = ? WHERE %s = ?",
        hierarchy_sidebar_quote(con, target_table),
        hierarchy_sidebar_quote(con, cols$level),
        hierarchy_sidebar_quote(con, cols$id)
      )
      for (target_id in names(level_map)) {
        DBI::dbExecute(con, level_sql, list(level_map[[target_id]], target_id))
      }
    }
  })

  updated_nodes <- hierarchy_sidebar_read_nodes(con, project_id = project_id, table_name = target_table)
  list(
    ok = TRUE,
    changed = TRUE,
    node_id = node_id,
    node_name = node_row$Name[[1]],
    from_parent_id = if (nzchar(from_parent_id)) from_parent_id else NA_character_,
    to_parent_id = if (nzchar(parent_id)) parent_id else NA_character_,
    table_name = target_table,
    path = hierarchy_sidebar_get_path_names(updated_nodes, node_id)
  )
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