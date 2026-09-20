# =============================================================================
# mod_admin_codes.R — Code Maintenance sub-module
# =============================================================================

mod_admin_codes_ui <- function(id) {
  ns <- NS(id)
  layout_sidebar(
    sidebar = sidebar(
      selectInput(ns("code_list_select"), "Select Lookup List", choices = NULL),
      actionButton(ns("code_refresh"), "Refresh Lists", class = "btn-secondary w-100 mt-2")
    ),
    card(
      card_header(textOutput(ns("code_list_header"))),
      card_body(
        DTOutput(ns("code_dt")),
        div(class = "mt-3 d-flex gap-2",
            actionButton(ns("code_add_row"), "Add Row", class = "btn-info"),
            actionButton(ns("code_save"), "Save All Item Changes", class = "btn-warning")
        ),
        helpText("Double-click cells to edit. Added rows appear at bottom. 'Save' overwrites the list in DB.")
      )
    )
  )
}

mod_admin_codes_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {

    require_permission <- function(permissions, message) {
      if (!auth_is_authenticated(state)) {
        show_toast(toast("Sign in required.", type = "danger"))
        return(FALSE)
      }
      if (!any(vapply(permissions, function(p) auth_user_has_permission(state, p), logical(1)))) {
        show_toast(toast(message, type = "danger"))
        return(FALSE)
      }
      TRUE
    }

    rv_codes <- reactiveValues(data = NULL)

    observe({
      tryCatch({
        lists <- dbGetQuery(con, "SELECT DISTINCT listname FROM VLists.USysTableOfLists ORDER BY listname")
        updateSelectInput(session, "code_list_select", choices = lists$listname)
      }, error = function(e) {
        print(e)
      })
    })

    observeEvent(input$code_list_select, {
      req(input$code_list_select)
      df <- dbGetQuery(con,
        "SELECT item, itemdescription, itemorder FROM VLists.USysTableOfLists WHERE listname = ? ORDER BY itemorder",
        list(input$code_list_select))
      rv_codes$data <- df
      output$code_list_header <- renderText(paste("List:", input$code_list_select))
    })

    output$code_dt <- renderDT({
      req(rv_codes$data)
      datatable(rv_codes$data,
                editable = 'cell',
                selection = 'none',
                options = list(pageLength = 15, dom = 't,p'))
    })

    observeEvent(input$code_dt_cell_edit, {
      info <- input$code_dt_cell_edit
      i <- info$row
      j <- info$col + 1
      v <- info$value
      rv_codes$data[i, j] <- DT::coerceValue(v, rv_codes$data[i, j])
    })

    observeEvent(input$code_add_row, {
      req(rv_codes$data)
      if (!require_permission(c("manage:codes", "write:all"), "Permission required: manage codes")) return()
      new_row <- data.frame(
        item            = "NEW_CODE",
        itemdescription = "New Description",
        itemorder       = 0,
        stringsAsFactors = FALSE
      )
      rv_codes$data <- rbind(rv_codes$data, new_row)
    })

    observeEvent(input$code_save, {
      req(input$code_list_select)
      req(rv_codes$data)
      if (!require_permission(c("manage:codes", "write:all"), "Permission required: manage codes")) return()
      lname    <- input$code_list_select
      old_rows <- dbGetQuery(con,
        "SELECT item, itemdescription, itemorder FROM VLists.USysTableOfLists WHERE listname = ?",
        list(lname))
      dbBegin(con)
      tryCatch({
        dbExecute(con, "DELETE FROM VLists.USysTableOfLists WHERE listname = ?", list(lname))
        to_save           <- rv_codes$data
        to_save$listname  <- lname
        sql <- "INSERT INTO VLists.USysTableOfLists (listname, item, itemdescription, itemorder) VALUES (?, ?, ?, ?)"
        for (i in seq_len(nrow(to_save))) {
          dbExecute(con, sql,
            list(to_save$listname[i], to_save$item[i], to_save$itemdescription[i], as.numeric(to_save$itemorder[i])))
        }
        dbCommit(con)
        show_toast(toast("List saved successfully.", type = "success"))

        if (nrow(to_save) > 0 || nrow(old_rows) > 0) {
          old_map       <- if (nrow(old_rows) > 0) split(old_rows, old_rows$item) else list()
          new_map       <- if (nrow(to_save) > 0)  split(to_save,  to_save$item)  else list()
          removed_items <- setdiff(names(old_map), names(new_map))
          added_items   <- setdiff(names(new_map), names(old_map))
          common_items  <- intersect(names(old_map), names(new_map))

          for (item_key in removed_items) {
            row <- old_map[[item_key]][1, , drop = FALSE]
            log_audit_change(con, NA, "Admin", lname, "VLists.USysTableOfLists", "item",            row$item,            NA)
            log_audit_change(con, NA, "Admin", lname, "VLists.USysTableOfLists", "itemdescription", row$itemdescription, NA)
            log_audit_change(con, NA, "Admin", lname, "VLists.USysTableOfLists", "itemorder",       row$itemorder,       NA)
          }
          for (item_key in added_items) {
            row <- new_map[[item_key]][1, , drop = FALSE]
            log_audit_change(con, NA, "Admin", lname, "VLists.USysTableOfLists", "item",            NA, row$item)
            log_audit_change(con, NA, "Admin", lname, "VLists.USysTableOfLists", "itemdescription", NA, row$itemdescription)
            log_audit_change(con, NA, "Admin", lname, "VLists.USysTableOfLists", "itemorder",       NA, row$itemorder)
          }
          for (item_key in common_items) {
            old_row <- old_map[[item_key]][1, , drop = FALSE]
            new_row <- new_map[[item_key]][1, , drop = FALSE]
            log_audit_change(con, NA, "Admin", lname, "VLists.USysTableOfLists", "itemdescription", old_row$itemdescription, new_row$itemdescription)
            log_audit_change(con, NA, "Admin", lname, "VLists.USysTableOfLists", "itemorder",       old_row$itemorder,       new_row$itemorder)
          }
        }
      }, error = function(e) {
        dbRollback(con)
        show_toast(toast(paste("Save failed:", e$message), type = "danger"))
      })
    })
  })
}
