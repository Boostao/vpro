open_fs882_destination_context <- function(state,
                                           con,
                                           form_name = "FS882-6x4XL",
                                           close_forms = c("FS882-8x6XL", "FS882-1x1")) {
  state$CurrForm <- form_name
  state$sysCurrForm <- form_name
  set_pref(con, "Current", "DataFormName", form_name)
}

fs882_coerce_numeric <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value) || !nzchar(trimws(as.character(value)))) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(value))
}

fs882_coerce_int <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value) || !nzchar(trimws(as.character(value)))) {
    return(NA_integer_)
  }
  suppressWarnings(as.integer(value))
}

fs882_coerce_chr <- function(value) {
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    return(NA_character_)
  }
  text <- trimws(as.character(value))
  if (!nzchar(text)) NA_character_ else text
}

fs882_list_choices <- function(con, list_name) {
  sql <- paste(
    "SELECT item, itemdescription",
    "FROM lists.USysTableOfLists",
    "WHERE lower(listname) = lower(?)",
    "ORDER BY itemorder, item"
  )
  out <- tryCatch(DBI::dbGetQuery(con, sql, list(list_name)), error = function(e) data.frame())
  if (!nrow(out)) return(character(0))
  labels <- ifelse(
    is.na(out$itemdescription) | !nzchar(trimws(as.character(out$itemdescription))),
    out$item,
    paste0(out$item, " - ", out$itemdescription)
  )
  stats::setNames(as.character(out$item), labels)
}

fs882_upsert_env_header <- function(con, fields) {
  update_sql <- paste(
    "UPDATE Sample_Env SET",
    "fieldnumber=?, date=?, sitesurveyor=?, _location=?, latitude=?, longitude=?,",
    "utmeasting=?, utmnorthing=?, elevation=?, slopegradient=?, aspect=?,",
    "mesoslopeposition=?, surfaceshape=?, moistureregime=?, nutrientregime=?, sitenotes=?",
    "WHERE plotnumber=?"
  )

  n_updated <- DBI::dbExecute(con, update_sql, list(
    fields$fieldnumber,
    fields$date,
    fields$sitesurveyor,
    fields$`_location`,
    fields$latitude,
    fields$longitude,
    fields$utmeasting,
    fields$utmnorthing,
    fields$elevation,
    fields$slopegradient,
    fields$aspect,
    fields$mesoslopeposition,
    fields$surfaceshape,
    fields$moistureregime,
    fields$nutrientregime,
    fields$sitenotes,
    fields$plotnumber
  ))

  if (n_updated > 0) {
    return(invisible("updated"))
  }

  insert_sql <- paste(
    "INSERT INTO Sample_Env (",
    "plotnumber, fieldnumber, date, sitesurveyor, _location, latitude, longitude,",
    "utmeasting, utmnorthing, elevation, slopegradient, aspect,",
    "mesoslopeposition, surfaceshape, moistureregime, nutrientregime, sitenotes",
    ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  )

  DBI::dbExecute(con, insert_sql, list(
    fields$plotnumber,
    fields$fieldnumber,
    fields$date,
    fields$sitesurveyor,
    fields$`_location`,
    fields$latitude,
    fields$longitude,
    fields$utmeasting,
    fields$utmnorthing,
    fields$elevation,
    fields$slopegradient,
    fields$aspect,
    fields$mesoslopeposition,
    fields$surfaceshape,
    fields$moistureregime,
    fields$nutrientregime,
    fields$sitenotes
  ))

  invisible("inserted")
}

mod_fs882_6x4_ui <- function(id) {
  mod_fs882_6x4xl_ui(id)
}

mod_fs882_6x4_server <- function(id, state, con) {
  mod_fs882_6x4xl_server(id, state, con)
}

