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
  if (!DBI::dbExistsTable(con, "Sample_Hierarchy")) return(FALSE)
  column_name %in% DBI::dbListFields(con, "Sample_Hierarchy")
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
  if (!DBI::dbExistsTable(con, "Sample_Hierarchy")) return(0L)
  df <- DBI::dbGetQuery(con, "SELECT ID, Parent FROM Sample_Hierarchy")
  orphan_ids <- find_orphan_nodes(df)
  if (length(orphan_ids) == 0) return(0L)

  placeholders <- paste(rep("?", length(orphan_ids)), collapse = ", ")
  sql <- sprintf("UPDATE Sample_Hierarchy SET Parent = NULL WHERE ID IN (%s)", placeholders)
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

get_plots_for_site_unit <- function(con, site_unit) {
  if (!DBI::dbExistsTable(con, "Sample_SU")) return(character(0))
  plots <- DBI::dbGetQuery(
    con,
    "SELECT PlotNumber FROM Sample_SU WHERE SiteUnit = ?",
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
  level_map <- if (use_level) compute_subtree_levels(subtree, parent_level) else NULL

  max_id <- DBI::dbGetQuery(con, "SELECT MAX(ID) AS max_id FROM Sample_Hierarchy")
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
    root_sql <- "SELECT MAX(MyOrder) AS max_order FROM Sample_Hierarchy WHERE Parent IS NULL"
    root_params <- list()
    if (!is.na(new_parent)) {
      root_sql <- "SELECT MAX(MyOrder) AS max_order FROM Sample_Hierarchy WHERE Parent = ?"
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

    if (use_level && use_order) {
      level_val <- level_map[[as.character(old_id)]]
      DBI::dbExecute(
        con,
        "INSERT INTO Sample_Hierarchy (ID, Name, Parent, Level, MyOrder) VALUES (?, ?, ?, ?, ?)",
        list(id_map[[as.character(old_id)]], row$Name, parent_new, level_val, order_val)
      )
    } else if (use_level) {
      level_val <- level_map[[as.character(old_id)]]
      DBI::dbExecute(
        con,
        "INSERT INTO Sample_Hierarchy (ID, Name, Parent, Level) VALUES (?, ?, ?, ?)",
        list(id_map[[as.character(old_id)]], row$Name, parent_new, level_val)
      )
    } else if (use_order) {
      DBI::dbExecute(
        con,
        "INSERT INTO Sample_Hierarchy (ID, Name, Parent, MyOrder) VALUES (?, ?, ?, ?)",
        list(id_map[[as.character(old_id)]], row$Name, parent_new, order_val)
      )
    } else {
      DBI::dbExecute(
        con,
        "INSERT INTO Sample_Hierarchy (ID, Name, Parent) VALUES (?, ?, ?)",
        list(id_map[[as.character(old_id)]], row$Name, parent_new)
      )
    }
    count <- count + 1
  }

  count
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
            actionButton(ns("hier_add"), "Add Node", class = "btn-primary"),
            actionButton(ns("hier_rename"), "Rename", class = "btn-warning"),
            actionButton(ns("hier_delete"), "Delete", class = "btn-danger"),
            actionButton(ns("hier_delete_subtree"), "Delete Subtree", class = "btn-danger"),
            actionButton(ns("hier_refresh"), "Refresh", class = "btn-secondary"),
            actionButton(ns("hier_fix_orphans"), "Reattach Orphans", class = "btn-outline-secondary"),
            col_widths = c(3, 2, 2, 2, 2, 1, 2)
          ),
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
            actionButton(ns("hier_merge"), "Merge", class = "btn-outline-secondary"),
            col_widths = c(2, 2, 5, 3)
          ),
          layout_columns(
            textInput(ns("hier_find"), "Find Node", placeholder = "Enter name"),
            actionButton(ns("hier_find_btn"), "Find", class = "btn-outline-secondary"),
            col_widths = c(8, 2)
          ),
          verbatimTextOutput(ns("merge_preview")),
          shinyTree::shinyTreeOutput(ns("hier_tree"), height = "600px"),
          verbatimTextOutput(ns("hier_status"))
        ),
        nav_panel("SU Table",
          layout_columns(
            actionButton(ns("su_add"), "Add Row", class = "btn-primary"),
            actionButton(ns("su_delete"), "Delete Selected", class = "btn-danger"),
            actionButton(ns("su_refresh"), "Refresh", class = "btn-secondary"),
            actionButton(ns("su_show_units"), "Show Units", class = "btn-outline-secondary"),
            actionButton(ns("su_show_plots"), "Show Plots", class = "btn-outline-secondary"),
            col_widths = c(2, 2, 2, 2, 2)
          ),
          rhandsontable::rhandsontableOutput(ns("su_hot")),
          verbatimTextOutput(ns("su_status"))
        )
      )
    )
  )
}

