hierarchy_label <- function(name, id) {
  paste0(name, " [", id, "]")
}

parse_hierarchy_id <- function(label) {
  if (is.null(label) || length(label) == 0) return(NA_integer_)
  m <- regmatches(label, regexec("\\[(\\d+)\\]$", label))
  if (length(m) == 0 || length(m[[1]]) < 2) return(NA_integer_)
  as.integer(m[[1]][2])
}

build_hierarchy_tree <- function(df, parent_id = NA_integer_) {
  if (nrow(df) == 0) return(list())
  roots <- df[is.na(df$Parent) & is.na(parent_id) | df$Parent == parent_id, , drop = FALSE]
  if (nrow(roots) == 0) return(list())

  tree <- list()
  for (i in seq_len(nrow(roots))) {
    row <- roots[i, ]
    label <- hierarchy_label(row$Name, row$ID)
    tree[[label]] <- build_hierarchy_tree(df, row$ID)
  }

  tree
}

mod_hierarchy_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Hierarchy"),
      navset_card_tab(
        nav_panel("Hierarchy",
          layout_columns(
            textInput(ns("hier_name"), "Name"),
            actionButton(ns("hier_add"), "Add Node", class = "btn-primary"),
            actionButton(ns("hier_rename"), "Rename", class = "btn-warning"),
            actionButton(ns("hier_delete"), "Delete", class = "btn-danger"),
            actionButton(ns("hier_delete_subtree"), "Delete Subtree", class = "btn-danger"),
            actionButton(ns("hier_refresh"), "Refresh", class = "btn-secondary"),
            col_widths = c(3, 2, 2, 2, 2, 1)
          ),
          layout_columns(
            selectInput(ns("move_parent"), "Move Node To", choices = NULL),
            actionButton(ns("hier_move"), "Move Node", class = "btn-outline-secondary"),
            col_widths = c(8, 4)
          ),
          layout_columns(
            actionButton(ns("hier_copy"), "Copy Subtree", class = "btn-outline-secondary"),
            actionButton(ns("hier_paste"), "Paste Subtree", class = "btn-outline-secondary"),
            textInput(ns("merge_table"), "Merge Table", placeholder = "OtherProject_Hierarchy"),
            actionButton(ns("hier_merge"), "Merge", class = "btn-outline-secondary"),
            col_widths = c(2, 2, 5, 3)
          ),
          shinyTree::shinyTreeOutput(ns("hier_tree"), height = "600px"),
          verbatimTextOutput(ns("hier_status"))
        ),
        nav_panel("SU Table",
          layout_columns(
            actionButton(ns("su_add"), "Add Row", class = "btn-primary"),
            actionButton(ns("su_delete"), "Delete Selected", class = "btn-danger"),
            actionButton(ns("su_refresh"), "Refresh", class = "btn-secondary"),
            col_widths = c(2, 2, 2)
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
    rv <- reactiveValues(data = NULL, clipboard = NULL, su = NULL, su_status = "")

    load_hierarchy <- function() {
      if (!DBI::dbExistsTable(con, "Sample_Hierarchy")) return(data.frame())
      DBI::dbGetQuery(con, "SELECT ID, Name, Parent FROM Sample_Hierarchy ORDER BY Name")
    }

    load_su <- function() {
      if (!DBI::dbExistsTable(con, "Sample_SU")) {
        return(data.frame(PlotNumber = character(0), SiteUnit = character(0), stringsAsFactors = FALSE))
      }
      DBI::dbGetQuery(con, "SELECT PlotNumber, SiteUnit FROM Sample_SU ORDER BY PlotNumber")
    }

    refresh_tree <- function() {
      rv$data <- load_hierarchy()
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
      build_hierarchy_tree(rv$data)
    })

    output$hier_status <- renderText({
      if (is.null(state$CurrProject)) {
        "Select a project to begin."
      } else if (is.null(rv$data)) {
        "No hierarchy loaded."
      } else {
        paste("Nodes:", nrow(rv$data))
      }
    })

    output$su_hot <- rhandsontable::renderRHandsontable({
      req(rv$su)
      rhandsontable::rhandsontable(rv$su, rowHeaders = FALSE, stretchH = "all")
    })

    output$su_status <- renderText({
      rv$su_status
    })

    get_hot_selected_row <- function(selection) {
      if (is.null(selection)) return(NULL)
      if (is.list(selection) && !is.null(selection$r)) return(selection$r)
      if (is.list(selection) && !is.null(selection$select) && !is.null(selection$select$r)) return(selection$select$r)
      if (is.matrix(selection) && ncol(selection) >= 1) return(selection[1, 1])
      NULL
    }

    observeEvent(input$hier_add, {
      req(input$hier_name)
      refresh_tree()

      selected <- shinyTree::get_selected(input$hier_tree)
      parent_id <- parse_hierarchy_id(selected)
      if (is.na(parent_id)) parent_id <- NA_integer_

      max_id <- DBI::dbGetQuery(con, "SELECT MAX(ID) AS max_id FROM Sample_Hierarchy")
      new_id <- if (is.na(max_id$max_id[1])) 1L else as.integer(max_id$max_id[1]) + 1L

      tryCatch({
        DBI::dbExecute(
          con,
          "INSERT INTO Sample_Hierarchy (ID, Name, Parent) VALUES (?, ?, ?)",
          list(new_id, input$hier_name, parent_id)
        )
        showNotification("Node added.", type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Add failed:", e$message), type = "error")
      })
    })

    observeEvent(input$hier_rename, {
      req(input$hier_name)
      selected <- shinyTree::get_selected(input$hier_tree)
      node_id <- parse_hierarchy_id(selected)
      req(node_id)

      tryCatch({
        DBI::dbExecute(
          con,
          "UPDATE Sample_Hierarchy SET Name = ? WHERE ID = ?",
          list(input$hier_name, node_id)
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

    get_descendants <- function(df, node_id) {
      if (nrow(df) == 0) return(integer(0))
      direct <- df$ID[df$Parent == node_id]
      if (length(direct) == 0) return(integer(0))
      children <- unlist(lapply(direct, function(id) get_descendants(df, id)))
      unique(c(direct, children))
    }

    get_subtree <- function(df, node_id) {
      ids <- c(node_id, get_descendants(df, node_id))
      df[df$ID %in% ids, , drop = FALSE]
    }

    insert_subtree <- function(subtree, new_parent) {
      if (nrow(subtree) == 0) return(0)

      max_id <- DBI::dbGetQuery(con, "SELECT MAX(ID) AS max_id FROM Sample_Hierarchy")
      next_id <- if (is.na(max_id$max_id[1])) 1L else as.integer(max_id$max_id[1]) + 1L

      old_ids <- subtree$ID
      new_ids <- seq.int(next_id, length.out = length(old_ids))
      id_map <- setNames(new_ids, old_ids)

      order_ids <- unique(c(subtree$ID[is.na(subtree$Parent)], subtree$ID[!is.na(subtree$Parent)]))
      count <- 0

      for (old_id in order_ids) {
        row <- subtree[subtree$ID == old_id, , drop = FALSE][1, ]
        parent_old <- row$Parent

        if (is.na(parent_old)) {
          parent_new <- new_parent
        } else {
          parent_new <- id_map[[as.character(parent_old)]]
        }

        DBI::dbExecute(
          con,
          "INSERT INTO Sample_Hierarchy (ID, Name, Parent) VALUES (?, ?, ?)",
          list(id_map[[as.character(old_id)]], row$Name, parent_new)
        )
        count <- count + 1
      }

      count
    }

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

      tryCatch({
        count <- insert_subtree(rv$clipboard, parent_id)
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

      source <- DBI::dbGetQuery(con, sprintf("SELECT ID, Name, Parent FROM %s", table))
      if (nrow(source) == 0) {
        showNotification("Merge table has no rows.", type = "warning")
        return()
      }

      tryCatch({
        count <- insert_subtree(source, NA_integer_)
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
        DBI::dbExecute(
          con,
          "UPDATE Sample_Hierarchy SET Parent = ? WHERE ID = ?",
          list(parent_id, node_id)
        )
        showNotification("Node moved.", type = "message")
        refresh_tree()
        update_move_choices()
      }, error = function(e) {
        showNotification(paste("Move failed:", e$message), type = "error")
      })
    })

    observeEvent(input$su_add, {
      if (is.null(rv$su)) rv$su <- load_su()
      rv$su <- rbind(rv$su, data.frame(PlotNumber = "", SiteUnit = "", stringsAsFactors = FALSE))
    })

    observeEvent(input$su_delete, {
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
  })
}
