# =============================================================================
# mod_admin_publishing.R — Publishing + Download Logs sub-module
# Helper functions publish_panel_ui / download_panel_ui are defined here.
# =============================================================================

publish_panel_ui <- function(ns) {
  layout_sidebar(
    sidebar = sidebar(
      textInput(ns("publish_out_dir"), "Output dir", value = "data/published"),
      selectInput(ns("publish_projects"), "Projects", choices = NULL, multiple = TRUE),
      checkboxGroupInput(
        ns("publish_formats"), "Formats",
        choices  = c("RDS" = "rds", "CSV" = "csv", "XLSX" = "xlsx"),
        selected = c("rds")
      ),
      checkboxInput(ns("publish_lump"),      "Apply species lumping",         value = TRUE),
      checkboxInput(ns("publish_is_public"), "Public dataset (BEC Map)",      value = TRUE),
      actionButton(ns("publish_run"),     "Publish Project Dataset",          class = "btn-primary w-100 mt-2"),
      actionButton(ns("publish_refresh"), "Refresh Published List",           class = "btn-outline-secondary w-100 mt-2")
    ),
    card(
      card_header("Project Publishing (BEC Map Explorer)"),
      card_body(
        textOutput(ns("publish_status")),
        tableOutput(ns("publish_snapshots"))
      )
    )
  )
}

download_panel_ui <- function(ns) {
  layout_sidebar(
    sidebar = sidebar(
      textInput(  ns("download_user"),    "User",    value = ""),
      textInput(  ns("download_dataset"), "Dataset", value = ""),
      selectInput(ns("download_format"),  "Format",
                  choices = c("All" = "", "rds", "csv", "excel", "xml"), selected = ""),
      selectInput(ns("download_status"),  "Status",
                  choices = c("All" = "", "success", "failed"), selected = ""),
      dateInput(ns("download_from"), "From", value = NULL),
      dateInput(ns("download_to"),   "To",   value = NULL),
      actionButton(  ns("download_refresh"), "Refresh",    class = "btn-secondary w-100 mt-2"),
      downloadButton(ns("download_export"), "Export CSV",  class = "btn-outline-primary w-100 mt-2")
    ),
    card(
      card_header("Download Log"),
      card_body(
        textOutput(ns("download_status_text")),
        DTOutput(ns("download_dt"))
      )
    )
  )
}

mod_admin_publishing_ui <- function(id) {
  ns <- NS(id)
  navset_card_tab(
    nav_panel("Publishing",     uiOutput(ns("publish_panel"))),
    nav_panel("Download Logs",  uiOutput(ns("download_panel")))
  )
}