mod_hierarchy_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(
      data = NULL,
      clipboard = NULL,
      su = NULL,
      su_status = "",
      selected_path = NULL,
      selected_id = NA_integer_,
      orphan_count = 0L,
      su_mode = "plots"
    )

    load_hierarchy <- function() {
      if (!DBI::dbExistsTable(con, "Sample_Hierarchy")) return(data.frame())
      fields <- DBI::dbListFields(con, "Sample_Hierarchy")
      select_cols <- intersect(c("ID", "Name", "Parent", "Level", "MyOrder"), fields)
      if (length(select_cols) == 0) return(data.frame())
      order_clause <- if ("MyOrder" %in% select_cols) {
        "ORDER BY Parent NULLS FIRST, MyOrder NULLS LAST, Name"
      } else {
        "ORDER BY Name"
      }
      sql <- sprintf("SELECT %s FROM Sample_Hierarchy %s", paste(select_cols, collapse = ", "), order_clause)
      DBI::dbGetQuery(con, sql)
    }

    load_su <- function(mode = rv$su_mode, site_units = NULL) {
      if (!DBI::dbExistsTable(con, "Sample_SU")) {
        return(data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE))
      }
      if (identical(mode, "units")) {
        units <- DBI::dbGetQuery(con, "SELECT DISTINCT SiteUnit FROM Sample_SU ORDER BY SiteUnit")
        data.frame(PlotNumber = "", SiteUnit = units$SiteUnit, stringsAsFactors = FALSE)
      } else {
        if (!is.null(site_units) && length(site_units) > 0) {
          placeholders <- paste(rep("?", length(site_units)), collapse = ", ")
          sql <- sprintf("SELECT PlotNumber, SiteUnit FROM Sample_SU WHERE SiteUnit IN (%s) ORDER BY PlotNumber", placeholders)
          DBI::dbGetQuery(con, sql, as.list(site_units))
        } else {
          DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM Sample_SU ORDER BY PlotNumber")
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

    observeEvent(input$hier_refresh, {
      refresh_tree()
      update_move_choices()
    })

    observeEvent(input$su_refresh, {
      rv$su <- load_su()
    })

    output$hier_tree <- shinyTree::renderShinyTree({
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
        if (nzchar(path_text)) {
          status_parts <- c(status_parts, paste("Selected:", path_text))
        }
        paste(status_parts, collapse = " | ")
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

      existing <- DBI::dbGetQuery(con, "SELECT Name FROM Sample_Hierarchy")
      existing_names <- unique(existing$Name)

      dupes <- sum(source$Name %in% existing_names)
      total <- nrow(source)
      paste("Merge preview:", total, "rows;", dupes, "duplicates;", total - dupes, "new")
    })

    output$su_hot <- rhandsontable::renderRHandsontable({
      req(rv$su)
      read_only <- identical(rv$su_mode, "units")
      rhandsontable::rhandsontable(rv$su, rowHeaders = FALSE, stretchH = "all", readOnly = read_only)
    })

    output$su_status <- renderText({
      mode_label <- if (identical(rv$su_mode, "units")) "Site units" else "Plots"
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
      name_val <- trimws(input$hier_name)
      req(nzchar(name_val))
      refresh_tree()

      if (!is.null(rv$data) && name_val %in% rv$data$Name) {
        showNotification("Name already exists.", type = "warning")
        return()
      }

      selected <- shinyTree::get_selected(input$hier_tree)
      parent_id <- parse_hierarchy_id(selected)
      if (is.na(parent_id)) parent_id <- NA_integer_

      max_id <- DBI::dbGetQuery(con, "SELECT MAX(ID) AS max_id FROM Sample_Hierarchy")
      new_id <- if (is.na(max_id$max_id[1])) 1L else as.integer(max_id$max_id[1]) + 1L

      tryCatch({
        has_level <- hierarchy_has_column(con, "Level")
        has_order <- hierarchy_has_column(con, "MyOrder")
        if (has_level || has_order) {
          level_val <- 0L
          if (!is.null(rv$data) && "Level" %in% names(rv$data) && !is.na(parent_id)) {
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

          if (has_level && has_order) {
            DBI::dbExecute(
              con,
              "INSERT INTO Sample_Hierarchy (ID, Name, Parent, Level, MyOrder) VALUES (?, ?, ?, ?, ?)",
              list(new_id, name_val, parent_id, level_val, order_val)
            )
          } else if (has_level) {
            DBI::dbExecute(
              con,
              "INSERT INTO Sample_Hierarchy (ID, Name, Parent, Level) VALUES (?, ?, ?, ?)",
              list(new_id, name_val, parent_id, level_val)
            )
          } else if (has_order) {
            DBI::dbExecute(
              con,
              "INSERT INTO Sample_Hierarchy (ID, Name, Parent, MyOrder) VALUES (?, ?, ?, ?)",
              list(new_id, name_val, parent_id, order_val)
            )
          }
        } else {
          DBI::dbExecute(
            con,
            "INSERT INTO Sample_Hierarchy (ID, Name, Parent) VALUES (?, ?, ?)",
            list(new_id, name_val, parent_id)
          )
        }
        showNotification("Node added.", type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Add failed:", e$message), type = "error")
      })
    })

    observeEvent(input$hier_rename, {
      name_val <- trimws(input$hier_name)
      req(nzchar(name_val))
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      if (!is.null(rv$data)) {
        existing <- rv$data$Name[rv$data$ID != node_id]
        if (name_val %in% existing) {
          showNotification("Name already exists.", type = "warning")
          return()
        }
      }

      tryCatch({
        DBI::dbExecute(
          con,
          "UPDATE Sample_Hierarchy SET Name = ? WHERE ID = ?",
          list(name_val, node_id)
        )
        showNotification("Node renamed.", type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Rename failed:", e$message), type = "error")
      })
    })

    observeEvent(input$hier_delete, {
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      child_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS cnt FROM Sample_Hierarchy WHERE Parent = ?", list(node_id))
      if (!is.null(child_count$cnt[1]) && child_count$cnt[1] > 0) {
        showNotification("Delete blocked: node has children.", type = "warning")
        return()
      }

      tryCatch({
        DBI::dbExecute(con, "DELETE FROM Sample_Hierarchy WHERE ID = ?", list(node_id))
        showNotification("Node deleted.", type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Delete failed:", e$message), type = "error")
      })
    })

    observeEvent(input$hier_delete_subtree, {
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      refresh_tree()
      all_ids <- c(node_id, get_descendants(rv$data, node_id))
      placeholders <- paste(rep("?", length(all_ids)), collapse = ", ")
      sql <- sprintf("DELETE FROM Sample_Hierarchy WHERE ID IN (%s)", placeholders)

      tryCatch({
        DBI::dbExecute(con, sql, as.list(all_ids))
        showNotification(paste("Deleted", length(all_ids), "nodes."), type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Delete failed:", e$message), type = "error")
      })
    })

    observeEvent(input$hier_fix_orphans, {
      tryCatch({
        count <- fix_orphan_nodes(con)
        if (count > 0) {
          showNotification(paste("Reattached", count, "orphans."), type = "message")
        } else {
          showNotification("No orphans found.", type = "message")
        }
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Fix failed:", e$message), type = "error")
      })
    })

    observeEvent(input$hier_view_user_list, {
      rv$su_mode <- "units"
      rv$su <- load_su("units")
      rv$su_status <- "Showing distinct site units."
      bslib::nav_select("hier_tabs", "SU Table", session = session)
    })

    observeEvent(input$hier_view_plot_data, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) {
        showNotification("Select a hierarchy node first.", type = "warning")
        return()
      }

      node_row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(node_row) == 0) {
        showNotification("Selected node not found.", type = "warning")
        return()
      }

      plots <- get_plots_for_site_unit(con, node_row$Name[1])
      if (length(plots) == 0) {
        showNotification("No plots linked to this site unit.", type = "message")
        bslib::nav_select("hier_tabs", "SU Table", session = session)
        return()
      }

      plot_number <- plots[1]
      project_id <- NULL
      if (DBI::dbExistsTable(con, "Sample_Env")) {
        env_fields <- DBI::dbListFields(con, "Sample_Env")
        project_col <- if ("projectid" %in% env_fields) "projectid" else if ("ProjectID" %in% env_fields) "ProjectID" else NULL
        plot_col <- if ("plotnumber" %in% env_fields) "plotnumber" else if ("PlotNumber" %in% env_fields) "PlotNumber" else NULL
        if (!is.null(project_col) && !is.null(plot_col)) {
          sql <- sprintf("SELECT %s AS project_id FROM Sample_Env WHERE %s = ?", project_col, plot_col)
          proj <- DBI::dbGetQuery(con, sql, list(plot_number))
          if (nrow(proj) > 0) project_id <- proj$project_id[1]
        }
      }

      if (!is.null(project_id) && !is.null(session$parent)) {
        updateSelectInput(session$parent, "sel_project", selected = as.character(project_id))
      }

      if (!is.null(session$parent)) {
        updateSelectInput(session$parent, "sel_su", selected = as.character(plot_number))
      }

      if (!is.null(session$parent)) {
        bslib::nav_select("main_tabs", "Site & Env", session = session$parent)
      }
      showNotification(paste("Jumped to plot", plot_number), type = "message")
    })

    observeEvent(input$hier_view_veg, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) {
        showNotification("Select a hierarchy node first.", type = "warning")
        return()
      }

      node_row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(node_row) == 0) {
        showNotification("Selected node not found.", type = "warning")
        return()
      }

      plots <- get_plots_for_site_unit(con, node_row$Name[1])
      if (length(plots) == 0) {
        showNotification("No plots linked to this site unit.", type = "message")
        return()
      }

      if (!is.null(session$parent)) {
        updateSelectInput(session$parent, "sel_su", selected = as.character(plots[1]))
        bslib::nav_select("main_tabs", "Vegetation", session = session$parent)
      }
      showNotification("Opened vegetation for selected plot.", type = "message")
    })

    observeEvent(input$hier_view_current_su, {
      req(rv$data)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      if (is.na(node_id)) {
        showNotification("Select a hierarchy node first.", type = "warning")
        return()
      }

      node_row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(node_row) == 0) {
        showNotification("Selected node not found.", type = "warning")
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
        showNotification("Select a hierarchy node first.", type = "warning")
        return()
      }

      site_units <- get_subtree_names(rv$data, node_id)
      if (length(site_units) == 0) {
        showNotification("No site units found under this node.", type = "message")
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
        showNotification("Select a hierarchy node first.", type = "warning")
        return()
      }

      node_row <- rv$data[rv$data$ID == node_id, , drop = FALSE]
      if (nrow(node_row) == 0) {
        showNotification("Selected node not found.", type = "warning")
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
      showNotification(paste("Copied", nrow(rv$clipboard), "nodes."), type = "message")
    })

    observeEvent(input$hier_paste, {
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
        showNotification(paste("Pasted", count, "nodes."), type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Paste failed:", e$message), type = "error")
      })
    })

    observeEvent(input$hier_merge, {
      req(input$merge_table)
      table <- trimws(input$merge_table)
      if (!nzchar(table)) return()

      if (!DBI::dbExistsTable(con, table)) {
        showNotification("Merge table not found.", type = "error")
        return()
      }

      merge_fields <- DBI::dbListFields(con, table)
      merge_cols <- intersect(c("ID", "Name", "Parent", "MyOrder"), merge_fields)
      if (length(merge_cols) == 0) {
        showNotification("Merge table is missing required fields.", type = "error")
        return()
      }
      source <- DBI::dbGetQuery(con, sprintf("SELECT %s FROM %s", paste(merge_cols, collapse = ", "), table))
      if (nrow(source) == 0) {
        showNotification("Merge table has no rows.", type = "warning")
        return()
      }

      existing <- DBI::dbGetQuery(con, "SELECT Name FROM Sample_Hierarchy")
      filtered <- filter_duplicate_names(source, unique(existing$Name))
      if (filtered$dropped > 0) {
        showNotification(paste("Skipped", filtered$dropped, "duplicate names."), type = "warning")
      }
      if (nrow(filtered$data) == 0) {
        showNotification("No new nodes to merge.", type = "message")
        return()
      }

      tryCatch({
        count <- insert_subtree(con, filtered$data, NA_integer_, -1L)
        showNotification(paste("Merged", count, "nodes."), type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Merge failed:", e$message), type = "error")
      })
    })

    observeEvent(input$hier_move, {
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      refresh_tree()
      parent_id <- suppressWarnings(as.integer(input$move_parent))
      if (is.na(parent_id)) parent_id <- NA_integer_

      if (!is.na(parent_id)) {
        descendants <- get_descendants(rv$data, node_id)
        if (parent_id == node_id || parent_id %in% descendants) {
          showNotification("Move blocked: cannot move under self or descendant.", type = "warning")
          return()
        }
      }

      tryCatch({
        update_sql <- "UPDATE Sample_Hierarchy SET Parent = ?"
        update_params <- list(parent_id)

        if (!is.null(rv$data) && "MyOrder" %in% names(rv$data)) {
          siblings <- get_sibling_order(rv$data, parent_id)
          if (nrow(siblings) == 0 || all(is.na(suppressWarnings(as.numeric(siblings$MyOrder))))) {
            order_val <- 1
          } else {
            max_order <- suppressWarnings(max(as.numeric(siblings$MyOrder), na.rm = TRUE))
            order_val <- if (is.finite(max_order)) max_order + 1 else 1
          }
          update_sql <- paste0(update_sql, ", MyOrder = ?")
          update_params <- c(update_params, list(order_val))
        }

        update_sql <- paste0(update_sql, " WHERE ID = ?")
        update_params <- c(update_params, list(node_id))

        DBI::dbExecute(con, update_sql, update_params)

        if (!is.null(rv$data) && "Level" %in% names(rv$data)) {
          current_level <- rv$data$Level[rv$data$ID == node_id][1]
          parent_level <- if (is.na(parent_id)) -1L else rv$data$Level[rv$data$ID == parent_id][1]
          if (!is.na(current_level) && !is.na(parent_level)) {
            delta <- as.integer(parent_level + 1L) - as.integer(current_level)
            if (delta != 0) {
              ids <- c(node_id, get_descendants(rv$data, node_id))
              for (target_id in ids) {
                old_level <- rv$data$Level[rv$data$ID == target_id][1]
                new_level <- as.integer(old_level) + delta
                DBI::dbExecute(
                  con,
                  "UPDATE Sample_Hierarchy SET Level = ? WHERE ID = ?",
                  list(new_level, target_id)
                )
              }
            }
          }
        }
        showNotification("Node moved.", type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Move failed:", e$message), type = "error")
      })
    })

    reorder_sibling <- function(direction = c("up", "down")) {
      direction <- match.arg(direction)
      if (is.null(rv$data) || !("MyOrder" %in% names(rv$data))) {
        showNotification("Ordering not available for this hierarchy.", type = "warning")
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
        showNotification("Ordering values missing. Refresh or re-add nodes.", type = "warning")
        return()
      }

      tryCatch({
        DBI::dbExecute(con, "UPDATE Sample_Hierarchy SET MyOrder = ? WHERE ID = ?", list(swap_order, current_id))
        DBI::dbExecute(con, "UPDATE Sample_Hierarchy SET MyOrder = ? WHERE ID = ?", list(current_order, swap_id))
        showNotification("Order updated.", type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Order change failed:", e$message), type = "error")
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
      parent_id <- row$Parent[1]
      updateSelectInput(session, "move_parent", selected = if (is.na(parent_id)) "" else as.character(parent_id))
    })

    observeEvent(input$hier_find_btn, {
      req(rv$data)
      query <- trimws(input$hier_find)
      if (!nzchar(query)) return()

      match_idx <- which(tolower(rv$data$Name) == tolower(query))
      if (length(match_idx) == 0) {
        match_idx <- which(grepl(query, rv$data$Name, ignore.case = TRUE))
      }
      if (length(match_idx) == 0) {
        showNotification("No matching node found.", type = "warning")
        return()
      }

      node_id <- rv$data$ID[match_idx[1]]
      rv$selected_id <- node_id
      rv$selected_path <- get_node_path(rv$data, node_id)
      updateTextInput(session, "hier_name", value = rv$data$Name[match_idx[1]])
      parent_id <- rv$data$Parent[match_idx[1]]
      updateSelectInput(session, "move_parent", selected = if (is.na(parent_id)) "" else as.character(parent_id))
      showNotification("Node selected.", type = "message")
    })

    observeEvent(input$su_add, {
      if (identical(rv$su_mode, "units")) {
        showNotification("Switch to plot view to edit.", type = "warning")
        return()
      }
      if (is.null(rv$su)) rv$su <- load_su()
      rv$su <- rbind(rv$su, data.frame(PlotNumber = "", SiteUnit = "", stringsAsFactors = FALSE))
    })

    observeEvent(input$su_delete, {
      if (identical(rv$su_mode, "units")) {
        showNotification("Switch to plot view to edit.", type = "warning")
        return()
      }
      req(rv$su)
      row_idx <- get_hot_selected_row(input$su_hot_select)
      req(row_idx)
      row_idx <- as.integer(row_idx)
      if (row_idx < 1 || row_idx > nrow(rv$su)) return()

      plot_id <- rv$su$PlotNumber[row_idx]
      rv$su <- rv$su[-row_idx, , drop = FALSE]
      if (!is.null(plot_id) && nzchar(plot_id)) {
        tryCatch({
          DBI::dbExecute(con, "DELETE FROM Sample_SU WHERE PlotNumber = ?", list(plot_id))
          rv$su_status <- paste("Deleted plot", plot_id)
        }, error = function(e) {
          rv$su_status <- paste("Delete failed:", e$message)
        })
      }
    })

    observeEvent(input$su_hot, {
      if (identical(rv$su_mode, "units")) return()
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
        showNotification("Duplicate PlotNumber detected. Fix duplicates before saving.", type = "warning")
        return()
      }

      to_delete <- setdiff(old_keys, new_keys)
      to_insert <- setdiff(new_keys, old_keys)
      to_update <- intersect(old_keys, new_keys)

      changed <- FALSE

      for (plot_id in to_delete) {
        tryCatch({
          DBI::dbExecute(con, "DELETE FROM Sample_SU WHERE PlotNumber = ?", list(plot_id))
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
            "INSERT INTO Sample_SU (PlotNumber, SiteUnit) VALUES (?, ?)",
            list(plot_id, site_unit)
          )
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
          DBI::dbExecute(
            con,
            "UPDATE Sample_SU SET SiteUnit = ? WHERE PlotNumber = ?",
            list(new_val, plot_id)
          )
          changed <- TRUE
        }, error = function(e) {
          rv$su_status <- paste("Update failed:", e$message)
        })
      }

      if (changed) {
        rv$su <- load_su()
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
  })
}
