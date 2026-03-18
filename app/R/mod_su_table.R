mod_su_table_ui <- function(id) {
  ns <- NS(id)
  bslib::card(
    full_screen = TRUE,
    class = "h-100",
    bslib::card_header(
      div(class = "d-flex justify-content-between align-items-center gap-3",
        div(
          div(class = "fw-semibold", "Site Unit Table"),
          div(class = "small text-muted", "Live SU rows for the current project. Use this page to verify drag-based plot reassignment.")
        ),
        actionButton(ns("refresh"), "Refresh", class = "btn btn-outline-secondary btn-sm")
      )
    ),
    bslib::card_body(
      div(class = "small text-muted mb-2", textOutput(ns("summary"))),
      DT::DTOutput(ns("table"))
    )
  )
}

mod_su_table_server <- function(id, state, con, refresh_trigger = reactive(NULL), active_tab = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    refresh_nonce <- reactiveVal(0L)

    load_su_table <- reactive({
      refresh_trigger()
      refresh_nonce()
      active_tab()

      project_id <- trimws(as.character(state$CurrProject %||% state$PrefProject %||% ""))
      if (!nzchar(project_id)) {
        return(data.frame(
          PlotNumber = character(0),
          SiteUnit = character(0),
          LocalModifiedUTC = character(0),
          stringsAsFactors = FALSE
        ))
      }

      scope <- read_project_site_unit_scope(con, project_id)
      if (nrow(scope) == 0) {
        return(data.frame(
          PlotNumber = character(0),
          SiteUnit = character(0),
          LocalModifiedUTC = character(0),
          stringsAsFactors = FALSE
        ))
      }

      su_fields <- tryCatch(DBI::dbListFields(con, "SU"), error = function(e) character(0))
      su_plot_col <- hierarchy_sidebar_match_col(su_fields, c("PlotNumber", "plotnumber"))
      su_site_col <- hierarchy_sidebar_match_col(su_fields, c("SiteUnit", "siteunit"))
      su_modified_col <- hierarchy_sidebar_match_col(su_fields, c("local_modified_utc"))

      if (any(is.na(c(su_plot_col, su_site_col)))) {
        return(data.frame(
          PlotNumber = character(0),
          SiteUnit = character(0),
          LocalModifiedUTC = character(0),
          stringsAsFactors = FALSE
        ))
      }

      plot_ids <- unique(as.character(scope$plotnumber))
      placeholders <- paste(rep("?", length(plot_ids)), collapse = ", ")
      modified_select <- if (!is.na(su_modified_col)) {
        sprintf("CAST(%s AS VARCHAR) AS LocalModifiedUTC", hierarchy_sidebar_quote(con, su_modified_col))
      } else {
        "NULL AS LocalModifiedUTC"
      }

      sql <- sprintf(
        paste(
          "SELECT",
          "%s AS PlotNumber,",
          "%s AS SiteUnit,",
          "%s",
          "FROM %s",
          "WHERE %s IN (%s)",
          "ORDER BY %s, %s"
        ),
        hierarchy_sidebar_quote(con, su_plot_col),
        hierarchy_sidebar_quote(con, su_site_col),
        modified_select,
        hierarchy_sidebar_quote(con, "SU"),
        hierarchy_sidebar_quote(con, su_plot_col),
        placeholders,
        hierarchy_sidebar_quote(con, su_site_col),
        hierarchy_sidebar_quote(con, su_plot_col)
      )

      out <- tryCatch(
        DBI::dbGetQuery(con, sql, as.list(plot_ids)),
        error = function(e) data.frame(
          PlotNumber = character(0),
          SiteUnit = character(0),
          LocalModifiedUTC = character(0),
          stringsAsFactors = FALSE
        )
      )

      out$PlotNumber <- as.character(out$PlotNumber)
      out$SiteUnit <- as.character(out$SiteUnit)
      out$LocalModifiedUTC <- as.character(out$LocalModifiedUTC %||% "")
      out
    })

    observeEvent(input$refresh, {
      refresh_nonce(isolate(refresh_nonce()) + 1L)
    })

    output$summary <- renderText({
      rows <- load_su_table()
      project_id <- trimws(as.character(state$CurrProject %||% state$PrefProject %||% ""))
      sprintf("Project: %s | Rows: %d | Current plot: %s", if (nzchar(project_id)) project_id else "None", nrow(rows), trimws(as.character(state$CurrSU %||% "None")))
    })

    output$table <- DT::renderDT({
      rows <- load_su_table()
      DT::datatable(
        rows,
        rownames = FALSE,
        filter = "top",
        class = "compact stripe hover",
        selection = "single",
        options = list(
          pageLength = 20,
          autoWidth = TRUE,
          scrollX = TRUE,
          order = list(list(1, "asc"), list(0, "asc"))
        )
      )
    })

    invisible(list(
      refresh = function() refresh_nonce(isolate(refresh_nonce()) + 1L),
      data = load_su_table
    ))
  })
}