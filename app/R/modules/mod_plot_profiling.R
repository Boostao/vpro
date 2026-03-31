# Plot Profiling Module
# Port of Access USysPlotProfiling / V7mdlPlotProfiling
#
# Opens as a modal from FS882 form. Allows the user to define
# profile criteria (species, layer, cover, env field) and run the
# profile to filter plots matching all criteria.

mod_plot_profiling_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(
      col_widths = c(8, 4),

      # Left: profile criteria grid
      card(
        card_header("Profile Criteria"),
        card_body(
          rhandsontable::rHandsontableOutput(ns("hot_profile")),
          div(
            class = "d-flex gap-2 mt-2",
            actionButton(ns("btnAddRow"), "Add Row", class = "btn btn-outline-primary btn-sm"),
            actionButton(ns("btnRemoveRow"), "Remove Last Row", class = "btn btn-outline-danger btn-sm"),
            actionButton(ns("btnClearAll"), "Clear All", class = "btn btn-outline-secondary btn-sm")
          )
        )
      ),

      # Right: run + results
      card(
        card_header("Results"),
        card_body(
          div(
            class = "d-flex gap-2 mb-3",
            actionButton(ns("btnRunProfile"), "Run Profile", class = "btn btn-primary btn-sm"),
            actionButton(ns("btnApplyFilter"), "Apply to SU Table", class = "btn btn-outline-success btn-sm")
          ),
          div(class = "mb-2",
            textOutput(ns("lblTotalPlots")),
            textOutput(ns("lblFilteredPlots"))
          ),
          DT::DTOutput(ns("dt_results"))
        )
      )
    )
  )
}

