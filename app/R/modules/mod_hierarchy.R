hierarchy_label <- function(name, id) {
  paste0(name, " [", id, "]")
}

parse_hierarchy_id <- function(label) {
  if (is.null(label) || length(label) == 0) return(NA_integer_)
  m <- regmatches(label, regexec("\\[(\\d+)\\]$", label))
  if (length(m) == 0 || length(m[[1]]) < 2) return(NA_integer_)
  as.integer(m[[1]][2])
}

order_hierarchy_rows <- function(df) {
  if (nrow(df) == 0) return(df)
  if ("MyOrder" %in% names(df)) {
    order_vals <- suppressWarnings(as.numeric(df$MyOrder))
    return(df[order(order_vals, df$Name, na.last = TRUE), , drop = FALSE])
  }
  df[order(df$Name), , drop = FALSE]
}

build_hierarchy_tree <- function(df, parent_id = NA_integer_, selected_id = NA_integer_, open_ids = integer(0)) {
  if (nrow(df) == 0) return(list())
  if (is.na(parent_id)) {
    roots <- df[is.na(df$Parent), , drop = FALSE]
  } else {
    roots <- df[!is.na(df$Parent) & df$Parent == parent_id, , drop = FALSE]
  }
  if (nrow(roots) == 0) return(list())

  roots <- order_hierarchy_rows(roots)

  tree <- list()
  for (i in seq_len(nrow(roots))) {
    row <- roots[i, ]
    label <- hierarchy_label(row$Name, row$ID)
    child_tree <- build_hierarchy_tree(df, row$ID, selected_id, open_ids)
    if (!is.na(selected_id) && row$ID == selected_id) {
      tree[[label]] <- structure(child_tree, stselected = TRUE, stopened = TRUE)
    } else if (row$ID %in% open_ids) {
      tree[[label]] <- structure(child_tree, stopened = TRUE)
    } else {
      tree[[label]] <- child_tree
    }
  }

  tree
}

hierarchy_has_column <- function(con, column_name) {
  if (!DBI::dbExistsTable(con, "Hierarchy")) return(FALSE)
  column_name %in% DBI::dbListFields(con, "Hierarchy")
}

hierarchy_table_has_column <- function(con, table_name, column_name) {
  if (!DBI::dbExistsTable(con, table_name)) return(FALSE)
  column_name %in% DBI::dbListFields(con, table_name)
}

table_has_columns <- function(con, table_name, columns) {
  if (!DBI::dbExistsTable(con, table_name)) return(FALSE)
  fields <- DBI::dbListFields(con, table_name)
  all(columns %in% fields)
}

get_sibling_order <- function(df, parent_id) {
  if (nrow(df) == 0) return(data.frame())
  siblings <- df[df$Parent == parent_id | (is.na(df$Parent) & is.na(parent_id)), , drop = FALSE]
  if (nrow(siblings) == 0) return(data.frame())

  if ("MyOrder" %in% names(siblings)) {
    order_vals <- suppressWarnings(as.numeric(siblings$MyOrder))
    siblings$order_val <- order_vals
    siblings <- siblings[order(siblings$order_val, siblings$Name, na.last = TRUE), , drop = FALSE]
  } else {
    siblings <- siblings[order(siblings$Name), , drop = FALSE]
  }

  siblings
}

get_descendants <- function(df, node_id) {
  if (nrow(df) == 0) return(integer(0))
  direct <- df$ID[!is.na(df$Parent) & df$Parent == node_id]
  if (length(direct) == 0) return(integer(0))
  children <- unlist(lapply(direct, function(id) get_descendants(df, id)))
  unique(c(direct, children))
}

get_node_path <- function(df, node_id, max_steps = 50L) {
  if (nrow(df) == 0) return(character(0))
  path <- character(0)
  current_id <- node_id
  steps <- 0L

  while (!is.na(current_id) && steps < max_steps) {
    row <- df[df$ID == current_id, , drop = FALSE]
    if (nrow(row) == 0) break
    path <- c(row$Name[1], path)
    current_id <- row$Parent[1]
    steps <- steps + 1L
  }

  path
}

get_node_path_ids <- function(df, node_id, max_steps = 50L) {
  if (nrow(df) == 0) return(integer(0))
  ids <- integer(0)
  current_id <- node_id
  steps <- 0L

  while (!is.na(current_id) && steps < max_steps) {
    row <- df[df$ID == current_id, , drop = FALSE]
    if (nrow(row) == 0) break
    ids <- c(row$ID[1], ids)
    current_id <- row$Parent[1]
    steps <- steps + 1L
  }

  ids
}

find_orphan_nodes <- function(df) {
  if (nrow(df) == 0) return(integer(0))
  parents <- unique(df$Parent[!is.na(df$Parent)])
  missing_parents <- setdiff(parents, df$ID)
  if (length(missing_parents) == 0) return(integer(0))
  unique(df$ID[df$Parent %in% missing_parents])
}

fix_orphan_nodes <- function(con) {
  if (!DBI::dbExistsTable(con, "Hierarchy")) return(0L)
  df <- DBI::dbGetQuery(con, "SELECT ID, Parent FROM Hierarchy")
  orphan_ids <- find_orphan_nodes(df)
  if (length(orphan_ids) == 0) return(0L)

  placeholders <- paste(rep("?", length(orphan_ids)), collapse = ", ")
  sql <- sprintf("UPDATE Hierarchy SET Parent = NULL WHERE ID IN (%s)", placeholders)
  DBI::dbExecute(con, sql, as.list(orphan_ids))
  length(orphan_ids)
}

get_subtree <- function(df, node_id) {
  ids <- c(node_id, get_descendants(df, node_id))
  df[df$ID %in% ids, , drop = FALSE]
}

get_subtree_names <- function(df, node_id) {
  subtree <- get_subtree(df, node_id)
  if (nrow(subtree) == 0) return(character(0))
  unique(subtree$Name)
}

get_lowest_tilde_ids <- function(df) {
  if (nrow(df) == 0) return(integer(0))
  tilde_ids <- df$ID[grepl("^~", df$Name)]
  if (length(tilde_ids) == 0) return(integer(0))

  lowest <- integer(0)
  for (node_id in tilde_ids) {
    descendants <- get_descendants(df, node_id)
    if (length(descendants) == 0) {
      lowest <- c(lowest, node_id)
      next
    }
    desc_names <- df$Name[df$ID %in% descendants]
    if (!any(grepl("^~", desc_names))) {
      lowest <- c(lowest, node_id)
    }
  }

  unique(lowest)
}

clip_hierarchy_ids <- function(df) {
  if (nrow(df) == 0) return(integer(0))
  tilde_ids <- get_lowest_tilde_ids(df)
  if (length(tilde_ids) == 0) return(integer(0))

  to_delete <- integer(0)
  for (node_id in tilde_ids) {
    descendants <- get_descendants(df, node_id)
    if (length(descendants) == 0) next
    to_delete <- unique(c(to_delete, descendants))
  }

  to_delete
}

set_lowest_tilde_levels <- function(con, table_name, tilde_ids) {
  if (length(tilde_ids) == 0) return(0L)
  if (!DBI::dbExistsTable(con, table_name)) return(0L)
  if (!hierarchy_table_has_column(con, table_name, "Level")) return(0L)

  placeholders <- paste(rep("?", length(tilde_ids)), collapse = ", ")
  sql <- sprintf("UPDATE %s SET Level = 11 WHERE ID IN (%s)", table_name, placeholders)
  DBI::dbExecute(con, sql, as.list(tilde_ids))
  length(tilde_ids)
}

create_lowest_breakpoints_table <- function(con, source_table = "Hierarchy", target_table = "USysLowestBreakpoints_Hierarchy") {
  if (!DBI::dbExistsTable(con, source_table)) return(list(count = 0L, roots = 0L))

  fields <- DBI::dbListFields(con, source_table)
  select_cols <- intersect(c("ID", "Name", "Parent", "Level", "MyOrder"), fields)
  if (!all(c("ID", "Name", "Parent") %in% select_cols)) return(list(count = 0L, roots = 0L))

  sql <- sprintf("SELECT %s FROM %s", paste(select_cols, collapse = ", "), source_table)
  df <- DBI::dbGetQuery(con, sql)
  if (nrow(df) == 0) return(list(count = 0L, roots = 0L))

  lowest_ids <- get_lowest_tilde_ids(df)
  if (length(lowest_ids) == 0) {
    DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", target_table))
    DBI::dbExecute(con, sprintf("CREATE TABLE %s AS SELECT %s FROM %s WHERE 1=0", target_table, paste(select_cols, collapse = ", "), source_table))
    return(list(count = 0L, roots = 0L))
  }

  subtree_ids <- unique(unlist(lapply(lowest_ids, function(node_id) {
    c(node_id, get_descendants(df, node_id))
  })))
  subset <- df[df$ID %in% subtree_ids, , drop = FALSE]
  subset$Parent[subset$ID %in% lowest_ids] <- NA

  if ("Level" %in% select_cols) {
    level_map <- compute_subtree_levels(subset, parent_level = 0L)
    subset$Level <- as.integer(level_map[as.character(subset$ID)])
  }

  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", target_table))
  DBI::dbExecute(con, sprintf("CREATE TABLE %s AS SELECT %s FROM %s WHERE 1=0", target_table, paste(select_cols, collapse = ", "), source_table))
  DBI::dbWriteTable(con, target_table, subset, append = TRUE, row.names = FALSE)
  list(count = nrow(subset), roots = length(lowest_ids))
}

sync_env_to_su <- function(con) {
  if (!table_has_columns(con, "Env", c("PlotNumber", "UserSiteUnit"))) return(0L)
  if (!table_has_columns(con, "SU", c("PlotNumber", "SiteUnit"))) return(0L)

  sql <- paste(
    "UPDATE SU SET SiteUnit = e.UserSiteUnit",
    "FROM Env e",
    "WHERE SU.PlotNumber = e.PlotNumber"
  )
  DBI::dbExecute(con, sql)
}

sync_su_to_env <- function(con) {
  if (!table_has_columns(con, "Env", c("PlotNumber", "UserSiteUnit"))) return(0L)
  if (!table_has_columns(con, "SU", c("PlotNumber", "SiteUnit"))) return(0L)

  sql <- paste(
    "UPDATE Env SET UserSiteUnit = s.SiteUnit",
    "FROM SU s",
    "WHERE Env.PlotNumber = s.PlotNumber"
  )
  DBI::dbExecute(con, sql)
}

copy_bec_to_su <- function(con) {
  if (!table_has_columns(con, "Env", c("PlotNumber", "BECSiteUnit"))) return(0L)
  if (!table_has_columns(con, "SU", c("PlotNumber", "SiteUnit"))) return(0L)

  sql <- paste(
    "UPDATE SU SET SiteUnit = e.BECSiteUnit",
    "FROM Env e",
    "WHERE SU.PlotNumber = e.PlotNumber",
    "AND e.BECSiteUnit IS NOT NULL",
    "AND e.BECSiteUnit <> ''"
  )
  DBI::dbExecute(con, sql)
}