mod_fs882_6x4xl_ui <- function(id) {
  ns <- NS(id)

  tagList(
    card(
      full_screen = TRUE,
      card_header(
        "FS882-6x4XL",
        uiOutput(ns("fs882_context"))
      ),
      navset_card_tab(
        id = ns("fs882_tabs"),
        nav_panel(
          "Site",
          layout_columns(
            textInput(ns("PlotNumber"), "Plot Number"),
            textInput(ns("FieldNumber"), "Field No."),
            textInput(ns("Date"), "Date"),
            textInput(ns("SiteSurveyor"), "Surveyor"),
            col_widths = c(3, 3, 3, 3)
          ),
          layout_columns(
            textInput(ns("Location"), "General Location"),
            textInput(ns("UTMEasting"), "Easting"),
            textInput(ns("UTMNorthing"), "Northing"),
            col_widths = c(6, 3, 3)
          ),
          layout_columns(
            numericInput(ns("Latitude"), "Latitude", value = NA_real_),
            numericInput(ns("Longitude"), "Longitude", value = NA_real_),
            numericInput(ns("Elevation"), "Elevation (m)", value = NA_real_),
            numericInput(ns("SlopeGradient"), "Slope (%)", value = NA_real_),
            col_widths = c(3, 3, 3, 3)
          ),
          layout_columns(
            numericInput(ns("Aspect"), "Aspect", value = NA_real_),
            selectInput(ns("MesoSlopePosition"), "Meso Slope Pos.", choices = NULL),
            selectInput(ns("SurfaceShape"), "Surface Shape", choices = NULL),
            col_widths = c(3, 4, 5)
          ),
          layout_columns(
            selectInput(ns("MoistureRegime"), "Moisture Regime", choices = NULL),
            selectInput(ns("NutrientRegime"), "Nutrient Regime", choices = NULL),
            col_widths = c(6, 6)
          ),
          textAreaInput(ns("SiteNotes"), "Site Notes", width = "100%", height = "100px"),
          div(
            class = "d-flex gap-2",
            actionButton(ns("btnSaveRecord"), "Save", class = "btn-primary"),
            actionButton(ns("btnReloadRecord"), "Reload", class = "btn-outline-secondary"),
            actionButton(ns("btnG2MainMenu"), "Close", class = "btn-outline-danger")
          )
        ),
        nav_panel(
          "Vegetation",
          div(
            class = "d-flex gap-2 mb-2",
            actionButton(ns("btnAddVegRow"), "Add Species", class = "btn-primary"),
            actionButton(ns("btnDeleteVegRow"), "Delete Selected", class = "btn-danger"),
            actionButton(ns("btnSaveVeg"), "Save Vegetation", class = "btn-success")
          ),
          DT::DTOutput(ns("veg_table"))
        )
      )
    )
  )
}

