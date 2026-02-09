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
      layout_columns(
        textInput(ns("hier_name"), "Name"),
        actionButton(ns("hier_add"), "Add Node", class = "btn-primary"),
        actionButton(ns("hier_rename"), "Rename", class = "btn-warning"),
        actionButton(ns("hier_delete"), "Delete", class = "btn-danger"),
        actionButton(ns("hier_refresh"), "Refresh", class = "btn-secondary"),
        col_widths = c(4, 2, 2, 2, 2)
      ),
      shinyTree::shinyTreeOutput(ns("hier_tree"), height = "600px"),
      verbatimTextOutput(ns("hier_status"))
    )
  )
}

mod_hierarchy_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(data = NULL)

    load_hierarchy <- function() {
      if (!DBI::dbExistsTable(con, "Sample_Hierarchy")) return(data.frame())
      DBI::dbGetQuery(con, "SELECT ID, Name, Parent FROM Sample_Hierarchy ORDER BY Name")
    }

    refresh_tree <- function() {
      rv$data <- load_hierarchy()
    }

    observeEvent(state$CurrProject, {
      refresh_tree()
    }, ignoreInit = TRUE)

    observeEvent(input$hier_refresh, {
      refresh_tree()
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
      }, error = function(e) {
        showNotification(paste("Delete failed:", e$message), type = "error")
      })
    })
  })
}