get_env_su_column <- function(con) {
  if (!DBI::dbExistsTable(con, "Env")) return(NULL)
  fields <- DBI::dbListFields(con, "Env")
  candidates <- c("UserSiteUnit", "AssignedSiteUnit", "SiteUnit", "BECSiteUnit")
  pick <- candidates[candidates %in% fields]
  if (length(pick) == 0) return(NULL)
  pick[1]
}

get_env_distinct_values <- function(con, column, zone = NULL) {
  if (!DBI::dbExistsTable(con, "Env")) return(character(0))
  if (!(column %in% DBI::dbListFields(con, "Env"))) return(character(0))

  where_clause <- ""
  params <- list()
  if (!is.null(zone) && nzchar(zone) && ("Zone" %in% DBI::dbListFields(con, "Env"))) {
    where_clause <- "WHERE Zone = ?"
    params <- list(zone)
  }

  sql <- sprintf("SELECT DISTINCT %s AS value FROM Env %s ORDER BY %s", column, where_clause, column)
  values <- DBI::dbGetQuery(con, sql, params)$value
  values[!is.na(values) & nzchar(trimws(values))]
}

get_env_filter_columns <- function(con) {
  if (!DBI::dbExistsTable(con, "Env")) return(character(0))
  fields <- DBI::dbListFields(con, "Env")
  candidates <- c("Zone", "SubZone", "SiteSeries", "UserSiteUnit", "BECSiteUnit", "PlotNumber")
  candidates[candidates %in% fields]
}

get_lists_master_table <- function(con) {
  candidates <- list(
    list(schema = "lists", table = "MasterSiteUnitList"),
    list(schema = "lists", table = "USysMasterSiteUnitList"),
    list(schema = "main", table = "MasterSiteUnitList"),
    list(schema = "main", table = "USysMasterSiteUnitList")
  )

  for (candidate in candidates) {
    if (DBI::dbExistsTable(con, DBI::Id(schema = candidate$schema, table = candidate$table))) {
      return(paste(candidate$schema, candidate$table, sep = "."))
    }
  }

  NULL
}

get_master_site_units <- function(con, level = NULL) {
  table_name <- get_lists_master_table(con)
  if (is.null(table_name)) return(data.frame())

  cols <- tryCatch({
    DBI::dbGetQuery(con, sprintf("PRAGMA table_info('%s')", table_name))$name
  }, error = function(e) {
    character(0)
  })
  select_cols <- intersect(c("SiteSeries", "SiteSeriesLongName", "Level"), cols)
  if (length(select_cols) == 0) return(data.frame())

  where_clause <- ""
  params <- list()
  if (!is.null(level) && nzchar(level) && ("Level" %in% select_cols)) {
    where_clause <- "WHERE Level = ?"
    params <- list(as.integer(level))
  }

  sql <- sprintf("SELECT %s FROM %s %s ORDER BY SiteSeries", paste(select_cols, collapse = ", "), table_name, where_clause)
  DBI::dbGetQuery(con, sql, params)
}

get_user_site_unit_table <- function(con) {
  candidates <- list(
    DBI::Id(schema = "user", table = "UserSiteUnitList"),
    DBI::Id(schema = "user", table = "USysUserSiteUnitList"),
    DBI::Id(catalog = "user_db", schema = "main", table = "UserSiteUnitList"),
    DBI::Id(catalog = "user_db", schema = "main", table = "USysUserSiteUnitList"),
    DBI::Id(schema = "main", table = "UserSiteUnitList"),
    DBI::Id(schema = "main", table = "USysUserSiteUnitList"),
    DBI::Id(table = "UserSiteUnitList"),
    DBI::Id(table = "USysUserSiteUnitList")
  )

  for (id in candidates) {
    if (isTRUE(DBI::dbExistsTable(con, id))) {
      return(list(
        id = id,
        ref = as.character(DBI::dbQuoteIdentifier(con, id))
      ))
    }
  }

  NULL
}

get_user_site_units <- function(con, level = NULL) {
  table_info <- get_user_site_unit_table(con)
  if (is.null(table_info)) return(data.frame())

  fields <- DBI::dbListFields(con, table_info$id)
  select_cols <- intersect(
    c("ID", "SiteSeries", "SiteSeriesLongName", "SiteSeriesScientificName", "Level"),
    fields
  )
  if (length(select_cols) == 0 || !("SiteSeries" %in% select_cols)) return(data.frame())

  where_clause <- ""
  params <- list()
  if (!is.null(level) && nzchar(level) && ("Level" %in% select_cols)) {
    where_clause <- "WHERE Level = ?"
    params <- list(as.integer(level))
  }

  sql <- sprintf("SELECT %s FROM %s %s ORDER BY SiteSeries", paste(select_cols, collapse = ", "), table_info$ref, where_clause)
  DBI::dbGetQuery(con, sql, params)
}

build_su_from_env <- function(con, zone = NULL, subzone = NULL, replace = TRUE) {
  if (!table_has_columns(con, "Env", c("PlotNumber"))) return(0L)
  if (!table_has_columns(con, "SU", c("PlotNumber", "SiteUnit"))) return(0L)

  su_col <- get_env_su_column(con)
  if (is.null(su_col)) return(0L)

  filters <- character(0)
  params <- list()
  if (!is.null(zone) && nzchar(zone) && ("Zone" %in% DBI::dbListFields(con, "Env"))) {
    filters <- c(filters, "e.Zone = ?")
    params <- c(params, list(zone))
  }
  if (!is.null(subzone) && nzchar(subzone) && ("SubZone" %in% DBI::dbListFields(con, "Env"))) {
    filters <- c(filters, "e.SubZone = ?")
    params <- c(params, list(subzone))
  }
  filters <- c(filters, "e.PlotNumber IS NOT NULL")
  where_clause <- if (length(filters) > 0) paste("WHERE", paste(filters, collapse = " AND ")) else ""

  if (replace) {
    DBI::dbExecute(con, "DELETE FROM SU")
    sql <- sprintf(
      "INSERT INTO SU (PlotNumber, SiteUnit) SELECT e.PlotNumber, e.%s FROM Env e %s",
      su_col,
      where_clause
    )
    return(DBI::dbExecute(con, sql, params))
  }

  sql <- sprintf(
    "INSERT INTO SU (PlotNumber, SiteUnit) SELECT e.PlotNumber, e.%s FROM Env e LEFT JOIN SU s ON e.PlotNumber = s.PlotNumber %s AND s.PlotNumber IS NULL",
    su_col,
    where_clause
  )
  DBI::dbExecute(con, sql, params)
}

build_su_from_env_filter <- function(con, column, value, replace = TRUE, carry_siteunit = FALSE) {
  if (!table_has_columns(con, "Env", c("PlotNumber"))) return(0L)
  if (!table_has_columns(con, "SU", c("PlotNumber", "SiteUnit"))) return(0L)
  if (is.null(column) || !nzchar(column)) return(0L)
  if (!(column %in% DBI::dbListFields(con, "Env"))) return(0L)

  su_col <- get_env_su_column(con)
  if (is.null(su_col)) return(0L)

  where_clause <- "WHERE e.PlotNumber IS NOT NULL"
  params <- list()
  if (!is.null(value) && nzchar(value)) {
    where_clause <- paste(where_clause, "AND", sprintf("e.%s = ?", column))
    params <- c(params, list(value))
  }

  if (replace) {
    DBI::dbExecute(con, "DELETE FROM SU")
  }

  sql <- sprintf(
    "INSERT INTO SU (PlotNumber, SiteUnit) SELECT e.PlotNumber, e.%s FROM Env e LEFT JOIN SU s ON e.PlotNumber = s.PlotNumber %s AND s.PlotNumber IS NULL",
    su_col,
    where_clause
  )
  count <- DBI::dbExecute(con, sql, params)

  if (!replace && isTRUE(carry_siteunit)) {
    sql_update <- paste(
      "UPDATE SU SET SiteUnit = s.SiteUnit",
      "FROM SU s",
      "WHERE SU.PlotNumber = s.PlotNumber"
    )
    DBI::dbExecute(con, sql_update)
  }

  count
}

get_plots_for_site_unit <- function(con, site_unit) {
  if (!DBI::dbExistsTable(con, "SU")) return(character(0))
  plots <- DBI::dbGetQuery(
    con,
    "SELECT PlotNumber FROM SU WHERE SiteUnit = ?",
    list(site_unit)
  )
  if (nrow(plots) == 0) return(character(0))
  plots$PlotNumber
}

filter_duplicate_names <- function(source_df, existing_names) {
  if (nrow(source_df) == 0) return(list(data = source_df, dropped = 0L))
  if (length(existing_names) == 0) return(list(data = source_df, dropped = 0L))

  dupes <- source_df$Name %in% existing_names
  if (!any(dupes)) return(list(data = source_df, dropped = 0L))
  list(data = source_df[!dupes, , drop = FALSE], dropped = sum(dupes))
}

filter_duplicate_subtrees <- function(source_df, existing_names) {
  if (nrow(source_df) == 0) return(list(data = source_df, dropped = 0L))
  if (length(existing_names) == 0) return(list(data = source_df, dropped = 0L))

  dup_ids <- source_df$ID[source_df$Name %in% existing_names]
  if (length(dup_ids) == 0) return(list(data = source_df, dropped = 0L))

  to_drop <- unique(unlist(lapply(dup_ids, function(id) c(id, get_descendants(source_df, id)))))
  list(data = source_df[!source_df$ID %in% to_drop, , drop = FALSE], dropped = length(to_drop))
}

resolve_duplicate_names <- function(source_df, existing_names, mode = c("skip", "prefix", "suffix"), prefix = "", suffix = "") {
  if (nrow(source_df) == 0) return(list(data = source_df, dropped = 0L, renamed = 0L))
  if (length(existing_names) == 0) return(list(data = source_df, dropped = 0L, renamed = 0L))

  mode <- match.arg(mode)
  if (mode == "skip") {
    filtered <- filter_duplicate_names(source_df, existing_names)
    return(list(data = filtered$data, dropped = filtered$dropped, renamed = 0L))
  }

  updated <- source_df
  dupes <- updated$Name %in% existing_names
  if (!any(dupes)) return(list(data = updated, dropped = 0L, renamed = 0L))

  renamed_count <- 0L
  for (idx in which(dupes)) {
    base_name <- updated$Name[idx]
    proposed <- if (mode == "prefix") paste0(prefix, base_name) else paste0(base_name, suffix)
    candidate <- proposed
    counter <- 1L
    while (candidate %in% c(existing_names, updated$Name[-idx])) {
      candidate <- paste0(proposed, " ", counter)
      counter <- counter + 1L
    }
    updated$Name[idx] <- candidate
    renamed_count <- renamed_count + 1L
  }

  list(data = updated, dropped = 0L, renamed = renamed_count)
}