mod_admin_publishing_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    require_permission <- function(permission) {
      if (!auth_is_authenticated(state)) {
        show_toast(toast("Sign in required.", type = "danger"))
        return(FALSE)
      }
      if (!auth_user_has_permission(state, permission)) {
        show_toast(toast(paste("Permission required:", permission), type = "danger"))
        return(FALSE)
      }
      TRUE
    }

    # ------------------------------------------------------------------
    # Conditional panel rendering
    # ------------------------------------------------------------------

    output$publish_panel <- renderUI({
      if (!auth_is_authenticated(state) || !auth_user_has_permission(state, "publish_rds")) {
        return(card(card_header("Project Publishing"),
                    card_body("Sign in with publish permissions to access this panel.")))
      }
      publish_panel_ui(ns)
    })

    output$download_panel <- renderUI({
      if (!auth_is_authenticated(state) || !auth_user_has_permission(state, "view_download_logs")) {
        return(card(card_header("Download Log"),
                    card_body("Sign in with download log permissions to access this panel.")))
      }
      download_panel_ui(ns)
    })

    # ------------------------------------------------------------------
    # Publishing
    # ------------------------------------------------------------------

    publish_status    <- reactiveVal("")
    publish_snapshots <- reactiveVal(data.frame())

    observe({
      if (!auth_is_authenticated(state) || !auth_user_has_permission(state, "publish_rds")) return()
      if (is.null(input$publish_projects)) return()
      projects <- tryCatch({
        dbGetQuery(con, "SELECT projectid, projecttitle FROM USysProjectMetadata ORDER BY projectid")
      }, error = function(e) data.frame())
      if (nrow(projects) > 0) {
        updateSelectInput(session, "publish_projects",
                          choices = setNames(projects$projectid,
                                            paste(projects$projectid, "-", projects$projecttitle)))
      }
    })

    refresh_publish_snapshots <- function() {
      out_dir  <- trimws(input$publish_out_dir %||% "")
      if (!nzchar(out_dir)) out_dir <- "data/published"
      reg_path <- file.path(out_dir, "publication_registry.csv")
      if (!file.exists(reg_path)) {
        publish_snapshots(data.frame())
        publish_status("No publication registry found yet.")
        return(invisible(NULL))
      }
      snaps <- tryCatch(utils::read.csv(reg_path, stringsAsFactors = FALSE), error = function(e) NULL)
      if (is.null(snaps) || nrow(snaps) == 0) {
        publish_snapshots(data.frame())
        publish_status("Publication registry is empty.")
        return(invisible(NULL))
      }
      snaps <- snaps[order(snaps$timestamp_utc, decreasing = TRUE), , drop = FALSE]
      publish_snapshots(utils::head(snaps, 25))
      publish_status("")
    }

    observeEvent(input$publish_refresh, { refresh_publish_snapshots() })

    observeEvent(input$publish_run, {
      if (!require_permission("publish_rds")) return()
      out_dir     <- trimws(input$publish_out_dir %||% "")
      if (!nzchar(out_dir)) out_dir <- "data/published"
      project_ids <- input$publish_projects %||% character(0)
      if (length(project_ids) == 0) {
        show_toast(toast("Select one or more projects to publish.", type = "warning"))
        return()
      }
      formats <- input$publish_formats %||% character(0)
      if (length(formats) == 0) {
        show_toast(toast("Select at least one output format.", type = "warning"))
        return()
      }
      tryCatch({
        source("R/logic_publish.R", local = TRUE)
        results <- publish_project_dataset(
          project_id    = project_ids,
          output_dir    = out_dir,
          formats       = formats,
          apply_lumping = isTRUE(input$publish_lump),
          con           = con,
          is_public     = isTRUE(input$publish_is_public)
        )
        if (is.list(results) && !is.null(results$project_id)) {
          publish_status(paste("Published", results$project_id,
                               "(env", results$env_rows, "veg", results$veg_rows, ")"))
        } else {
          publish_status(paste("Published", length(results), "projects"))
        }
        show_toast(toast("Project dataset published.", type = "success"))
        refresh_publish_snapshots()
      }, error = function(e) {
        publish_status("")
        show_toast(toast(paste("Publish failed:", e$message), type = "danger"))
      })
    })

    output$publish_status <- renderText({ publish_status() })

    output$publish_snapshots <- renderTable({ publish_snapshots() })

    # ------------------------------------------------------------------
    # Download Log
    # ------------------------------------------------------------------

    download_status <- reactiveVal("")
    download_log    <- reactiveVal(data.frame())

    refresh_download_log <- function() {
      if (!require_permission("view_download_logs")) {
        download_log(data.frame())
        download_status("Permission required: view_download_logs")
        return()
      }
      tryCatch({
        sync_require_cloud(con, allow_attach = TRUE)
        query <- build_download_log_query(
          filters = list(
            user    = trimws(input$download_user),
            dataset = trimws(input$download_dataset),
            format  = input$download_format,
            status  = input$download_status,
            from    = if (!is.null(input$download_from)) as.POSIXct(input$download_from) else NULL,
            to      = if (!is.null(input$download_to))   as.POSIXct(input$download_to) + 86400 else NULL
          ),
          limit = 1000L
        )
        rows <- dbGetQuery(con, query$sql, query$params)
        download_log(rows)
        download_status("")
      }, error = function(e) {
        download_log(data.frame())
        download_status(paste("Download log unavailable:", e$message))
      })
    }

    observeEvent(input$download_refresh, { refresh_download_log() })

    output$download_status_text <- renderText({ download_status() })

    output$download_dt <- renderDT({
      datatable(download_log(), options = list(pageLength = 25, order = list(list(0, "desc"))))
    })

    output$download_export <- downloadHandler(
      filename = function() paste0("download_log_", Sys.Date(), ".csv"),
      content  = function(file) {
        if (!require_permission("view_download_logs")) stop("Permission required: view_download_logs")
        write.csv(download_log(), file, row.names = FALSE)
      }
    )
  })
}
