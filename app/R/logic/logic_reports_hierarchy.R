# Hierarchy Tree Formatting for Reports
#
# Ported from VPro64 Access VBA modules:
# - V7mdlReportsHierarchyDiagram.txt (tree walking, diagram generation)
# - V7mdlReportsShortVegHierarchy.txt (hierarchy ordering, sorting)
#
# Provides functions for:
# - Walking hierarchy trees (parent-child relationships)
# - Formatting hierarchies with indentation
# - Ordering hierarchy units for reports
# - Building tree diagrams

#' Build hierarchy tree path
#'
#' Creates full path from root to node (e.g., "Root / Branch / Leaf")
#'
#' @param con DBI connection to hierarchy table
#' @param node_id Integer ID of target node
#' @param hierarchy_table Name of hierarchy table (default "Hierarchy")
#' @param separator Path separator (default " / ")
#' @return Character path string
#' @family hierarchy
build_hierarchy_path <- function(con, node_id, hierarchy_table = "Hierarchy", separator = " / ") {
  
  # VBA source: V7mdlReportsHierarchyDiagram.txt::BuildListInXl() logic
  
  if (is.na(node_id) || !is.numeric(node_id)) return("")
  
  # Walk up the tree collecting names
  path_parts <- character()
  current_id <- node_id
  max_iterations <- 100  # Prevent infinite loops
  iteration <- 0
  
  while (!is.na(current_id) && iteration < max_iterations) {
    iteration <- iteration + 1
    
    sql <- sprintf("SELECT ID, Name, Parent FROM %s WHERE ID = ?", hierarchy_table)
    node <- DBI::dbGetQuery(con, sql, list(current_id))
    
    if (nrow(node) == 0) break
    
    path_parts <- c(as.character(node$Name[1]), path_parts)
    current_id <- node$Parent[1]
  }
  
  paste(path_parts, collapse = separator)
}