compute_subtree_levels <- function(df, parent_level = -1L) {
  if (nrow(df) == 0) return(integer(0))

  level_map <- setNames(rep(NA_integer_, nrow(df)), df$ID)
  roots <- df$ID[is.na(df$Parent)]

  assign_levels <- function(node_id, level_val) {
    level_map[[as.character(node_id)]] <<- level_val
    children <- df$ID[!is.na(df$Parent) & df$Parent == node_id]
    if (length(children) == 0) return()
    for (child in children) {
      assign_levels(child, level_val + 1L)
    }
  }

  for (root_id in roots) {
    assign_levels(root_id, parent_level + 1L)
  }

  level_map
}

insert_subtree <- function(con, subtree, new_parent, parent_level = -1L) {
  if (nrow(subtree) == 0) return(0)

  use_level <- hierarchy_has_column(con, "Level")
  use_order <- hierarchy_has_column(con, "MyOrder")
  use_tag <- hierarchy_has_column(con, "Tag")
  level_map <- if (use_level) compute_subtree_levels(subtree, parent_level) else NULL

  max_id <- DBI::dbGetQuery(con, "SELECT MAX(ID) AS max_id FROM Hierarchy")
  next_id <- if (is.na(max_id$max_id[1])) 1L else as.integer(max_id$max_id[1]) + 1L

  old_ids <- subtree$ID
  new_ids <- seq.int(next_id, length.out = length(old_ids))
  id_map <- setNames(new_ids, old_ids)

  order_ids <- unique(c(subtree$ID[is.na(subtree$Parent)], subtree$ID[!is.na(subtree$Parent)]))
  count <- 0

  root_counter <- 0L
  child_counters <- new.env(parent = emptyenv())
  root_base <- 0
  if (use_order) {
    root_sql <- "SELECT MAX(MyOrder) AS max_order FROM Hierarchy WHERE Parent IS NULL"
    root_params <- list()
    if (!is.na(new_parent)) {
      root_sql <- "SELECT MAX(MyOrder) AS max_order FROM Hierarchy WHERE Parent = ?"
      root_params <- list(new_parent)
    }
    root_max <- DBI::dbGetQuery(con, root_sql, root_params)
    root_base <- suppressWarnings(as.numeric(root_max$max_order[1]))
    if (is.na(root_base) || !is.finite(root_base)) root_base <- 0
  }

  for (old_id in order_ids) {
    row <- subtree[subtree$ID == old_id, , drop = FALSE][1, ]
    parent_old <- row$Parent

    if (is.na(parent_old)) {
      parent_new <- new_parent
    } else {
      parent_new <- id_map[[as.character(parent_old)]]
    }

    order_val <- NULL
    if (use_order) {
      if ("MyOrder" %in% names(subtree) && !is.na(row$MyOrder)) {
        order_val <- suppressWarnings(as.numeric(row$MyOrder))
      } else if (is.na(parent_old)) {
        root_counter <- root_counter + 1L
        order_val <- root_base + root_counter
      } else {
        parent_key <- as.character(parent_new)
        if (is.null(child_counters[[parent_key]])) child_counters[[parent_key]] <- 0L
        child_counters[[parent_key]] <- child_counters[[parent_key]] + 1L
        order_val <- child_counters[[parent_key]]
      }
    }

    columns <- c("ID", "Name", "Parent")
    values <- list(id_map[[as.character(old_id)]], row$Name, parent_new)
    if (use_level) {
      columns <- c(columns, "Level")
      values <- c(values, list(level_map[[as.character(old_id)]]))
    }
    if (use_order) {
      columns <- c(columns, "MyOrder")
      values <- c(values, list(order_val))
    }
    if (use_tag) {
      tag_val <- if ("Tag" %in% names(subtree)) row$Tag else NA
      columns <- c(columns, "Tag")
      values <- c(values, list(tag_val))
    }
    placeholders <- paste(rep("?", length(columns)), collapse = ", ")
    sql <- sprintf("INSERT INTO Hierarchy (%s) VALUES (%s)", paste(columns, collapse = ", "), placeholders)
    DBI::dbExecute(con, sql, values)
    count <- count + 1
  }

  count
}

insert_rekeyed_hierarchy <- function(con, source_df, parent_level = -1L) {
  if (nrow(source_df) == 0) return(list(count = 0L, missing_parents = 0L))

  use_level <- hierarchy_has_column(con, "Level")
  use_order <- hierarchy_has_column(con, "MyOrder")
  use_tag <- hierarchy_has_column(con, "Tag")

  temp_df <- source_df
  if (!is.null(temp_df$Parent)) {
    missing <- !is.na(temp_df$Parent) & !(temp_df$Parent %in% temp_df$ID)
    temp_df$Parent[missing] <- NA
  }
  level_map <- if (use_level) compute_subtree_levels(temp_df, parent_level) else NULL

  max_id <- DBI::dbGetQuery(con, "SELECT MAX(ID) AS max_id FROM Hierarchy")
  next_id <- if (is.na(max_id$max_id[1])) 1L else as.integer(max_id$max_id[1]) + 1L

  old_ids <- temp_df$ID
  new_ids <- seq.int(next_id, length.out = length(old_ids))
  id_map <- setNames(new_ids, old_ids)

  order_ids <- unique(c(temp_df$ID[is.na(temp_df$Parent)], temp_df$ID[!is.na(temp_df$Parent)]))
  count <- 0L
  missing_parents <- 0L

  root_counter <- 0L
  child_counters <- new.env(parent = emptyenv())
  root_base <- 0
  if (use_order) {
    root_max <- DBI::dbGetQuery(con, "SELECT MAX(MyOrder) AS max_order FROM Hierarchy WHERE Parent IS NULL")
    root_base <- suppressWarnings(as.numeric(root_max$max_order[1]))
    if (is.na(root_base) || !is.finite(root_base)) root_base <- 0
  }

  for (old_id in order_ids) {
    row <- temp_df[temp_df$ID == old_id, , drop = FALSE][1, ]
    parent_old <- row$Parent
    parent_new <- NA_integer_

    if (!is.na(parent_old)) {
      mapped <- id_map[[as.character(parent_old)]]
      if (!is.null(mapped)) {
        parent_new <- mapped
      } else {
        missing_parents <- missing_parents + 1L
      }
    }

    order_val <- NULL
    if (use_order) {
      if ("MyOrder" %in% names(temp_df) && !is.na(row$MyOrder)) {
        order_val <- suppressWarnings(as.numeric(row$MyOrder))
      } else if (is.na(parent_old)) {
        root_counter <- root_counter + 1L
        order_val <- root_base + root_counter
      } else {
        parent_key <- as.character(parent_new)
        if (is.null(child_counters[[parent_key]])) child_counters[[parent_key]] <- 0L
        child_counters[[parent_key]] <- child_counters[[parent_key]] + 1L
        order_val <- child_counters[[parent_key]]
      }
    }

    columns <- c("ID", "Name", "Parent")
    values <- list(id_map[[as.character(old_id)]], row$Name, parent_new)
    if (use_level) {
      columns <- c(columns, "Level")
      values <- c(values, list(level_map[[as.character(old_id)]]))
    }
    if (use_order) {
      columns <- c(columns, "MyOrder")
      values <- c(values, list(order_val))
    }
    if (use_tag) {
      tag_val <- if ("Tag" %in% names(temp_df)) row$Tag else NA
      columns <- c(columns, "Tag")
      values <- c(values, list(tag_val))
    }
    placeholders <- paste(rep("?", length(columns)), collapse = ", ")
    sql <- sprintf("INSERT INTO Hierarchy (%s) VALUES (%s)", paste(columns, collapse = ", "), placeholders)
    DBI::dbExecute(con, sql, values)
    count <- count + 1L
  }

  list(count = count, missing_parents = missing_parents)
}