mod_plot_profiling_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Reactive store for profile criteria and results
    rv <- reactiveValues(
      criteria = data.frame(
        Table = character(0),
        Field = character(0),
        Operator = character(0),
        Layer = character(0),
        Species = character(0),
        Value = character(0),
        Operation = character(0),
        stringsAsFactors = FALSE
      ),
      result_plots = character(0)
    )

    # Initialise with one blank row
    observe({
      if (!nrow(rv$criteria)) {
        rv$criteria <- data.frame(
          Table = "Veg", Field = "Species", Operator = ">=",
          Layer = "Any", Species = "", Value = "1",
          Operation = "Add Plots",
          stringsAsFactors = FALSE
        )
      }
    }) |> bindEvent(TRUE, once = TRUE)

    output$hot_profile <- rhandsontable::renderRHandsontable({
      df <- rv$criteria
      hot <- rhandsontable::rhandsontable(df, rowHeaders = FALSE, stretchH = "all")
      hot <- rhandsontable::hot_col(hot, "Table",
        type = "dropdown", source = c("Veg", "Env"))
      hot <- rhandsontable::hot_col(hot, "Field",
        type = "dropdown", source = c("Species", "Cover", "Zone", "SubZone",
          "MoistureRegime", "NutrientRegime", "Elevation", "Aspect",
          "SlopeGradient", "StructuralStage", "Ecosection"))
      hot <- rhandsontable::hot_col(hot, "Operator",
        type = "dropdown", source = c(">=", ">", "=", "<=", "<", "<>", "Like"))
      hot <- rhandsontable::hot_col(hot, "Layer",
        type = "dropdown", source = c("Any", "All", "SumAll", "A1", "A2", "A3",
          "B1", "B2", "C", "D"))
      hot <- rhandsontable::hot_col(hot, "Operation",
        type = "dropdown", source = c("Add Plots", "Remove Plots"))
      hot
    })

    observeEvent(input$btnAddRow, {
      rv$criteria <- rbind(rv$criteria, data.frame(
        Table = "Veg", Field = "Species", Operator = ">=",
        Layer = "Any", Species = "", Value = "1",
        Operation = "Add Plots",
        stringsAsFactors = FALSE
      ))
    })

    observeEvent(input$btnRemoveRow, {
      n <- nrow(rv$criteria)
      if (n > 0) rv$criteria <- rv$criteria[-n, , drop = FALSE]
    })

    observeEvent(input$btnClearAll, {
      rv$criteria <- data.frame(
        Table = character(0), Field = character(0), Operator = character(0),
        Layer = character(0), Species = character(0), Value = character(0),
        Operation = character(0), stringsAsFactors = FALSE
      )
      rv$result_plots <- character(0)
    })

    # Total plots in project
    output$lblTotalPlots <- renderText({
      env_tbl <- as.character(db_tb(con, "Env", config("Current", "CurrProject"), prj = TRUE))
      n <- tryCatch(
        db_query(con, paste("SELECT COUNT(*) AS n FROM", env_tbl))$n[1],
        error = function(e) 0
      )
      paste("Project plots:", n)
    })

    output$lblFilteredPlots <- renderText({
      paste("Filtered plots:", length(rv$result_plots))
    })

    # Run profile
    observeEvent(input$btnRunProfile, {
      hot_data <- rhandsontable::hot_to_r(input$hot_profile)
      if (is.null(hot_data) || !nrow(hot_data)) {
        showNotification("Add profile criteria first.", type = "warning")
        return()
      }
      rv$criteria <- hot_data

      project <- config("Current", "CurrProject")
      env_tbl <- as.character(db_tb(con, "Env", project, prj = TRUE))
      veg_tbl <- as.character(db_tb(con, "Veg", project, prj = TRUE))

      matched <- NULL  # NULL = not yet filtered; character(0) = empty

      for (i in seq_len(nrow(hot_data))) {
        row <- hot_data[i, ]
        tbl_type  <- trimws(row$Table)
        field     <- trimws(row$Field)
        op_str    <- trimws(row$Operator)
        layer     <- trimws(row$Layer)
        spp       <- trimws(row$Species)
        val       <- trimws(row$Value)
        operation <- trimws(row$Operation)

        if (!nzchar(val) && !nzchar(spp)) next

        # Validate operator
        valid_ops <- c(">=", ">", "=", "<=", "<", "<>", "Like")
        if (!op_str %in% valid_ops) {
          showNotification(paste("Row", i, ": invalid operator", op_str), type = "warning")
          next
        }

        step_plots <- tryCatch({
          if (tbl_type == "Veg") {
            profile_veg_step(con, env_tbl, veg_tbl, spp, layer, op_str, val)
          } else {
            profile_env_step(con, env_tbl, field, op_str, val)
          }
        }, error = function(e) {
          showNotification(paste("Row", i, "error:", conditionMessage(e)), type = "error")
          character(0)
        })

        if (operation == "Add Plots") {
          if (is.null(matched)) {
            matched <- step_plots
          } else {
            matched <- union(matched, step_plots)
          }
        } else {
          # Remove Plots
          if (!is.null(matched)) {
            matched <- setdiff(matched, step_plots)
          }
        }
      }

      rv$result_plots <- if (is.null(matched)) character(0) else matched
      showNotification(paste(length(rv$result_plots), "plots matched."), type = "message")
    })

    # Results grid
    output$dt_results <- DT::renderDT({
      plots <- rv$result_plots
      if (!length(plots)) {
        return(DT::datatable(data.frame(Message = "No matching plots"), rownames = FALSE))
      }
      DT::datatable(
        data.frame(PlotNumber = plots, stringsAsFactors = FALSE),
        rownames = FALSE, selection = "multiple",
        options = list(pageLength = 50, dom = "tp")
      )
    })

    # Apply filtered plots to SU table
    observeEvent(input$btnApplyFilter, {
      plots <- rv$result_plots
      if (!length(plots)) {
        showNotification("Run the profile first to get matching plots.", type = "warning")
        return()
      }
      showModal(modalDialog(
        title = "Create SU From Filter",
        radioButtons(ns("filter_action"), "Action",
          choices = c("Create new SU table" = "create",
                      "Modify current SU table" = "modify",
                      "Append to current SU table" = "append"),
          selected = "create"
        ),
        conditionalPanel(
          sprintf("input['%s'] == 'create'", ns("filter_action")),
          textInput(ns("filter_new_name"), "New SU Table Name")
        ),
        footer = tagList(
          actionButton(ns("btnConfirmFilter"), "Apply", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
    })

    observeEvent(input$btnConfirmFilter, {
      action <- input$filter_action
      new_name <- trimws(input$filter_new_name %||% "")
      result <- su_create_from_filter(con, rv$result_plots, action, new_name)
      removeModal()
      showNotification(result$message, type = if (result$ok) "message" else "error")
    })

    invisible(NULL)
  })
}

# ---- Internal helper: Veg profile step ----
profile_veg_step <- function(con, env_tbl, veg_tbl, spp, layer, op, val) {
  # Build cover expression based on layer setting
  cover_expr <- if (layer == "Any") {
    "GREATEST(COALESCE(cover1,0), COALESCE(cover2,0), COALESCE(cover3,0), COALESCE(cover4,0), COALESCE(cover5,0), COALESCE(cover6,0), COALESCE(cover7,0))"
  } else if (layer == "SumAll") {
    "COALESCE(cover1,0) + COALESCE(cover2,0) + COALESCE(cover3,0) + COALESCE(cover4,0) + COALESCE(cover5,0) + COALESCE(cover6,0) + COALESCE(cover7,0)"
  } else if (layer %in% c("A1", "A2", "A3", "B1", "B2", "C", "D")) {
    # Map layer to cover column
    layer_map <- c(A1 = "cover1", A2 = "cover2", A3 = "cover3",
                   B1 = "cover4", B2 = "cover5", C = "cover6", D = "cover7")
    col_name <- layer_map[layer]
    if (is.na(col_name)) "COALESCE(cover1,0)" else paste0("COALESCE(", col_name, ",0)")
  } else {
    # "All" = sum of all
    "COALESCE(totala,0) + COALESCE(totalb,0)"
  }

  where_parts <- character(0)
  params <- list()
  if (nzchar(spp)) {
    where_parts <- c(where_parts, "LOWER(v.species) = LOWER(?)")
    params <- c(params, list(spp))
  }

  numeric_val <- suppressWarnings(as.numeric(val))
  if (!is.na(numeric_val)) {
    where_parts <- c(where_parts, paste0("(", cover_expr, ") ", op, " ?"))
    params <- c(params, list(numeric_val))
  }

  where_clause <- if (length(where_parts)) paste("AND", paste(where_parts, collapse = " AND ")) else ""

  sql <- paste0(
    "SELECT DISTINCT e.plotnumber FROM ", env_tbl, " e ",
    "INNER JOIN ", veg_tbl, " v ON e.plotnumber = v.plotnumber ",
    "WHERE 1=1 ", where_clause
  )
  rows <- db_query(con, sql, params = params)
  as.character(rows$plotnumber)
}

# ---- Internal helper: Env profile step ----
profile_env_step <- function(con, env_tbl, field, op, val) {
  # For Env fields, compare field value to criteria
  # Sanitise field name — only allow known column names
  safe_fields <- c("zone", "subzone", "siteseries", "moistureregime", "nutrientregime",
    "elevation", "aspect", "slopegradient", "structuralstage", "ecosection",
    "mesoslopeposition", "surfaceshape", "successionalstatus", "standage",
    "becsiteunit", "usersiteunit")
  field_lower <- tolower(field)
  if (!field_lower %in% safe_fields) {
    return(character(0))
  }

  # Determine if numeric comparison
  numeric_val <- suppressWarnings(as.numeric(val))
  if (op == "Like") {
    sql <- paste0(
      "SELECT DISTINCT plotnumber FROM ", env_tbl,
      " WHERE LOWER(CAST(", field_lower, " AS TEXT)) LIKE LOWER(?)"
    )
    rows <- db_query(con, sql, params = list(paste0("%", val, "%")))
  } else if (!is.na(numeric_val)) {
    sql <- paste0(
      "SELECT DISTINCT plotnumber FROM ", env_tbl,
      " WHERE CAST(", field_lower, " AS DOUBLE) ", op, " ?"
    )
    rows <- db_query(con, sql, params = list(numeric_val))
  } else {
    sql <- paste0(
      "SELECT DISTINCT plotnumber FROM ", env_tbl,
      " WHERE LOWER(CAST(", field_lower, " AS TEXT)) ", op, " LOWER(?)"
    )
    rows <- db_query(con, sql, params = list(val))
  }
  as.character(rows$plotnumber)
}