#' Walk hierarchy tree downward
#'
#' Returns all descendant nodes from a starting point
#'
#' @param con DBI connection
#' @param parent_id Integer ID of parent node
#' @param hierarchy_table Name of hierarchy table
#' @param max_level Maximum level depth to traverse
#' @param current_level Current recursion level (internal)
#' @return Data frame with ID, Name, Parent, Level, Path columns
#' @family hierarchy
walk_hierarchy_down <- function(con,
                               parent_id = NULL,
                               hierarchy_table = "Hierarchy",
                               max_level = 20,
                               current_level = 1) {
  
  # VBA source: V7mdlReportsHierarchyDiagram.txt::WalkTheTreeDown()
  
  if (current_level > max_level) {
    return(data.frame(
      ID = integer(),
      Name = character(),
      Parent = integer(),
      Level = integer(),
      Path = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Get children of current parent
  if (is.null(parent_id)) {
    sql <- sprintf("SELECT ID, Name, Parent, Level FROM %s WHERE Parent IS NULL", hierarchy_table)
    children <- DBI::dbGetQuery(con, sql)
  } else {
    sql <- sprintf("SELECT ID, Name, Parent, Level FROM %s WHERE Parent = ?", hierarchy_table)
    children <- DBI::dbGetQuery(con, sql, list(parent_id))
  }
  
  if (nrow(children) == 0) {
    return(data.frame(
      ID = integer(),
      Name = character(),
      Parent = integer(),
      Level = integer(),
      Path = character(),
      stringsAsFactors = FALSE
    ))
  }
  
  # Add current level info
  children$Level <- ifelse(is.na(children$Level), current_level, children$Level)
  children$Path <- ""
  
  # Build paths for each child
  for (i in seq_len(nrow(children))) {
    children$Path[i] <- build_hierarchy_path(con, children$ID[i], hierarchy_table)
  }
  
  # Recursively get descendants
  all_nodes <- children
  for (i in seq_len(nrow(children))) {
    descendants <- walk_hierarchy_down(
      con,
      parent_id = children$ID[i],
      hierarchy_table = hierarchy_table,
      max_level = max_level,
      current_level = current_level + 1
    )
    if (nrow(descendants) > 0) {
      all_nodes <- rbind(all_nodes, descendants)
    }
  }
  
  all_nodes
}

#' Format hierarchy with indentation
#'
#' Adds indentation markers to hierarchy names based on level
#'
#' @param hier_df Data frame with Level and Name columns
#' @param indent_char Character(s) to use for indentation (default "  ")
#' @param add_level_prefix Add level number prefix? (default FALSE)
#' @return Data frame with FormattedName column added
#' @export
#' @family hierarchy
format_hierarchy_indented <- function(hier_df,
                                     indent_char = "  ",
                                     add_level_prefix = FALSE) {
  
  # VBA source: V7mdlReportsHierarchyDiagram.txt::AddShape() - uses indentation
  
  if (nrow(hier_df) == 0) return(hier_df)
  
  # Normalize level column
  level_col <- NULL
  for (col in c("Level", "level")) {
    if (col %in% names(hier_df)) {
      level_col <- col
      break
    }
  }
  
  if (is.null(level_col)) {
    # No level info, return unformatted
    hier_df$FormattedName <- hier_df$Name
    return(hier_df)
  }
  
  # Format each name with indentation
  hier_df$FormattedName <- vapply(seq_len(nrow(hier_df)), function(i) {
    level <- hier_df[[level_col]][i]
    name <- as.character(hier_df$Name[i])
    
    if (is.na(level) || level <= 1) {
      prefix <- if (add_level_prefix) paste0("[", level, "] ") else ""
      return(paste0(prefix, name))
    }
    
    indent <- paste(rep(indent_char, level - 1), collapse = "")
    prefix <- if (add_level_prefix) paste0("[", level, "] ") else ""
    paste0(indent, prefix, name)
  }, character(1))
  
  hier_df
}

#' Order hierarchy for reporting
#'
#' Sorts hierarchy in tree order (depth-first traversal)
#'
#' @param con DBI connection
#' @param hierarchy_table Name of hierarchy table
#' @param cutoff_level Maximum level to include (NULL for all)
#' @return Data frame with hierarchy in tree order
#' @export
#' @family hierarchy
order_hierarchy_tree <- function(con,
                                hierarchy_table = "Hierarchy",
                                cutoff_level = NULL) {
  
  # VBA source: V7mdlReportsShortVegHierarchy.txt::ControlHierarchyOrder()
  
  # Get all hierarchy records
  sql <- sprintf("SELECT * FROM %s", hierarchy_table)
  hier <- DBI::dbGetQuery(con, sql)
  
  if (nrow(hier) == 0) return(hier)
  
  # Apply cutoff level if specified
  if (!is.null(cutoff_level) && "Level" %in% names(hier)) {
    cutoff <- suppressWarnings(as.integer(cutoff_level))
    if (!is.na(cutoff)) {
      hier <- hier[is.na(hier$Level) | hier$Level <= cutoff, , drop = FALSE]
    }
  }
  
  # Build tree order recursively
  ordered_ids <- integer()
  
  # Start with root nodes (where Parent IS NULL)
  roots <- hier[is.na(hier$Parent), , drop = FALSE]
  
  for (i in seq_len(nrow(roots))) {
    ordered_ids <- c(ordered_ids, traverse_subtree(hier, roots$ID[i]))
  }
  
  # Return in tree order
  hier_ordered <- hier[match(ordered_ids, hier$ID), , drop = FALSE]
  hier_ordered <- hier_ordered[!is.na(hier_ordered$ID), , drop = FALSE]
  
  hier_ordered
}

# Helper function for tree traversal
traverse_subtree <- function(hier_df, parent_id) {
  # VBA source: V7mdlReportsShortVegHierarchy.txt::OrderHierarchyStep2()
  
  ids <- parent_id
  
  # Find children
  children <- hier_df[!is.na(hier_df$Parent) & hier_df$Parent == parent_id, , drop = FALSE]
  
  if (nrow(children) == 0) return(ids)
  
  # Sort children by name
  children <- children[order(children$Name), , drop = FALSE]
  
  # Recursively add each child's subtree
  for (i in seq_len(nrow(children))) {
    child_subtree <- traverse_subtree(hier_df, children$ID[i])
    ids <- c(ids, child_subtree)
  }
  
  ids
}

#' Add hierarchy order columns
#'
#' Adds MinOrder and MaxOrder columns for hierarchy sorting
#'
#' @param hier_df Data frame with ID, Parent columns
#' @return Data frame with MinOrder, MaxOrder columns added
#' @family hierarchy
add_hierarchy_order_columns <- function(hier_df) {
  
  # VBA source: V7mdlReportsShortVegHierarchy.txt::SetMinMax()
  
  if (nrow(hier_df) == 0) return(hier_df)
  
  # Assign sequential order
  hier_df$MinOrder <- seq_len(nrow(hier_df))
  hier_df$MaxOrder <- seq_len(nrow(hier_df))
  
  # For each node, set MinOrder to minimum of self and descendants
  # and MaxOrder to maximum of self and descendants
  for (i in seq_len(nrow(hier_df))) {
    descendants <- get_all_descendants(hier_df, hier_df$ID[i])
    if (length(descendants) > 0) {
      desc_indices <- which(hier_df$ID %in% descendants)
      if (length(desc_indices) > 0) {
        hier_df$MinOrder[i] <- min(hier_df$MinOrder[c(i, desc_indices)])
        hier_df$MaxOrder[i] <- max(hier_df$MaxOrder[c(i, desc_indices)])
      }
    }
  }
  
  hier_df
}

# Helper to get all descendants
get_all_descendants <- function(hier_df, parent_id, max_depth = 100) {
  descendants <- integer()
  current_gen <- parent_id
  depth <- 0
  
  while (length(current_gen) > 0 && depth < max_depth) {
    depth <- depth + 1
    children <- hier_df$ID[!is.na(hier_df$Parent) & hier_df$Parent %in% current_gen]
    if (length(children) == 0) break
    descendants <- c(descendants, children)
    current_gen <- children
  }
  
  unique(descendants)
}

#' Get hierarchy level statistics
#'
#' Counts nodes at each level
#'
#' @param con DBI connection
#' @param hierarchy_table Name of hierarchy table
#' @return Data frame with Level, Count columns
#' @export
#' @family hierarchy
get_hierarchy_level_stats <- function(con, hierarchy_table = "Hierarchy") {
  sql <- sprintf("
    SELECT 
      Level,
      COUNT(*) as Count
    FROM %s
    GROUP BY Level
    ORDER BY Level
  ", hierarchy_table)
  
  DBI::dbGetQuery(con, sql)
}

#' Build flattened hierarchy list
#'
#' Returns hierarchy as a flat list with full paths
#'
#' @param con DBI connection
#' @param hierarchy_table Name of hierarchy table
#' @param include_long_names Join with MasterSiteUnitList for long names?
#' @param cutoff_level Maximum level to include
#' @return Data frame with ID, Name, Path, Level, LongName columns
#' @export
#' @family hierarchy
build_flat_hierarchy <- function(con,
                                hierarchy_table = "Hierarchy",
                                include_long_names = TRUE,
                                cutoff_level = NULL) {
  
  # Get basic hierarchy
  hier <- order_hierarchy_tree(con, hierarchy_table, cutoff_level)
  
  if (nrow(hier) == 0) return(hier)
  
  # Add paths
  hier$Path <- vapply(hier$ID, function(id) {
    build_hierarchy_path(con, id, hierarchy_table)
  }, character(1))
  
  # Join long names if requested
  if (include_long_names) {
    # Check if VLists.MasterSiteUnitList exists using SQL query
    table_exists <- tryCatch({
      DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM information_schema.tables 
                            WHERE table_schema = 'lists' AND table_name = 'MasterSiteUnitList'")$n > 0
    }, error = function(e) FALSE)
    
    if (table_exists) {
      long_names <- DBI::dbGetQuery(
        con,
        "SELECT SiteSeries, SiteSeriesLongName FROM VLists.MasterSiteUnitList"
      )
      names(long_names) <- c("Name", "LongName")
      hier <- dplyr::left_join(hier, long_names, by = "Name")
    } else {
      hier$LongName <- NA_character_
    }
  } else {
    hier$LongName <- NA_character_
  }
  
  hier
}

#' Check for hierarchy circular references
#'
#' Detects cycles in parent-child relationships
#'
#' @param con DBI connection
#' @param hierarchy_table Name of hierarchy table
#' @return Data frame with circular reference chains, or empty if none
#' @export
#' @family hierarchy
check_hierarchy_circular_refs <- function(con, hierarchy_table = "Hierarchy") {
  hier <- DBI::dbGetQuery(con, sprintf("SELECT ID, Name, Parent FROM %s", hierarchy_table))
  
  circular_refs <- data.frame(
    ID = integer(),
    Name = character(),
    Chain = character(),
    stringsAsFactors = FALSE
  )
  
  for (i in seq_len(nrow(hier))) {
    visited <- integer()
    current <- hier$ID[i]
    chain <- character()
    max_steps <- nrow(hier) + 1
    step <- 0
    
    while (!is.na(current) && step < max_steps) {
      step <- step + 1
      
      if (current %in% visited) {
        # Found a cycle
        idx <- which(hier$ID == hier$ID[i])
        circular_refs <- rbind(circular_refs, data.frame(
          ID = hier$ID[i],
          Name = hier$Name[i],
          Chain = paste(chain, collapse = " -> "),
          stringsAsFactors = FALSE
        ))
        break
      }
      
      visited <- c(visited, current)
      idx <- which(hier$ID == current)
      if (length(idx) == 0) break
      
      chain <- c(chain, as.character(hier$Name[idx[1]]))
      current <- hier$Parent[idx[1]]
    }
  }
  
  circular_refs
}