mod_hierarchy_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Hierarchy"),
      navset_card_tab(
        id = ns("hier_tabs"),
        nav_panel("Hierarchy",
          layout_columns(
            actionButton(ns("hier_view_user_list"), "View User List", class = "btn-outline-secondary"),
            actionButton(ns("hier_view_plot_data"), "View Plot Data", class = "btn-outline-secondary"),
            actionButton(ns("hier_view_su_table"), "View SU Table", class = "btn-outline-secondary"),
            actionButton(ns("hier_load_hierarchy_plots"), "Load Hierarchy + Plots", class = "btn-outline-secondary"),
            actionButton(ns("hier_load_su_plots"), "Load SUs + Plots", class = "btn-outline-secondary"),
            col_widths = c(2, 2, 2, 3, 3)
          ),
          layout_columns(
            actionButton(ns("hier_view_veg"), "View Vegetation", class = "btn-outline-secondary"),
            actionButton(ns("hier_view_current_su"), "View Current SU", class = "btn-outline-secondary"),
            col_widths = c(2, 2)
          ),
          layout_columns(
            textInput(ns("hier_name"), "Name"),
            textInput(ns("hier_tag"), "Tag"),
            actionButton(ns("hier_add"), "Add Node", class = "btn-primary"),
            actionButton(ns("hier_rename"), "Rename", class = "btn-warning"),
            actionButton(ns("hier_update_tag"), "Update Tag", class = "btn-outline-secondary"),
            actionButton(ns("hier_delete"), "Delete", class = "btn-danger"),
            actionButton(ns("hier_delete_subtree"), "Delete Subtree", class = "btn-danger"),
            actionButton(ns("hier_refresh"), "Refresh", class = "btn-secondary"),
            actionButton(ns("hier_fix_orphans"), "Reattach Orphans", class = "btn-outline-secondary"),
            actionButton(ns("hier_clip"), "Clip Hierarchy", class = "btn-outline-secondary"),
            actionButton(ns("hier_below_breaks"), "Below Breaks", class = "btn-outline-secondary"),
            actionButton(ns("hier_show_original"), "Show Original", class = "btn-outline-secondary"),
            col_widths = c(2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2)
          ),
          tags$small(textOutput(ns("hier_clip_status"))),
          layout_columns(
            selectInput(ns("move_parent"), "Move Node To", choices = NULL),
            actionButton(ns("hier_move"), "Move Node", class = "btn-outline-secondary"),
            actionButton(ns("hier_move_up"), "Move Up", class = "btn-outline-secondary"),
            actionButton(ns("hier_move_down"), "Move Down", class = "btn-outline-secondary"),
            col_widths = c(6, 2, 2, 2)
          ),
          layout_columns(
            actionButton(ns("hier_copy"), "Copy Subtree", class = "btn-outline-secondary"),
            actionButton(ns("hier_paste"), "Paste Subtree", class = "btn-outline-secondary"),
            textInput(ns("merge_table"), "Merge Table", placeholder = "OtherProject_Hierarchy"),
            checkboxInput(ns("merge_allow_dupes"), "Allow duplicate names", value = FALSE),
            actionButton(ns("hier_merge"), "Merge", class = "btn-outline-secondary"),
            col_widths = c(2, 2, 4, 2, 2)
          ),
          layout_columns(
            selectInput(ns("merge_conflict_mode"), "Conflict handling", choices = c("skip", "prefix", "suffix"), selected = "skip"),
            textInput(ns("merge_conflict_text"), "Prefix/Suffix", placeholder = "Merged - "),
            col_widths = c(3, 7)
          ),
          layout_columns(
            textInput(ns("hier_find"), "Find Node", placeholder = "Enter name"),
            actionButton(ns("hier_find_btn"), "Find", class = "btn-outline-secondary"),
            actionButton(ns("hier_find_prev"), "Prev", class = "btn-outline-secondary"),
            actionButton(ns("hier_find_next"), "Next", class = "btn-outline-secondary"),
            col_widths = c(6, 2, 2, 2)
          ),
          tags$script(HTML(sprintf("(function(){\n  var inputId = '%s';\n  var enterId = '%s';\n  var nextId = '%s';\n  var prevId = '%s';\n  function bind(){\n    var el = document.getElementById(inputId);\n    if (!el) return;\n    el.addEventListener('keydown', function(e){\n      if (e.key === 'Enter' && e.shiftKey){\n        e.preventDefault();\n        Shiny.setInputValue(prevId, Date.now());\n        return;\n      }\n      if (e.key === 'Enter'){\n        e.preventDefault();\n        Shiny.setInputValue(enterId, Date.now());\n      }\n    });\n  }\n  if (document.readyState === 'loading') {\n    document.addEventListener('DOMContentLoaded', bind);\n  } else {\n    bind();\n  }\n})();", ns("hier_find"), ns("hier_find_enter"), ns("hier_find_next_key"), ns("hier_find_prev_key")))),
          verbatimTextOutput(ns("merge_preview")),
            div(style = "height:600px; overflow:auto;",
              shinyTree::shinyTree(ns("hier_tree"))
            ),
          verbatimTextOutput(ns("hier_status"))
        ),
        nav_panel("SU Table",
          layout_columns(
            actionButton(ns("su_add"), "Add Row", class = "btn-primary"),
            actionButton(ns("su_delete"), "Delete Selected", class = "btn-danger"),
            actionButton(ns("su_refresh"), "Refresh", class = "btn-secondary"),
            actionButton(ns("su_show_units"), "Show Units", class = "btn-outline-secondary"),
            actionButton(ns("su_show_plots"), "Show Plots", class = "btn-outline-secondary"),
            actionButton(ns("su_show_master"), "Show Master List", class = "btn-outline-secondary"),
            actionButton(ns("su_show_user"), "Show User List", class = "btn-outline-secondary"),
            col_widths = c(2, 2, 2, 2, 2, 2, 2)
          ),
          layout_columns(
            actionButton(ns("su_env_to_su"), "Env -> SU", class = "btn-outline-secondary"),
            actionButton(ns("su_su_to_env"), "SU -> Env", class = "btn-outline-secondary"),
            actionButton(ns("su_bec_to_su"), "BEC -> SU", class = "btn-outline-secondary"),
            col_widths = c(2, 2, 2)
          ),
          layout_columns(
            selectInput(ns("su_filter_zone"), "Zone", choices = c("All" = "")),
            selectInput(ns("su_filter_subzone"), "SubZone", choices = c("All" = "")),
            checkboxInput(ns("su_replace"), "Replace existing", value = TRUE),
            actionButton(ns("su_build_from_env"), "Build SU from Env", class = "btn-outline-secondary"),
            col_widths = c(3, 3, 2, 4)
          ),
          layout_columns(
            selectInput(ns("su_filter_column"), "Filter column", choices = c("Select" = "")),
            selectInput(ns("su_filter_value"), "Filter value", choices = c("All" = "")),
            checkboxInput(ns("su_carry_siteunit"), "Carry existing SiteUnit", value = FALSE),
            actionButton(ns("su_build_from_filter"), "Build SU from Filter", class = "btn-outline-secondary"),
            col_widths = c(3, 3, 3, 3)
          ),
          layout_columns(
            selectInput(ns("su_master_level"), "Master level", choices = c("All" = "")),
            col_widths = c(3)
          ),
          rhandsontable::rHandsontableOutput(ns("su_hot")),
          verbatimTextOutput(ns("su_status"))
        )
      )
    )
  )
}