mod_fs882_6x4xl_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    rv <- reactiveValues(
      veg = data.frame(),
      selected_row = NULL,
      current_plot = NULL
    )

    output$fs882_context <- renderUI({
      project_name <- state$CurrProject %||% state$PrefProject %||% "None"
      su_name <- state$PrefSUTable %||% "None"
      plot_name <- state$CurrSU %||% rv$current_plot %||% "None"
      tags$small(
        class = "text-muted",
        sprintf("Project: %s / SU Table: %s / Plot: %s", project_name, su_name, plot_name)
      )
    })

    observe({
      updateSelectInput(session, "MesoSlopePosition", choices = fs882_list_choices(con, "MesoSlopePosition"))
      updateSelectInput(session, "SurfaceShape", choices = fs882_list_choices(con, "SurfaceShape"))
      updateSelectInput(session, "MoistureRegime", choices = fs882_list_choices(con, "MoistureRegime"))
      updateSelectInput(session, "NutrientRegime", choices = fs882_list_choices(con, "NutrientRegime"))
    })

    load_plot_data <- function(plot_id) {
      if (is.null(plot_id) || !nzchar(trimws(as.character(plot_id)))) {
        return(invisible(NULL))
      }

      plot_id <- trimws(as.character(plot_id))
      rv$current_plot <- plot_id

      env_df <- DBI::dbGetQuery(con, "SELECT * FROM Sample_Env WHERE plotnumber = ?", list(plot_id))
      if (nrow(env_df) == 0) {
        env_df <- data.frame(
          plotnumber = plot_id,
          fieldnumber = NA_character_,
          date = NA_character_,
          sitesurveyor = NA_character_,
          `_location` = NA_character_,
          latitude = NA_real_,
          longitude = NA_real_,
          utmeasting = NA_real_,
          utmnorthing = NA_real_,
          elevation = NA_real_,
          slopegradient = NA_real_,
          aspect = NA_real_,
          mesoslopeposition = NA_character_,
          surfaceshape = NA_character_,
          moistureregime = NA_character_,
          nutrientregime = NA_character_,
          sitenotes = NA_character_
        )
      }

      env_row <- env_df[1, , drop = FALSE]
      updateTextInput(session, "PlotNumber", value = env_row$plotnumber %||% plot_id)
      updateTextInput(session, "FieldNumber", value = env_row$fieldnumber %||% "")
      updateTextInput(session, "Date", value = env_row$date %||% "")
      updateTextInput(session, "SiteSurveyor", value = env_row$sitesurveyor %||% "")
      updateTextInput(session, "Location", value = env_row$`_location` %||% "")
      updateNumericInput(session, "Latitude", value = env_row$latitude)
      updateNumericInput(session, "Longitude", value = env_row$longitude)
      updateTextInput(session, "UTMEasting", value = ifelse(is.na(env_row$utmeasting), "", as.character(env_row$utmeasting)))
      updateTextInput(session, "UTMNorthing", value = ifelse(is.na(env_row$utmnorthing), "", as.character(env_row$utmnorthing)))
      updateNumericInput(session, "Elevation", value = env_row$elevation)
      updateNumericInput(session, "SlopeGradient", value = env_row$slopegradient)
      updateNumericInput(session, "Aspect", value = env_row$aspect)
      updateSelectInput(session, "MesoSlopePosition", selected = env_row$mesoslopeposition %||% "")
      updateSelectInput(session, "SurfaceShape", selected = env_row$surfaceshape %||% "")
      updateSelectInput(session, "MoistureRegime", selected = env_row$moistureregime %||% "")
      updateSelectInput(session, "NutrientRegime", selected = env_row$nutrientregime %||% "")
      updateTextAreaInput(session, "SiteNotes", value = env_row$sitenotes %||% "")

      veg_df <- DBI::dbGetQuery(
        con,
        paste(
          "SELECT id, plotnumber, species, layer,",
          "cover1, cover2, cover3, cover4, cover5, cover6, cover7, cover8, cover9,",
          "totala, totalb, collected",
          "FROM Sample_Veg WHERE plotnumber = ? ORDER BY species, id"
        ),
        list(plot_id)
      )

      rv$veg <- veg_df
      state$CurrSU <- plot_id
      state$sysCurrSU <- plot_id
      set_pref(con, "Current", "CurrPlotNumber", plot_id)
    }

    observeEvent(state$CurrSU, {
      req(state$CurrSU)
      load_plot_data(state$CurrSU)
    }, ignoreInit = FALSE)

    observeEvent(input$btnReloadRecord, {
      load_plot_data(input$PlotNumber %||% state$CurrSU)
    })

    observeEvent(input$btnSaveRecord, {
      plot_id <- fs882_coerce_chr(input$PlotNumber)
      req(plot_id)

      fields <- list(
        plotnumber = plot_id,
        fieldnumber = fs882_coerce_chr(input$FieldNumber),
        date = fs882_coerce_chr(input$Date),
        sitesurveyor = fs882_coerce_chr(input$SiteSurveyor),
        `_location` = fs882_coerce_chr(input$Location),
        latitude = fs882_coerce_numeric(input$Latitude),
        longitude = fs882_coerce_numeric(input$Longitude),
        utmeasting = fs882_coerce_numeric(input$UTMEasting),
        utmnorthing = fs882_coerce_numeric(input$UTMNorthing),
        elevation = fs882_coerce_int(input$Elevation),
        slopegradient = fs882_coerce_numeric(input$SlopeGradient),
        aspect = fs882_coerce_int(input$Aspect),
        mesoslopeposition = fs882_coerce_chr(input$MesoSlopePosition),
        surfaceshape = fs882_coerce_chr(input$SurfaceShape),
        moistureregime = fs882_coerce_chr(input$MoistureRegime),
        nutrientregime = fs882_coerce_chr(input$NutrientRegime),
        sitenotes = fs882_coerce_chr(input$SiteNotes)
      )

      tryCatch({
        fs882_upsert_env_header(con, fields)
        state$CurrSU <- plot_id
        state$sysCurrSU <- plot_id
        set_pref(con, "Current", "CurrPlotNumber", plot_id)
        showNotification("FS882 header saved.", type = "message")
      }, error = function(e) {
        showNotification(paste("Save failed:", conditionMessage(e)), type = "error")
      })
    })

    output$veg_table <- DT::renderDT({
      DT::datatable(
        rv$veg,
        rownames = FALSE,
        selection = "single",
        editable = list(target = "cell", disable = list(columns = c(0, 1))),
        options = list(pageLength = 12, scrollX = TRUE)
      )
    })

    observeEvent(input$veg_table_rows_selected, {
      rv$selected_row <- input$veg_table_rows_selected
    })

    observeEvent(input$veg_table_cell_edit, {
      info <- input$veg_table_cell_edit
      req(nrow(rv$veg) > 0)
      row <- info$row
      col <- info$col + 1
      if (row > nrow(rv$veg) || col > ncol(rv$veg)) return()
      col_name <- names(rv$veg)[col]

      numeric_cols <- c("cover1", "cover2", "cover3", "cover4", "cover5", "cover6", "cover7", "cover8", "cover9", "totala", "totalb")
      if (col_name %in% numeric_cols) {
        rv$veg[row, col_name] <- fs882_coerce_numeric(info$value)
      } else {
        rv$veg[row, col_name] <- fs882_coerce_chr(info$value)
      }
    })

    observeEvent(input$btnAddVegRow, {
      plot_id <- fs882_coerce_chr(input$PlotNumber %||% state$CurrSU)
      req(plot_id)

      add_row <- data.frame(
        id = NA_integer_,
        plotnumber = plot_id,
        species = NA_character_,
        layer = NA_character_,
        cover1 = NA_real_,
        cover2 = NA_real_,
        cover3 = NA_real_,
        cover4 = NA_real_,
        cover5 = NA_real_,
        cover6 = NA_real_,
        cover7 = NA_real_,
        cover8 = NA_real_,
        cover9 = NA_real_,
        totala = NA_real_,
        totalb = NA_real_,
        collected = NA_character_
      )

      rv$veg <- rbind(rv$veg, add_row)
    })

    observeEvent(input$btnDeleteVegRow, {
      req(rv$selected_row)
      idx <- rv$selected_row
      if (length(idx) != 1 || idx < 1 || idx > nrow(rv$veg)) return()
      rv$veg <- rv$veg[-idx, , drop = FALSE]
      rv$selected_row <- NULL
    })

    observeEvent(input$btnSaveVeg, {
      plot_id <- fs882_coerce_chr(input$PlotNumber %||% state$CurrSU)
      req(plot_id)

      veg_df <- rv$veg
      if (!nrow(veg_df)) {
        DBI::dbExecute(con, "DELETE FROM Sample_Veg WHERE plotnumber = ?", list(plot_id))
        showNotification("Vegetation saved (no rows).", type = "message")
        return()
      }

      veg_df$plotnumber <- plot_id
      veg_df$species <- vapply(veg_df$species, fs882_coerce_chr, character(1))
      veg_df$layer <- vapply(veg_df$layer, fs882_coerce_chr, character(1))
      veg_df$collected <- vapply(veg_df$collected, fs882_coerce_chr, character(1))

      numeric_cols <- c("cover1", "cover2", "cover3", "cover4", "cover5", "cover6", "cover7", "cover8", "cover9", "totala", "totalb")
      for (col_name in numeric_cols) {
        veg_df[[col_name]] <- vapply(veg_df[[col_name]], fs882_coerce_numeric, numeric(1))
      }

      tryCatch({
        DBI::dbExecute(con, "BEGIN TRANSACTION")
        on.exit(DBI::dbExecute(con, "ROLLBACK"), add = TRUE)

        existing_max <- DBI::dbGetQuery(con, "SELECT COALESCE(MAX(id), 0) AS max_id FROM Sample_Veg")$max_id[[1]]
        next_id <- as.integer(existing_max)

        for (row_idx in seq_len(nrow(veg_df))) {
          if (is.na(veg_df$id[row_idx])) {
            next_id <- next_id + 1L
            veg_df$id[row_idx] <- next_id
          }
        }

        DBI::dbExecute(con, "DELETE FROM Sample_Veg WHERE plotnumber = ?", list(plot_id))

        insert_sql <- paste(
          "INSERT INTO Sample_Veg (",
          "id, plotnumber, species, layer,",
          "cover1, cover2, cover3, cover4, cover5, cover6, cover7, cover8, cover9,",
          "totala, totalb, collected",
          ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        )

        for (row_idx in seq_len(nrow(veg_df))) {
          DBI::dbExecute(con, insert_sql, list(
            as.integer(veg_df$id[row_idx]),
            veg_df$plotnumber[row_idx],
            veg_df$species[row_idx],
            veg_df$layer[row_idx],
            veg_df$cover1[row_idx],
            veg_df$cover2[row_idx],
            veg_df$cover3[row_idx],
            veg_df$cover4[row_idx],
            veg_df$cover5[row_idx],
            veg_df$cover6[row_idx],
            veg_df$cover7[row_idx],
            veg_df$cover8[row_idx],
            veg_df$cover9[row_idx],
            veg_df$totala[row_idx],
            veg_df$totalb[row_idx],
            veg_df$collected[row_idx]
          ))
        }

        DBI::dbExecute(con, "COMMIT")
        on.exit(NULL, add = FALSE)
        rv$veg <- DBI::dbGetQuery(
          con,
          paste(
            "SELECT id, plotnumber, species, layer,",
            "cover1, cover2, cover3, cover4, cover5, cover6, cover7, cover8, cover9,",
            "totala, totalb, collected",
            "FROM Sample_Veg WHERE plotnumber = ? ORDER BY species, id"
          ),
          list(plot_id)
        )
        showNotification("Vegetation saved.", type = "message")
      }, error = function(e) {
        showNotification(paste("Vegetation save failed:", conditionMessage(e)), type = "error")
      })
    })

    observeEvent(input$btnG2MainMenu, {
      bslib::nav_select("main_tabs", "Vegetation", session = session$parent)
    })
  })
}
