# Module: Colour-theme
# Access parity: frmColourMaster (no exported form — behaviour reconstructed from
# USysComboColourTheme in VUser.db, Sample_Theme in project, and USysThemeTable
# in VPro64.db).
#
# The colour-theme form lets users view and edit the mapping between lump group
# codes and their colour/pattern attributes used in thematic reports.

mod_colour_theme_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    class = "h-100",
    full_screen = TRUE,
    bslib::card_header(
      shiny::tags$div(
        class = "d-flex justify-content-between align-items-center",
        shiny::tags$div(class = "fw-semibold", "Colour-theme"),
        shiny::tags$div(
          class = "d-flex gap-2",
          shiny::actionButton(ns("btnRefresh"), "Refresh", class = "btn btn-outline-secondary btn-sm"),
          shiny::actionButton(ns("btnSave"), "Save", class = "btn btn-primary btn-sm")
        )
      )
    ),
    bslib::card_body(
      shiny::tags$p(
        class = "text-muted small mb-3",
        "Manage theme colours related to combined species groups.",
        "Changes are written back to the project theme table."
      ),
      rhandsontable::rHandsontableOutput(ns("theme_table"), height = "500px"),
      shiny::textOutput(ns("status"))
    )
  )
}

mod_colour_theme_server <- function(id, state, con) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    status_text <- shiny::reactiveVal("")

    theme_data <- shiny::reactiveVal(data.frame())

    load_theme <- function() {
      current_project <- trimws(state$CurrProject %||% config("Current", "CurrProject") %||% "Sample")
      table_name <- paste0(current_project, "_Theme")
      tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
      match_hit <- tables[tolower(tables) == tolower(table_name)]
      if (length(match_hit) == 0) {
        status_text(sprintf("Theme table '%s' not found in current project.", table_name))
        theme_data(data.frame(
          LumpCode = character(), SppCode = character(), ScientificName = character(),
          ColourCode = integer(), PatternCode = integer(), FontColour = integer(),
          Use = integer(), stringsAsFactors = FALSE
        ))
        return(invisible(NULL))
      }
      quoted <- DBI::dbQuoteIdentifier(con, match_hit[[1]])
      df <- tryCatch(
        DBI::dbGetQuery(con, paste("SELECT * FROM", as.character(quoted))),
        error = function(e) {
          status_text(paste("Error loading theme:", conditionMessage(e)))
          data.frame()
        }
      )
      theme_data(df)
      status_text(sprintf("Loaded %d theme rows from %s.", nrow(df), match_hit[[1]]))
    }

    observeEvent(TRUE, { load_theme() }, once = TRUE)
    observeEvent(input$btnRefresh, { load_theme() })
    observeEvent(state$CurrProject, { load_theme() }, ignoreInit = TRUE)

    output$theme_table <- rhandsontable::renderRHandsontable({
      df <- theme_data()
      if (!nrow(df)) return(NULL)
      rhandsontable::rhandsontable(df, stretchH = "all", rowHeaders = FALSE) |>
        rhandsontable::hot_col("LumpCode", readOnly = TRUE) |>
        rhandsontable::hot_col("SppCode", readOnly = TRUE) |>
        rhandsontable::hot_col("ScientificName", readOnly = TRUE)
    })

    observeEvent(input$btnSave, {
      hot <- input$theme_table
      if (is.null(hot)) {
        status_text("No data to save.")
        return()
      }
      df <- rhandsontable::hot_to_r(hot)
      current_project <- trimws(state$CurrProject %||% config("Current", "CurrProject") %||% "Sample")
      table_name <- paste0(current_project, "_Theme")
      tables <- tryCatch(DBI::dbListTables(con), error = function(e) character(0))
      match_hit <- tables[tolower(tables) == tolower(table_name)]
      if (length(match_hit) == 0) {
        status_text("Theme table not found — cannot save.")
        return()
      }
      quoted <- as.character(DBI::dbQuoteIdentifier(con, match_hit[[1]]))
      tryCatch({
        DBI::dbExecute(con, paste("DELETE FROM", quoted))
        DBI::dbAppendTable(con, match_hit[[1]], df)
        status_text(sprintf("Saved %d rows to %s.", nrow(df), match_hit[[1]]))
      }, error = function(e) {
        status_text(paste("Save error:", conditionMessage(e)))
      })
    })

    output$status <- shiny::renderText(status_text())
  })
}