mod_hierarchy_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()

    rv <- reactiveValues(
      data = NULL,
      clipboard = NULL,
      su = NULL,
      su_status = "",
      selected_path = NULL,
      selected_id = NA_integer_,
      orphan_count = 0L,
      su_mode = "plots",
      use_clipped = FALSE,
      clip_deleted = 0L,
      clip_lowest = 0L,
      clip_total = 0L,
      clip_mode = "original",
      find_matches = integer(0),
      find_index = 0L,
      find_query = ""
    )

    require_hierarchy_write <- function() {
      if (!auth_is_authenticated(state)) {
        show_toast(toast("Sign in required.", type = "danger"))
        return(FALSE)
      }
      allowed <- c("write:project_plots", "write:all", "manage:codes")
      if (!any(vapply(allowed, function(p) auth_user_has_permission(state, p), logical(1)))) {
        show_toast(toast("Permission required: edit hierarchy", type = "danger"))
        return(FALSE)
      }
      TRUE
    }

    require_su_write <- function() {
      if (!auth_is_authenticated(state)) {
        show_toast(toast("Sign in required.", type = "danger"))
        return(FALSE)
      }
      allowed <- c("write:project_plots", "write:all", "manage:codes")
      if (!any(vapply(allowed, function(p) auth_user_has_permission(state, p), logical(1)))) {
        show_toast(toast("Permission required: edit site units", type = "danger"))
        return(FALSE)
      }
      TRUE
    }

    normalize_text <- function(value) {
      val <- as.character(value)
      val[is.na(val)] <- ""
      trimws(val)
    }

    log_su_audit_changes <- function(before_df, after_df) {
      if (is.null(before_df)) before_df <- data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
      if (is.null(after_df)) after_df <- data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)

      if (!all(c("PlotNumber", "SiteUnit") %in% names(before_df)) || !all(c("PlotNumber", "SiteUnit") %in% names(after_df))) {
        return(0L)
      }

      before_df <- before_df[, c("PlotNumber", "SiteUnit"), drop = FALSE]
      after_df <- after_df[, c("PlotNumber", "SiteUnit"), drop = FALSE]
      before_df$PlotNumber <- normalize_text(before_df$PlotNumber)
      before_df$SiteUnit <- normalize_text(before_df$SiteUnit)
      after_df$PlotNumber <- normalize_text(after_df$PlotNumber)
      after_df$SiteUnit <- normalize_text(after_df$SiteUnit)

      before_map <- setNames(before_df$SiteUnit, before_df$PlotNumber)
      after_map <- setNames(after_df$SiteUnit, after_df$PlotNumber)
      all_plots <- union(names(before_map), names(after_map))

      logged <- 0L
      for (plot_id in all_plots) {
        if (!nzchar(plot_id)) next
        old_val <- before_map[[plot_id]]
        new_val <- after_map[[plot_id]]
        if (identical(old_val, new_val)) next
        if (!nzchar(old_val)) old_val <- NA
        if (!nzchar(new_val)) new_val <- NA

        project_id <- resolve_project_id_for_plot(con, plot_id, state$CurrProject)
        if (isTRUE(log_audit_change(con, project_id, state$User, plot_id, "SU", "SiteUnit", old_val, new_val))) {
          logged <- logged + 1L
        }
      }

      logged
    }

    log_env_siteunit_changes <- function(before_df, after_df, field_name = "UserSiteUnit") {
      if (is.null(before_df)) return(0L)
      if (is.null(after_df)) return(0L)
      if (!(field_name %in% names(before_df)) || !(field_name %in% names(after_df))) return(0L)
      if (!("PlotNumber" %in% names(before_df)) || !("PlotNumber" %in% names(after_df))) return(0L)

      before_df$PlotNumber <- normalize_text(before_df$PlotNumber)
      after_df$PlotNumber <- normalize_text(after_df$PlotNumber)
      before_vals <- normalize_text(before_df[[field_name]])
      after_vals <- normalize_text(after_df[[field_name]])

      before_map <- setNames(before_vals, before_df$PlotNumber)
      after_map <- setNames(after_vals, after_df$PlotNumber)
      all_plots <- union(names(before_map), names(after_map))

      logged <- 0L
      for (plot_id in all_plots) {
        if (!nzchar(plot_id)) next
        old_val <- before_map[[plot_id]]
        new_val <- after_map[[plot_id]]
        if (identical(old_val, new_val)) next
        if (!nzchar(old_val)) old_val <- NA
        if (!nzchar(new_val)) new_val <- NA

        project_id <- NA_character_
        if ("ProjectID" %in% names(after_df)) {
          project_id <- after_df$ProjectID[after_df$PlotNumber == plot_id][1]
        }
        if ((is.na(project_id) || !nzchar(as.character(project_id))) && "ProjectID" %in% names(before_df)) {
          project_id <- before_df$ProjectID[before_df$PlotNumber == plot_id][1]
        }
        if (is.na(project_id) || !nzchar(as.character(project_id))) {
          project_id <- resolve_project_id_for_plot(con, plot_id, state$CurrProject)
        }

        if (isTRUE(log_audit_change(con, project_id, state$User, plot_id, "Env", field_name, old_val, new_val))) {
          logged <- logged + 1L
        }
      }

      logged
    }

    load_hierarchy <- function() {
      table_name <- if (isTRUE(rv$use_clipped) && DBI::dbExistsTable(con, "USysLowestBreakpoints_Hierarchy")) {
        "USysLowestBreakpoints_Hierarchy"
      } else {
        "Hierarchy"
      }

      if (!DBI::dbExistsTable(con, table_name)) return(data.frame())
      fields <- DBI::dbListFields(con, table_name)
      select_cols <- intersect(c("ID", "Name", "Parent", "Level", "Tag", "MyOrder"), fields)
      if (length(select_cols) == 0) return(data.frame())
      order_clause <- if ("MyOrder" %in% select_cols) {
        "ORDER BY Parent NULLS FIRST, MyOrder NULLS LAST, Name"
      } else {
        "ORDER BY Name"
      }
      sql <- sprintf("SELECT %s FROM %s %s", paste(select_cols, collapse = ", "), table_name, order_clause)
      DBI::dbGetQuery(con, sql)
    }

    load_su <- function(mode = rv$su_mode, site_units = NULL, master_level = NULL) {
      if (!DBI::dbExistsTable(con, "SU")) {
        return(data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE))
      }
      if (identical(mode, "units")) {
        units <- DBI::dbGetQuery(con, "SELECT DISTINCT SiteUnit FROM SU ORDER BY SiteUnit")
        data.frame(
          PlotNumber = rep("", nrow(units)),
          SiteUnit = units$SiteUnit,
          stringsAsFactors = FALSE
        )
      } else if (identical(mode, "user")) {
        level_val <- master_level
        if (is.null(level_val) && !is.null(input$su_master_level)) {
          level_val <- input$su_master_level
        }
        user_units <- get_user_site_units(con, level = level_val)
        if (nrow(user_units) == 0) return(data.frame())
        user_units
      } else if (identical(mode, "master")) {
        level_val <- master_level
        if (is.null(level_val) && !is.null(input$su_master_level)) {
          level_val <- input$su_master_level
        }
        master <- get_master_site_units(con, level = level_val)
        if (nrow(master) == 0) return(data.frame())
        master
      } else {
        if (!is.null(site_units) && length(site_units) > 0) {
          placeholders <- paste(rep("?", length(site_units)), collapse = ", ")
          sql <- sprintf("SELECT PlotNumber, SiteUnit FROM SU WHERE SiteUnit IN (%s) ORDER BY PlotNumber", placeholders)
          DBI::dbGetQuery(con, sql, as.list(site_units))
        } else {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU ORDER BY PlotNumber")
        }
      }
    }

    refresh_tree <- function() {
      rv$data <- load_hierarchy()
      if (!is.null(rv$data) && nrow(rv$data) > 0) {
        rv$orphan_count <- length(find_orphan_nodes(rv$data))
      } else {
        rv$orphan_count <- 0L
      }
    }

    update_move_choices <- function() {
      if (is.null(rv$data) || nrow(rv$data) == 0) {
        updateSelectInput(session, "move_parent", choices = c("Root" = ""))
        return()
      }

      labels <- paste0(rv$data$Name, " [", rv$data$ID, "]")
      choices <- setNames(as.character(rv$data$ID), labels)
      choices <- c("Root" = "", choices)
      updateSelectInput(session, "move_parent", choices = choices)
    }

    observeEvent(state$CurrProject, {
      refresh_tree()
      update_move_choices()
      rv$su <- load_su()
    }, ignoreInit = TRUE)

    update_su_filters <- function(zone = NULL) {
      zones <- get_env_distinct_values(con, "Zone")
      zone_choices <- c("All" = "", stats::setNames(zones, zones))
      updateSelectInput(session, "su_filter_zone", choices = zone_choices)

      subzones <- get_env_distinct_values(con, "SubZone", zone = zone)
      subzone_choices <- c("All" = "", stats::setNames(subzones, subzones))
      updateSelectInput(session, "su_filter_subzone", choices = subzone_choices)

      columns <- get_env_filter_columns(con)
      column_choices <- c("Select" = "", stats::setNames(columns, columns))
      updateSelectInput(session, "su_filter_column", choices = column_choices)

      updateSelectInput(session, "su_filter_value", choices = c("All" = ""))

      master_levels <- get_master_site_units(con)
      if (nrow(master_levels) > 0 && "Level" %in% names(master_levels)) {
        levels <- sort(unique(master_levels$Level))
        level_choices <- c("All" = "", stats::setNames(as.character(levels), as.character(levels)))
        updateSelectInput(session, "su_master_level", choices = level_choices)
      }
    }

    observeEvent(state$CurrProject, {
      update_su_filters()
    }, ignoreInit = TRUE)

    observeEvent(input$su_filter_zone, {
      zone_val <- trimws(input$su_filter_zone)
      update_su_filters(zone = zone_val)
    }, ignoreInit = TRUE)

    observeEvent(input$su_filter_column, {
      column_val <- trimws(input$su_filter_column)
      values <- if (nzchar(column_val)) get_env_distinct_values(con, column_val) else character(0)
      value_choices <- c("All" = "", stats::setNames(values, values))
      updateSelectInput(session, "su_filter_value", choices = value_choices)
    }, ignoreInit = TRUE)

    observeEvent(input$hier_refresh, {
      refresh_tree()
      update_move_choices()
    })

    observeEvent(input$su_refresh, {
      rv$su <- load_su()
    })

    output$hier_tree <- shinyTree::renderTree({
      req(rv$data)
      open_ids <- if (!is.na(rv$selected_id)) get_node_path_ids(rv$data, rv$selected_id) else integer(0)
      build_hierarchy_tree(rv$data, selected_id = rv$selected_id, open_ids = open_ids)
    })

    output$hier_status <- renderText({
      if (is.null(state$CurrProject)) {
        "Select a project to begin."
      } else if (is.null(rv$data)) {
        "No hierarchy loaded."
      } else {
        path_text <- if (!is.null(rv$selected_path) && length(rv$selected_path) > 0) {
          paste(rv$selected_path, collapse = " > ")
        } else {
          ""
        }
        status_parts <- c(paste("Nodes:", nrow(rv$data)))
        if (rv$orphan_count > 0) {
          status_parts <- c(status_parts, paste("Orphans:", rv$orphan_count))
        }
        if (isTRUE(rv$use_clipped)) {
          if (identical(rv$clip_mode, "clipped")) {
            status_parts <- c(status_parts, paste("Clipped removed:", rv$clip_deleted))
            if (rv$clip_lowest > 0) {
              status_parts <- c(status_parts, paste("Lowest tildes:", rv$clip_lowest))
            }
          } else if (identical(rv$clip_mode, "below_breaks")) {
            status_parts <- c(status_parts, paste("Below breaks:", rv$clip_total))
            if (rv$clip_lowest > 0) {
              status_parts <- c(status_parts, paste("Lowest tildes:", rv$clip_lowest))
            }
          }
        }
        if (nzchar(path_text)) {
          status_parts <- c(status_parts, paste("Selected:", path_text))
        }
        paste(status_parts, collapse = " | ")
      }
    })

    output$hier_clip_status <- renderText({
      if (!isTRUE(rv$use_clipped)) {
        "Hierarchy view: original"
      } else if (identical(rv$clip_mode, "below_breaks")) {
        status <- paste("Hierarchy view: below breaks", "| nodes", rv$clip_total)
        if (rv$clip_lowest > 0) {
          status <- paste(status, "| lowest tildes", rv$clip_lowest)
        }
        status
      } else {
        status <- paste("Hierarchy view: clipped", "| removed", rv$clip_deleted)
        if (rv$clip_lowest > 0) {
          status <- paste(status, "| lowest tildes", rv$clip_lowest)
        }
        status
      }
    })

    output$merge_preview <- renderText({
      table <- trimws(input$merge_table)
      if (!nzchar(table)) return("")
      if (!DBI::dbExistsTable(con, table)) return("Merge preview: table not found.")

      merge_fields <- DBI::dbListFields(con, table)
      if (!("Name" %in% merge_fields)) return("Merge preview: missing Name column.")

      source <- DBI::dbGetQuery(con, sprintf("SELECT Name FROM %s", table))
      if (nrow(source) == 0) return("Merge preview: no rows.")

      existing <- DBI::dbGetQuery(con, "SELECT Name FROM Hierarchy")
      existing_names <- unique(existing$Name)

      dupes <- sum(source$Name %in% existing_names)
      total <- nrow(source)
      dup_names <- unique(source$Name[source$Name %in% existing_names])
      dup_preview <- if (length(dup_names) > 0) paste(utils::head(dup_names, 5), collapse = ", ") else ""
      message <- paste("Merge preview:", total, "rows;", dupes, "duplicates;", total - dupes, "new")
      if (nzchar(dup_preview)) message <- paste(message, "| dupes:", dup_preview)
      if (isTRUE(input$merge_allow_dupes) && dupes > 0) {
        message <- paste(message, "| allowing duplicates")
      } else if (dupes > 0) {
        mode_label <- if (identical(input$merge_conflict_mode, "skip")) "skip subtrees" else input$merge_conflict_mode
        message <- paste(message, "| handling:", mode_label)
      }
      message
    })

    output$su_hot <- rhandsontable::renderRHandsontable({
      req(rv$su)
      read_only <- identical(rv$su_mode, "units") || identical(rv$su_mode, "master") || identical(rv$su_mode, "user")
      rhandsontable::rhandsontable(rv$su, rowHeaders = FALSE, stretchH = "all", readOnly = read_only)
    })

    output$su_status <- renderText({
      mode_label <- if (identical(rv$su_mode, "units")) {
        "Site units"
      } else if (identical(rv$su_mode, "user")) {
        "User site units"
      } else if (identical(rv$su_mode, "master")) {
        "Master site units"
      } else {
        "Plots"
      }
      if (nzchar(rv$su_status)) {
        paste(mode_label, "|", rv$su_status)
      } else {
        mode_label
      }
    })

    get_hot_selected_row <- function(selection) {
      if (is.null(selection)) return(NULL)
      if (is.list(selection) && !is.null(selection$r)) return(selection$r)
      if (is.list(selection) && !is.null(selection$select) && !is.null(selection$select$r)) return(selection$select$r)
      if (is.matrix(selection) && ncol(selection) >= 1) return(selection[1, 1])
      NULL
    }

    observeEvent(input$hier_add, {
      if (!require_hierarchy_write()) return()
      name_val <- trimws(input$hier_name)
      req(nzchar(name_val))
      tag_val <- trimws(input$hier_tag)
      if (!nzchar(tag_val)) tag_val <- NA
      refresh_tree()

      if (!is.null(rv$data) && name_val %in% rv$data$Name) {
        show_toast(toast("Name already exists.", type = "warning"))
        return()
      }

      selected <- shinyTree::get_selected(input$hier_tree)
      parent_id <- parse_hierarchy_id(selected)
      if (is.na(parent_id)) parent_id <- NA_integer_

      max_id <- DBI::dbGetQuery(con, "SELECT MAX(ID) AS max_id FROM Hierarchy")
      new_id <- if (is.na(max_id$max_id[1])) 1L else as.integer(max_id$max_id[1]) + 1L

      tryCatch({
        has_level <- hierarchy_has_column(con, "Level")
        has_order <- hierarchy_has_column(con, "MyOrder")
        has_tag <- hierarchy_has_column(con, "Tag")
        level_val <- 0L
        if (has_level && !is.null(rv$data) && "Level" %in% names(rv$data) && !is.na(parent_id)) {
          parent_level <- rv$data$Level[rv$data$ID == parent_id][1]
          if (!is.na(parent_level)) level_val <- as.integer(parent_level) + 1L
        }
        order_val <- NULL
        if (has_order && !is.null(rv$data)) {
          siblings <- get_sibling_order(rv$data, parent_id)
          if (nrow(siblings) == 0 || all(is.na(suppressWarnings(as.numeric(siblings$MyOrder))))) {
            order_val <- 1
          } else {
            max_order <- suppressWarnings(max(as.numeric(siblings$MyOrder), na.rm = TRUE))
            order_val <- if (is.finite(max_order)) max_order + 1 else 1
          }
        }

        columns <- c("ID", "Name", "Parent")
        values <- list(new_id, name_val, parent_id)
        if (has_level) {
          columns <- c(columns, "Level")
          values <- c(values, list(level_val))
        }
        if (has_order) {
          columns <- c(columns, "MyOrder")
          values <- c(values, list(order_val))
        }
        if (has_tag) {
          columns <- c(columns, "Tag")
          values <- c(values, list(tag_val))
        }
        placeholders <- paste(rep("?", length(columns)), collapse = ", ")
        sql <- sprintf("INSERT INTO Hierarchy (%s) VALUES (%s)", paste(columns, collapse = ", "), placeholders)
        DBI::dbExecute(con, sql, values)
        show_toast(toast("Node added.", type = "success"))
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Add failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_rename, {
      if (!require_hierarchy_write()) return()
      name_val <- trimws(input$hier_name)
      req(nzchar(name_val))
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      if (!is.null(rv$data)) {
        existing <- rv$data$Name[rv$data$ID != node_id]
        if (name_val %in% existing) {
          show_toast(toast("Name already exists.", type = "warning"))
          return()
        }
      }

      tryCatch({
        DBI::dbExecute(
          con,
          "UPDATE Hierarchy SET Name = ? WHERE ID = ?",
          list(name_val, node_id)
        )
        show_toast(toast("Node renamed.", type = "success"))
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Rename failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_update_tag, {
      if (!require_hierarchy_write()) return()
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      if (!hierarchy_has_column(con, "Tag")) {
        show_toast(toast("Tag column not available for this hierarchy.", type = "warning"))
        return()
      }

      tag_val <- trimws(input$hier_tag)
      if (!nzchar(tag_val)) tag_val <- NA

      tryCatch({
        DBI::dbExecute(
          con,
          "UPDATE Hierarchy SET Tag = ? WHERE ID = ?",
          list(tag_val, node_id)
        )
        show_toast(toast("Tag updated.", type = "success"))
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Tag update failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_delete, {
      if (!require_hierarchy_write()) return()
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      child_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS cnt FROM Hierarchy WHERE Parent = ?", list(node_id))
      if (!is.null(child_count$cnt[1]) && child_count$cnt[1] > 0) {
        show_toast(toast("Delete blocked: node has children.", type = "warning"))
        return()
      }

      tryCatch({
        DBI::dbExecute(con, "DELETE FROM Hierarchy WHERE ID = ?", list(node_id))
        show_toast(toast("Node deleted.", type = "success"))
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Delete failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_delete_subtree, {
      if (!require_hierarchy_write()) return()
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      refresh_tree()
      all_ids <- c(node_id, get_descendants(rv$data, node_id))
      placeholders <- paste(rep("?", length(all_ids)), collapse = ", ")
      sql <- sprintf("DELETE FROM Hierarchy WHERE ID IN (%s)", placeholders)

      tryCatch({
        DBI::dbExecute(con, sql, as.list(all_ids))
        show_toast(toast(paste("Deleted", length(all_ids), "nodes."), type = "success"))
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Delete failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_fix_orphans, {
      if (!require_hierarchy_write()) return()
      tryCatch({
        count <- fix_orphan_nodes(con)
        if (count > 0) {
          show_toast(toast(paste("Reattached", count, "orphans."), type = "success"))
        } else {
          show_toast(toast("No orphans found.", type = "success"))
        }
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Fix failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_clip, {
      if (!require_hierarchy_write()) return()
      req(rv$data)
      if (!DBI::dbExistsTable(con, "Hierarchy")) {
        show_toast(toast("Hierarchy table not available.", type = "warning"))
        return()
      }

      tryCatch({
        DBI::dbExecute(con, "DROP TABLE IF EXISTS USysLowestBreakpoints_Hierarchy")
        DBI::dbExecute(con, "CREATE TABLE USysLowestBreakpoints_Hierarchy AS SELECT * FROM Hierarchy")

        delete_ids <- clip_hierarchy_ids(rv$data)
        if (length(delete_ids) > 0) {
          placeholders <- paste(rep("?", length(delete_ids)), collapse = ", ")
          sql <- sprintf("DELETE FROM USysLowestBreakpoints_Hierarchy WHERE ID IN (%s)", placeholders)
          DBI::dbExecute(con, sql, as.list(delete_ids))
        }

        lowest_tilde_ids <- get_lowest_tilde_ids(rv$data)
        if (length(lowest_tilde_ids) > 0) {
          set_lowest_tilde_levels(con, "USysLowestBreakpoints_Hierarchy", lowest_tilde_ids)
        }

        rv$use_clipped <- TRUE
        rv$clip_deleted <- length(delete_ids)
        rv$clip_lowest <- length(lowest_tilde_ids)
        rv$clip_total <- nrow(rv$data) - length(delete_ids)
        rv$clip_mode <- "clipped"
        refresh_tree()
        update_move_choices()
        show_toast(toast("Clipped hierarchy view created.", type = "success"))
      }, error = function(e) {
        show_toast(toast(paste("Clip failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_below_breaks, {
      if (!require_hierarchy_write()) return()
      req(rv$data)
      tryCatch({
        result <- create_lowest_breakpoints_table(con)
        rv$use_clipped <- TRUE
        rv$clip_deleted <- 0L
        rv$clip_lowest <- result$roots
        rv$clip_total <- result$count
        rv$clip_mode <- "below_breaks"
        refresh_tree()
        update_move_choices()
        show_toast(toast("Lowest breakpoints view created.", type = "success"))
      }, error = function(e) {
        show_toast(toast(paste("Below breaks failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_show_original, {
      rv$use_clipped <- FALSE
      rv$clip_deleted <- 0L
      rv$clip_lowest <- 0L
      rv$clip_total <- 0L
      rv$clip_mode <- "original"
      refresh_tree()
      update_move_choices()
      show_toast(toast("Showing original hierarchy.", type = "success"))
    })

    observeEvent(input$hier_view_user_list, {
      rv$su_mode <- "user"
      rv$su <- load_su("user", master_level = input$su_master_level)
      if (nrow(rv$su) == 0) {
        rv$su_status <- "User site unit list not available."
      } else {
        rv$su_status <- "Showing user site units."
      }
      bslib::nav_select("hier_tabs", "SU Table", session = session)
    })

    observeEvent(input$hier_view_plot_data, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) {
        show_toast(toast("Select a hierarchy node first.", type = "warning"))
        return()
      }

      node_row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(node_row) == 0) {
        show_toast(toast("Selected node not found.", type = "warning"))
        return()
      }

      rv$su_mode <- "plots"
      rv$su <- load_su("plots", node_row$Name[1])
      rv$su_status <- paste("Loaded plots for", node_row$Name[1])

      plots <- get_plots_for_site_unit(con, node_row$Name[1])
      if (length(plots) == 0) {
        show_toast(toast("No plots linked to this site unit.", type = "success"))
        bslib::nav_select("hier_tabs", "SU Table", session = session)
        return()
      }

      plot_number <- plots[1]
      project_id <- NULL
      if (DBI::dbExistsTable(con, "Env")) {
        env_fields <- DBI::dbListFields(con, "Env")
        project_col <- if ("projectid" %in% env_fields) "projectid" else if ("ProjectID" %in% env_fields) "ProjectID" else NULL
        plot_col <- if ("plotnumber" %in% env_fields) "plotnumber" else if ("PlotNumber" %in% env_fields) "PlotNumber" else NULL
        if (!is.null(project_col) && !is.null(plot_col)) {
          sql <- sprintf("SELECT %s AS project_id FROM Env WHERE %s = ?", project_col, plot_col)
          proj <- DBI::dbGetQuery(con, sql, list(plot_number))
          if (nrow(proj) > 0) project_id <- proj$project_id[1]
        }
      }

      if (!is.null(project_id) && !is.null(session$parent)) {
        if (is.function(session$parent$userData$select_plot)) {
          session$parent$userData$select_plot(
            plot_number = plot_number,
            project_id = project_id,
            site_unit = node_row$Name[1],
            navigate_tab = "FS882-6x4XL"
          )
        } else {
          updateSelectInput(session$parent, "sel_project", selected = as.character(project_id))
          updateSelectInput(session$parent, "sel_su", selected = as.character(plot_number))
          bslib::nav_select("main_tabs", "FS882-6x4XL", session = root_session)
        }
      }
      show_toast(toast(paste("Jumped to plot", plot_number), type = "success"))
    })

    observeEvent(input$hier_view_veg, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) {
        show_toast(toast("Select a hierarchy node first.", type = "warning"))
        return()
      }

      node_row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(node_row) == 0) {
        show_toast(toast("Selected node not found.", type = "warning"))
        return()
      }

      plots <- get_plots_for_site_unit(con, node_row$Name[1])
      if (length(plots) == 0) {
        show_toast(toast("No plots linked to this site unit.", type = "success"))
        return()
      }

      if (!is.null(session$parent)) {
        if (is.function(session$parent$userData$select_plot)) {
          session$parent$userData$select_plot(
            plot_number = plots[1],
            site_unit = node_row$Name[1],
            navigate_tab = "Vegetation"
          )
        } else {
          updateSelectInput(session$parent, "sel_su", selected = as.character(plots[1]))
          bslib::nav_select("main_tabs", "Vegetation", session = root_session)
        }
      }
      show_toast(toast("Opened vegetation for selected plot.", type = "success"))
    })

    observeEvent(input$hier_view_current_su, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) {
        show_toast(toast("Select a hierarchy node first.", type = "warning"))
        return()
      }

      node_row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(node_row) == 0) {
        show_toast(toast("Selected node not found.", type = "warning"))
        return()
      }

      rv$su_mode <- "plots"
      rv$su <- load_su("plots", node_row$Name[1])
      rv$su_status <- paste("Loaded plots for", node_row$Name[1])
      bslib::nav_select("hier_tabs", "SU Table", session = session)
    })

    observeEvent(input$hier_view_su_table, {
      rv$su_mode <- "plots"
      rv$su <- load_su("plots")
      rv$su_status <- ""
      bslib::nav_select("hier_tabs", "SU Table", session = session)
    })

    observeEvent(input$hier_load_hierarchy_plots, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) {
        show_toast(toast("Select a hierarchy node first.", type = "warning"))
        return()
      }

      site_units <- get_subtree_names(rv$data, node_id)
      if (length(site_units) == 0) {
        show_toast(toast("No site units found under this node.", type = "success"))
        return()
      }

      rv$su_mode <- "plots"
      rv$su <- load_su("plots", site_units)
      rv$su_status <- paste("Loaded plots for", length(site_units), "site units.")
      bslib::nav_select("hier_tabs", "SU Table", session = session)
    })

    observeEvent(input$hier_load_su_plots, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) {
        show_toast(toast("Select a hierarchy node first.", type = "warning"))
        return()
      }

      node_row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(node_row) == 0) {
        show_toast(toast("Selected node not found.", type = "warning"))
        return()
      }

      rv$su_mode <- "plots"
      rv$su <- load_su("plots", node_row$Name[1])
      rv$su_status <- paste("Loaded plots for", node_row$Name[1])
      bslib::nav_select("hier_tabs", "SU Table", session = session)
    })

    observeEvent(input$hier_copy, {
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      refresh_tree()
      rv$clipboard <- get_subtree(rv$data, node_id)
      show_toast(toast(paste("Copied", nrow(rv$clipboard), "nodes."), type = "success"))
    })

    observeEvent(input$hier_paste, {
      if (!require_hierarchy_write()) return()
      req(rv$clipboard)
      selected <- shinyTree::get_selected(input$hier_tree)
      parent_id <- parse_hierarchy_id(selected)
      if (is.na(parent_id)) parent_id <- NA_integer_

      parent_level <- -1L
      if (!is.na(parent_id) && !is.null(rv$data) && "Level" %in% names(rv$data)) {
        parent_level <- rv$data$Level[rv$data$ID == parent_id][1]
        if (is.na(parent_level)) parent_level <- -1L
      }

      tryCatch({
        count <- insert_subtree(con, rv$clipboard, parent_id, parent_level)
        show_toast(toast(paste("Pasted", count, "nodes."), type = "success"))
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Paste failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_merge, {
      if (!require_hierarchy_write()) return()
      req(input$merge_table)
      table <- trimws(input$merge_table)
      if (!nzchar(table)) return()

      if (!DBI::dbExistsTable(con, table)) {
        show_toast(toast("Merge table not found.", type = "danger"))
        return()
      }

      merge_fields <- DBI::dbListFields(con, table)
      if (!("Name" %in% merge_fields)) {
        show_toast(toast("Merge table is missing Name column.", type = "danger"))
        return()
      }
      merge_cols <- intersect(c("ID", "Name", "Parent", "Level", "Tag", "MyOrder"), merge_fields)
      if (length(merge_cols) == 0) {
        show_toast(toast("Merge table is missing required fields.", type = "danger"))
        return()
      }
      source <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s", paste(merge_cols, collapse = ", "), table))
      if (nrow(source) == 0) {
        show_toast(toast("Merge table has no rows.", type = "warning"))
        return()
      }

      allow_dupes <- isTRUE(input$merge_allow_dupes)
      filtered <- list(data = source, dropped = 0L, renamed = 0L)
      if (!allow_dupes) {
        existing <- DBI::dbGetQuery(con, "SELECT Name FROM Hierarchy")
        conflict_mode <- input$merge_conflict_mode
        conflict_text <- trimws(input$merge_conflict_text)
        prefix <- if (identical(conflict_mode, "prefix")) conflict_text else ""
        suffix <- if (identical(conflict_mode, "suffix")) conflict_text else ""
        if (identical(conflict_mode, "skip")) {
          filtered <- filter_duplicate_subtrees(source, unique(existing$Name))
          if (filtered$dropped > 0) {
            show_toast(toast(paste("Skipped", filtered$dropped, "nodes in duplicate subtrees."), type = "warning"))
          }
        } else {
          filtered <- resolve_duplicate_names(source, unique(existing$Name), conflict_mode, prefix, suffix)
          if (filtered$renamed > 0) {
            show_toast(toast(paste("Renamed", filtered$renamed, "duplicate names."), type = "success"))
          }
        }
        if (nrow(filtered$data) == 0) {
          show_toast(toast("No new nodes to merge.", type = "success"))
          return()
        }
      }

      tryCatch({
        result <- insert_rekeyed_hierarchy(con, filtered$data, -1L)
        show_toast(toast(paste("Merged", result$count, "nodes."), type = "success"))
        if (result$missing_parents > 0) {
          show_toast(toast(paste("Reattached", result$missing_parents, "orphaned nodes to root."), type = "warning"))
        }
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Merge failed:", e$message), type = "danger"))
      })
    })

    observeEvent(input$hier_move, {
      if (!require_hierarchy_write()) return()
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      refresh_tree()
      parent_id <- suppressWarnings(as.integer(input$move_parent))
      if (is.na(parent_id)) parent_id <- NA_integer_

      tryCatch({
        result <- hierarchy_sidebar_move_node(
          con = con,
          node_id = node_id,
          parent_id = if (is.na(parent_id)) NULL else parent_id,
          table_name = "Hierarchy"
        )
        refresh_tree()
        update_move_choices()
        select_node_by_id(node_id)
        if (isTRUE(result$changed)) {
          show_toast(toast("Node moved.", type = "success"))
        } else {
          show_toast(toast("Node is already under that parent.", type = "success"))
        }
      }, error = function(e) {
        show_toast(toast(paste("Move failed:", e$message), type = "danger"))
      })
    })

    reorder_sibling <- function(direction = c("up", "down")) {
      if (!require_hierarchy_write()) return()
      direction <- match.arg(direction)
      if (is.null(rv$data) || !("MyOrder" %in% names(rv$data))) {
        show_toast(toast("Ordering not available for this hierarchy.", type = "warning"))
        return()
      }

      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      refresh_tree()
      row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(row) == 0) return()

      parent_id <- row$Parent[1]
      siblings <- get_sibling_order(rv$data, parent_id)
      if (nrow(siblings) < 2) return()

      idx <- which(siblings$ID == node_id)
      if (length(idx) == 0) return()

      swap_idx <- if (direction == "up") idx - 1 else idx + 1
      if (swap_idx < 1 || swap_idx > nrow(siblings)) return()

      current_id <- siblings$ID[idx]
      swap_id <- siblings$ID[swap_idx]
      current_order <- suppressWarnings(as.numeric(siblings$MyOrder[idx]))
      swap_order <- suppressWarnings(as.numeric(siblings$MyOrder[swap_idx]))

      if (is.na(current_order) || is.na(swap_order)) {
        show_toast(toast("Ordering values missing. Refresh or re-add nodes.", type = "warning"))
        return()
      }

      tryCatch({
        DBI::dbExecute(con, "UPDATE Hierarchy SET MyOrder = ? WHERE ID = ?", list(swap_order, current_id))
        DBI::dbExecute(con, "UPDATE Hierarchy SET MyOrder = ? WHERE ID = ?", list(current_order, swap_id))
        show_toast(toast("Order updated.", type = "success"))
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        show_toast(toast(paste("Order change failed:", e$message), type = "danger"))
      })
    }

    observeEvent(input$hier_move_up, {
      reorder_sibling("up")
    })

    observeEvent(input$hier_move_down, {
      reorder_sibling("down")
    })

    observeEvent(input$hier_tree, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) return()

      row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(row) == 0) return()

      rv$selected_id <- node_id
      rv$selected_path <- get_node_path(rv$data, node_id)
      updateTextInput(session, "hier_name", value = row$Name[1])
      if ("Tag" %in% names(row)) {
        updateTextInput(session, "hier_tag", value = ifelse(is.na(row$Tag[1]), "", row$Tag[1]))
      }
      parent_id <- row$Parent[1]
      updateSelectInput(session, "move_parent", selected = if (is.na(parent_id)) "" else as.character(parent_id))
    })

    select_node_by_id <- function(node_id) {
      if (is.na(node_id)) return(FALSE)
      idx <- which(rv$data$ID == node_id)
      if (length(idx) == 0) return(FALSE)
      rv$selected_id <- node_id
      rv$selected_path <- get_node_path(rv$data, node_id)
      updateTextInput(session, "hier_name", value = rv$data$Name[idx[1]])
      if ("Tag" %in% names(rv$data)) {
        updateTextInput(session, "hier_tag", value = ifelse(is.na(rv$data$Tag[idx[1]]), "", rv$data$Tag[idx[1]]))
      }
      parent_id <- rv$data$Parent[idx[1]]
      updateSelectInput(session, "move_parent", selected = if (is.na(parent_id)) "" else as.character(parent_id))
      TRUE
    }

    perform_find <- function() {
      req(rv$data)
      query <- trimws(input$hier_find)
      if (!nzchar(query)) return()

      match_idx <- which(tolower(rv$data$Name) == tolower(query))
      if (length(match_idx) == 0) {
        match_idx <- which(grepl(query, rv$data$Name, ignore.case = TRUE))
      }
      if (length(match_idx) == 0) {
        rv$find_matches <- integer(0)
        rv$find_index <- 0L
        rv$find_query <- query
        show_toast(toast("No matching node found.", type = "warning"))
        return()
      }

      rv$find_matches <- rv$data$ID[match_idx]
      rv$find_index <- 1L
      rv$find_query <- query

      if (select_node_by_id(rv$find_matches[rv$find_index])) {
        show_toast(toast("Node selected.", type = "success"))
      }
    }

    move_find <- function(step) {
      if (length(rv$find_matches) == 0) {
        show_toast(toast("Use Find first.", type = "success"))
        return()
      }
      total <- length(rv$find_matches)
      next_idx <- rv$find_index + step
      if (next_idx < 1L) next_idx <- total
      if (next_idx > total) next_idx <- 1L
      rv$find_index <- next_idx
      select_node_by_id(rv$find_matches[rv$find_index])
    }

    observeEvent(input$hier_find_btn, {
      perform_find()
    })

    observeEvent(input$hier_find_enter, {
      perform_find()
    })

    observeEvent(input$hier_find_next, {
      move_find(1L)
    })

    observeEvent(input$hier_find_next_key, {
      move_find(1L)
    })

    observeEvent(input$hier_find_prev, {
      move_find(-1L)
    })

    observeEvent(input$hier_find_prev_key, {
      move_find(-1L)
    })

    observeEvent(input$su_add, {
      if (!require_su_write()) return()
      if (identical(rv$su_mode, "units") || identical(rv$su_mode, "master") || identical(rv$su_mode, "user")) {
        show_toast(toast("Switch to plot view to edit.", type = "warning"))
        return()
      }
      if (is.null(rv$su)) rv$su <- load_su()
      rv$su <- rbind(rv$su, data.frame(PlotNumber = "", SiteUnit = "", stringsAsFactors = FALSE))
    })

    observeEvent(input$su_delete, {
      if (!require_su_write()) return()
      if (identical(rv$su_mode, "units") || identical(rv$su_mode, "master") || identical(rv$su_mode, "user")) {
        show_toast(toast("Switch to plot view to edit.", type = "warning"))
        return()
      }
      req(rv$su)
      row_idx <- get_hot_selected_row(input$su_hot_select)
      req(row_idx)
      row_idx <- as.integer(row_idx)
      if (row_idx < 1 || row_idx > nrow(rv$su)) return()

      plot_id <- rv$su$PlotNumber[row_idx]
      site_unit <- rv$su$SiteUnit[row_idx]
      rv$su <- rv$su[-row_idx, , drop = FALSE]
      if (!is.null(plot_id) && nzchar(plot_id)) {
        tryCatch({
          sync_ensure_local_tables(con)
          project_id <- resolve_project_id_for_plot(con, plot_id, state$CurrProject)
          sync_delete_local_row(con, table_name = "su", pk_value = plot_id, project_id = project_id)
          log_audit_change(con, project_id, state$User, plot_id, "SU", "SiteUnit", site_unit, NA)
          sync_touch_state(state)
          rv$su_status <- paste("Deleted plot", plot_id)
        }, error = function(e) {
          rv$su_status <- paste("Delete failed:", e$message)
        })
      }
    })

    observeEvent(input$su_hot, {
      if (identical(rv$su_mode, "units") || identical(rv$su_mode, "master") || identical(rv$su_mode, "user")) return()
      if (!require_su_write()) return()
      req(rv$su)
      new_df <- rhandsontable::hot_to_r(input$su_hot)
      if (!all(c("PlotNumber", "SiteUnit") %in% names(new_df))) return()

      new_df <- new_df[, c("PlotNumber", "SiteUnit"), drop = FALSE]
      old_df <- rv$su

      normalize <- function(x) {
        val <- as.character(x)
        val[is.na(val)] <- ""
        trimws(val)
      }

      new_df$PlotNumber <- normalize(new_df$PlotNumber)
      new_df$SiteUnit <- normalize(new_df$SiteUnit)
      old_df$PlotNumber <- normalize(old_df$PlotNumber)
      old_df$SiteUnit <- normalize(old_df$SiteUnit)

      new_keys <- new_df$PlotNumber[new_df$PlotNumber != ""]
      old_keys <- old_df$PlotNumber[old_df$PlotNumber != ""]

      if (any(duplicated(new_keys))) {
        show_toast(toast("Duplicate PlotNumber detected. Fix duplicates before saving.", type = "warning"))
        return()
      }

      to_delete <- setdiff(old_keys, new_keys)
      to_insert <- setdiff(new_keys, old_keys)
      to_update <- intersect(old_keys, new_keys)

      changed <- FALSE
      sync_ensure_local_tables(con)

      for (plot_id in to_delete) {
        old_val <- old_df$SiteUnit[old_df$PlotNumber == plot_id][1]
        tryCatch({
          project_id <- resolve_project_id_for_plot(con, plot_id, state$CurrProject)
          sync_delete_local_row(con, table_name = "su", pk_value = plot_id, project_id = project_id)
          log_audit_change(con, project_id, state$User, plot_id, "SU", "SiteUnit", old_val, NA)
          changed <- TRUE
        }, error = function(e) {
          rv$su_status <- paste("Delete failed:", e$message)
        })
      }

      for (plot_id in to_insert) {
        site_unit <- new_df$SiteUnit[new_df$PlotNumber == plot_id][1]
        tryCatch({
          DBI::dbExecute(
            con,
            "INSERT INTO SU (PlotNumber, SiteUnit, local_modified_utc) VALUES (?, ?, CURRENT_TIMESTAMP)",
            list(plot_id, site_unit)
          )
          project_id <- resolve_project_id_for_plot(con, plot_id, state$CurrProject)
          sync_record_local_change(
            con,
            table_name = "su",
            pk_value = plot_id,
            project_id = project_id,
            change_type = "insert"
          )
          log_audit_change(con, project_id, state$User, plot_id, "SU", "SiteUnit", NA, site_unit)
          changed <- TRUE
        }, error = function(e) {
          rv$su_status <- paste("Insert failed:", e$message)
        })
      }

      for (plot_id in to_update) {
        new_val <- new_df$SiteUnit[new_df$PlotNumber == plot_id][1]
        old_val <- old_df$SiteUnit[old_df$PlotNumber == plot_id][1]
        if (identical(new_val, old_val)) next
        tryCatch({
          prior_row <- tryCatch(
            DBI::dbGetQuery(con, "SELECT * FROM SU WHERE PlotNumber = ? LIMIT 1", list(plot_id)),
            error = function(e) data.frame()
          )
          DBI::dbExecute(
            con,
            "UPDATE SU SET SiteUnit = ?, local_modified_utc = CURRENT_TIMESTAMP WHERE PlotNumber = ?",
            list(new_val, plot_id)
          )
          project_id <- resolve_project_id_for_plot(con, plot_id, state$CurrProject)
          sync_record_local_change(
            con,
            table_name = "su",
            pk_value = plot_id,
            project_id = project_id,
            change_type = "update",
            prior_payload = if (nrow(prior_row) > 0) as.list(prior_row[1, , drop = FALSE]) else NULL
          )
          log_audit_change(con, project_id, state$User, plot_id, "SU", "SiteUnit", old_val, new_val)
          changed <- TRUE
        }, error = function(e) {
          rv$su_status <- paste("Update failed:", e$message)
        })
      }

      if (changed) {
        rv$su <- load_su()
        sync_touch_state(state)
        rv$su_status <- "SU table updated."
      }
    })

    observeEvent(input$su_show_units, {
      rv$su_mode <- "units"
      rv$su <- load_su("units")
      rv$su_status <- "Showing distinct site units."
    })

    observeEvent(input$su_show_plots, {
      rv$su_mode <- "plots"
      rv$su <- load_su("plots")
      rv$su_status <- ""
    })

    observeEvent(input$su_show_master, {
      rv$su_mode <- "master"
      rv$su <- load_su("master", master_level = input$su_master_level)
      rv$su_status <- ""
    })

    observeEvent(input$su_show_user, {
      rv$su_mode <- "user"
      rv$su <- load_su("user", master_level = input$su_master_level)
      if (nrow(rv$su) == 0) {
        rv$su_status <- "User site unit list not available."
      } else {
        rv$su_status <- ""
      }
    })

    observeEvent(input$su_env_to_su, {
      if (!require_su_write()) return()
      tryCatch({
        before_su <- if (DBI::dbExistsTable(con, "SU")) {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
        } else {
          data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
        }
        count <- sync_env_to_su(con)
        after_su <- if (DBI::dbExistsTable(con, "SU")) {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
        } else {
          data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
        }
        log_su_audit_changes(before_su, after_su)
        rv$su <- load_su("plots")
        rv$su_status <- paste("Env -> SU updated", count, "rows")
      }, error = function(e) {
        rv$su_status <- paste("Env -> SU failed:", e$message)
      })
    })

    observeEvent(input$su_su_to_env, {
      if (!require_su_write()) return()
      tryCatch({
        before_env <- data.frame()
        if (DBI::dbExistsTable(con, "Env")) {
          fields <- DBI::dbListFields(con, "Env")
          select_cols <- intersect(c("PlotNumber", "ProjectID", "UserSiteUnit"), fields)
          if (all(c("PlotNumber", "UserSiteUnit") %in% select_cols)) {
            before_env <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM Env", paste(select_cols, collapse = ", ")))
          }
        }
        count <- sync_su_to_env(con)
        after_env <- data.frame()
        if (DBI::dbExistsTable(con, "Env")) {
          fields <- DBI::dbListFields(con, "Env")
          select_cols <- intersect(c("PlotNumber", "ProjectID", "UserSiteUnit"), fields)
          if (all(c("PlotNumber", "UserSiteUnit") %in% select_cols)) {
            after_env <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM Env", paste(select_cols, collapse = ", ")))
          }
        }
        log_env_siteunit_changes(before_env, after_env, "UserSiteUnit")
        rv$su_status <- paste("SU -> Env updated", count, "rows")
      }, error = function(e) {
        rv$su_status <- paste("SU -> Env failed:", e$message)
      })
    })

    observeEvent(input$su_bec_to_su, {
      if (!require_su_write()) return()
      tryCatch({
        before_su <- if (DBI::dbExistsTable(con, "SU")) {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
        } else {
          data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
        }
        count <- copy_bec_to_su(con)
        after_su <- if (DBI::dbExistsTable(con, "SU")) {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
        } else {
          data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
        }
        log_su_audit_changes(before_su, after_su)
        rv$su <- load_su("plots")
        rv$su_status <- paste("BEC -> SU updated", count, "rows")
      }, error = function(e) {
        rv$su_status <- paste("BEC -> SU failed:", e$message)
      })
    })

    observeEvent(input$su_build_from_env, {
      if (!require_su_write()) return()
      zone_val <- trimws(input$su_filter_zone)
      subzone_val <- trimws(input$su_filter_subzone)
      replace_flag <- isTRUE(input$su_replace)
      tryCatch({
        before_su <- if (DBI::dbExistsTable(con, "SU")) {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
        } else {
          data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
        }
        count <- build_su_from_env(con, zone = zone_val, subzone = subzone_val, replace = replace_flag)
        after_su <- if (DBI::dbExistsTable(con, "SU")) {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
        } else {
          data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
        }
        log_su_audit_changes(before_su, after_su)
        rv$su <- load_su("plots")
        rv$su_status <- paste("Built SU from Env:", count, "rows")
      }, error = function(e) {
        rv$su_status <- paste("Build SU failed:", e$message)
      })
    })

    observeEvent(input$su_build_from_filter, {
      if (!require_su_write()) return()
      column_val <- trimws(input$su_filter_column)
      value_val <- trimws(input$su_filter_value)
      replace_flag <- isTRUE(input$su_replace)
      carry_flag <- isTRUE(input$su_carry_siteunit)
      tryCatch({
        before_su <- if (DBI::dbExistsTable(con, "SU")) {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
        } else {
          data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
        }
        count <- build_su_from_env_filter(
          con,
          column = column_val,
          value = value_val,
          replace = replace_flag,
          carry_siteunit = carry_flag
        )
        after_su <- if (DBI::dbExistsTable(con, "SU")) {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM SU")
        } else {
          data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE)
        }
        log_su_audit_changes(before_su, after_su)
        rv$su <- load_su("plots")
        rv$su_status <- paste("Built SU from filter:", count, "rows")
      }, error = function(e) {
        rv$su_status <- paste("Build filter failed:", e$message)
      })
    })

    observeEvent(input$su_master_level, {
      if (!identical(rv$su_mode, "master")) return()
      rv$su <- load_su("master", master_level = input$su_master_level)
    })
  })
}
