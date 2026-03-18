
mod_reporting_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("Reporting"),
      card_body(
        navset_tab(
          id = ns("reporting_tabs"),
          nav_panel("Reports",
            p("Generate Quarto reports for the current context."),
            selectInput(ns("report_template"), "Report Template", choices = NULL),
            radioButtons(ns("report_format"), "Format", choices = c("HTML" = "html", "PDF" = "pdf", "Excel" = "xlsx"), inline = TRUE),
            tags$hr(),
            tags$h5("Report Options"),
            layout_columns(
              numericInput(ns("opt_colour_greater"), "Colour threshold", value = 5, min = 0, max = 100, step = 1),
              numericInput(ns("opt_gray_greater"), "Gray threshold", value = 65, min = 0, max = 100, step = 1),
              checkboxInput(ns("opt_apply_theme"), "Apply theme", value = TRUE),
              col_widths = c(4, 4, 4)
            ),
            uiOutput(ns("plot_params_ui")),
            uiOutput(ns("report_title_ui")),
            uiOutput(ns("veg_params_ui")),
            uiOutput(ns("hier_params_ui")),
            uiOutput(ns("qc_params_ui")),
            verbatimTextOutput(ns("report_ctx")),
            uiOutput(ns("report_action_buttons")),
            uiOutput(ns("report_preview")),
            uiOutput(ns("report_open_link"))
          ),
          nav_panel("Diagnostics",
            p("Run diagnostics and compliance checks for the current project."),
            layout_columns(
              selectInput(ns("diag_average"), "Average Type", choices = c("Plots" = "plots", "Covers" = "covers")),
              actionButton(ns("run_diag"), "Run Diagnostics", class = "btn-outline-secondary"),
              actionButton(ns("run_compliance"), "Run Compliance", class = "btn-outline-secondary"),
              col_widths = c(3, 3, 3)
            ),
            textOutput(ns("diag_status")),
            DT::DTOutput(ns("diag_matrix")),
            DT::DTOutput(ns("diag_results")),
            DT::DTOutput(ns("compliance_summary")),
            DT::DTOutput(ns("compliance_details"))
          )
        )
      )
    )
  )
}

mod_reporting_server <- function(id, sys_state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    value_or <- function(value, default = "") {
      if (is.null(value)) default else value
    }
    sql_quote <- function(value) {
      gsub("'", "''", value)
    }
    js_quote <- function(value) {
      paste0("'", gsub("'", "\\'", value), "'")
    }

    excel_available <- requireNamespace("writexl", quietly = TRUE)
    excel_warned <- reactiveVal(FALSE)

    report_prefs_loaded <- reactiveVal(FALSE)
    report_pref_defaults <- list(
      colour_greater = get_pref(con, "ReportOptions", "cmbColourGreater", default = 5L),
      gray_greater = get_pref(con, "ReportOptions", "cmbGrayGreater", default = 65L),
      apply_theme = get_pref(con, "ReportOptions", "cmbApplyTheme", default = 1L)
    )
    report_pref_defaults$apply_theme <- isTRUE(as.logical(report_pref_defaults$apply_theme))

    observe({
      if (report_prefs_loaded()) return()
      if (is.null(input$opt_colour_greater)) return()
      updateNumericInput(session, "opt_colour_greater", value = report_pref_defaults$colour_greater)
      updateNumericInput(session, "opt_gray_greater", value = report_pref_defaults$gray_greater)
      updateCheckboxInput(session, "opt_apply_theme", value = report_pref_defaults$apply_theme)
      report_prefs_loaded(TRUE)
    })

    observeEvent(input$opt_colour_greater, {
      set_pref(con, "ReportOptions", "cmbColourGreater", input$opt_colour_greater)
    }, ignoreInit = TRUE)

    observeEvent(input$opt_gray_greater, {
      set_pref(con, "ReportOptions", "cmbGrayGreater", input$opt_gray_greater)
    }, ignoreInit = TRUE)

    observeEvent(input$opt_apply_theme, {
      set_pref(con, "ReportOptions", "cmbApplyTheme", as.integer(isTRUE(input$opt_apply_theme)))
    }, ignoreInit = TRUE)

    export_tables_to_parquet <- function(tables) {
      if (length(tables) == 0) return(NULL)
      export_dir <- file.path(tempdir(), paste0("report_parquet_", as.integer(Sys.time())))
      dir.create(export_dir, recursive = TRUE, showWarnings = FALSE)

      for (table_name in tables) {
        file_name <- paste0(gsub("[^A-Za-z0-9_]", "_", table_name), ".parquet")
        file_path <- file.path(export_dir, file_name)
        sql <- sprintf(
          "COPY (SELECT * FROM %s) TO '%s' (FORMAT PARQUET)",
          table_name,
          sql_quote(file_path)
        )
        result <- tryCatch(
          DBI::dbExecute(con, sql),
          error = function(e) {
            # Non-fatal: warn but keep going so other tables still export
            warning(sprintf("[export_tables_to_parquet] %s: %s", table_name, conditionMessage(e)))
            NULL
          }
        )
      }

      export_dir
    }

    get_report_exports <- function(template_name) {
      exports <- list(
        "site_summary.qmd" = c("Env", "SU", "vw_USysAllVeg", "Humus", "Mineral"),
        "short_veg.qmd" = c("vw_USysAllVeg", "SU", "Lump", "LayerCode", "lists.USysAllSpecs"),
        "long_veg.qmd" = c("vw_USysAllVeg", "SU", "Lump", "LayerCode",
                           "lists.USysAllSpecs", "Admin", "vw_USysEnv"),
        "env_summary.qmd" = c("Env", "SU"),
        "long_env.qmd" = c("Env", "SU", "lists.MasterSiteUnitList"),
        "short_veg_env.qmd" = c("vw_USysAllVeg", "Env", "SU", "Lump", "LayerCode", "lists.USysAllSpecs"),
        "lifeform.qmd" = c("vw_USysAllVeg", "SU", "Lump", "LayerCode", "lists.USysAllSpecs"),
        "flat_hierarchy.qmd" = c("Hierarchy"),
        "hierarchy.qmd" = c("Hierarchy", "lists.MasterSiteUnitList"),
        "short_veg_hierarchy.qmd" = c("vw_USysAllVeg", "SU", "Lump", "LayerCode", "lists.USysAllSpecs"),
        "short_veg_order_hierarchy.qmd" = c("vw_USysAllVeg", "SU", "Lump", "LayerCode", "lists.USysAllSpecs"),
        "veg_layer_a.qmd" = c("Veg", "SU", "Env"),
        "veg_layer_c.qmd" = c("Veg", "SU", "Env"),
        "veg_layer_d.qmd" = c("Veg", "SU", "Env"),
        "bec_labels.qmd" = c("Env", "SU"),
        "quality_control.qmd" = c("SU", "Admin", "Env", "Veg", "lists.USysTableOfLists")
      )
      exports[[template_name]]
    }
    observe({
      templates <- list.files(file.path(getwd(), "reports"), pattern = "\\.qmd$", full.names = FALSE)
      if (length(templates) == 0) {
        updateSelectInput(session, "report_template", choices = c("No templates found" = ""))
      } else {
        updateSelectInput(session, "report_template", choices = templates, selected = "site_summary.qmd")
      }
    })

    report_requires_plot <- function(template_name) {
      template_name %in% c(
        "site_summary.qmd",
        "env_summary.qmd",
        "long_env.qmd",
        "veg_layer_a.qmd",
        "veg_layer_c.qmd",
        "veg_layer_d.qmd",
        "bec_labels.qmd",
        "short_veg.qmd",
        "lifeform.qmd",
        "short_veg_env.qmd",
        "short_veg_hierarchy.qmd",
        "short_veg_order_hierarchy.qmd"
      )
    }

    observeEvent(input$report_template, {
      if (identical(input$report_template, "long_env.qmd")) {
        updateRadioButtons(
          session,
          "report_format",
          choices = c("Excel" = "xlsx"),
          selected = "xlsx"
        )
      } else {
        updateRadioButtons(
          session,
          "report_format",
          choices = c("HTML" = "html", "PDF" = "pdf", "Excel" = "xlsx"),
          selected = if (!is.null(input$report_format) && nzchar(input$report_format)) input$report_format else "html"
        )
      }
    }, ignoreInit = TRUE)

    observeEvent(list(input$report_format, input$report_template), {
      if (is.null(input$report_format)) return()
      if (identical(input$report_format, "xlsx") && !excel_available) {
        shinyjs::disable("dl_report")
        if (!isTRUE(excel_warned())) {
          showNotification("Excel export requires the writexl package. Install it to enable downloads.", type = "warning")
          excel_warned(TRUE)
        }
      } else {
        shinyjs::enable("dl_report")
        excel_warned(FALSE)
      }
    })
    
    output$report_ctx <- renderText({
      req(input$report_template)
      if (isTRUE(report_requires_plot(input$report_template))) {
        req(sys_state$CurrSU)
        return(paste("Ready to generate report for Plot:", sys_state$CurrSU))
      }
      if (identical(input$report_template, "quality_control.qmd") && !is.null(sys_state$CurrProject)) {
        return(paste("Ready to generate report for Project:", sys_state$CurrProject))
      }
      "Ready to generate report."
    })

    output$report_action_buttons <- renderUI({
      if (identical(input$report_template, "long_env.qmd")) {
        return(tags$div(
          class = "mt-3",
          downloadButton(ns("dl_report"), "Generate Report", class = "btn-lg btn-danger")
        ))
      }

      tags$div(
        class = "mt-3",
        actionButton(ns("preview_report"), "Preview HTML", class = "btn-secondary"),
        downloadButton(ns("dl_report"), "Generate Report", class = "btn-lg btn-danger"),
        actionButton(ns("open_report"), "Open last report", class = "btn-outline-secondary")
      )
    })

    output$plot_params_ui <- renderUI({
      req(input$report_template)
      if (!(input$report_template %in% c(
        "site_summary.qmd",
        "env_summary.qmd",
        "long_env.qmd",
        "veg_layer_a.qmd",
        "veg_layer_c.qmd",
        "veg_layer_d.qmd",
        "bec_labels.qmd"
      ))) return(NULL)

      tagList(
        tags$hr(),
        tags$h5("Plot Filters"),
        layout_columns(
          textInput(ns("plot_plot_numbers"), "Plot list (comma-separated)", value = value_or(sys_state$CurrSU, "")),
          textInput(ns("plot_site_unit"), "Site unit (optional)", value = ""),
          textInput(ns("plot_project_id"), "Project ID (optional)", value = value_or(sys_state$CurrProject, "")),
          col_widths = c(4, 4, 4)
        ),
        if (input$report_template %in% c("env_summary.qmd", "long_env.qmd")) {
          layout_columns(
            textInput(ns("env_report_title"), "Report title", value = "Environment Summary"),
            col_widths = c(6)
          )
        } else if (identical(input$report_template, "bec_labels.qmd")) {
          layout_columns(
            textInput(ns("bec_labels_report_title"), "Report title", value = "BEC Labels"),
            col_widths = c(6)
          )
        } else if (identical(input$report_template, "site_summary.qmd")) {
          layout_columns(
            textInput(ns("site_report_title"), "Report title", value = "Site Unit Report"),
            col_widths = c(6)
          )
        } else if (input$report_template %in% c("veg_layer_a.qmd", "veg_layer_c.qmd", "veg_layer_d.qmd")) {
          default_title <- if (identical(input$report_template, "veg_layer_a.qmd")) {
            "Vegetation Layer A (Trees)"
          } else if (identical(input$report_template, "veg_layer_c.qmd")) {
            "Vegetation Layer C (Herbs)"
          } else {
            "Vegetation Layer D (Moss/Lichen)"
          }
          layout_columns(
            textInput(ns("veg_layer_report_title"), "Report title", value = default_title),
            col_widths = c(6)
          )
        }
      )
    })

    output$report_title_ui <- renderUI({
      req(input$report_template)
      if (!identical(input$report_template, "field_checklist.qmd")) return(NULL)

      tagList(
        tags$hr(),
        tags$h5("Report Title"),
        layout_columns(
          textInput(ns("field_report_title"), "Report title", value = "Field Checklist"),
          col_widths = c(6)
        )
      )
    })

    output$veg_params_ui <- renderUI({
      req(input$report_template)
      if (!(input$report_template %in% c(
        "short_veg.qmd",
        "long_veg.qmd",
        "lifeform.qmd",
        "short_veg_env.qmd",
        "short_veg_hierarchy.qmd",
        "short_veg_order_hierarchy.qmd"
      ))) return(NULL)

      tagList(
        tags$hr(),
        tags$h5("Vegetation Filters"),
        layout_columns(
          textInput(ns("veg_plot_numbers"), "Plot list (comma-separated)", value = value_or(sys_state$CurrSU, "")),
          textInput(ns("veg_site_unit"), "Site unit (optional)", value = ""),
          textInput(ns("veg_project_id"), "Project ID (optional)", value = value_or(sys_state$CurrProject, "")),
          col_widths = c(4, 4, 4)
        ),
        layout_columns(
          checkboxInput(ns("veg_apply_lumping"), "Apply lumping", value = FALSE),
          checkboxInput(ns("veg_constancy_format"), "Constancy format", value = FALSE),
          col_widths = c(4, 4)
        ),
        layout_columns(
          textInput(
            ns("veg_report_title"),
            "Report title",
            value = if (identical(input$report_template, "long_veg.qmd")) {
              "Long Vegetation Table"
            } else if (identical(input$report_template, "lifeform.qmd")) {
              "Lifeform Summary"
            } else if (identical(input$report_template, "short_veg_env.qmd")) {
              "Short Vegetation + Environment"
            } else if (identical(input$report_template, "short_veg_hierarchy.qmd")) {
              "Short Vegetation + Hierarchy"
            } else if (identical(input$report_template, "short_veg_order_hierarchy.qmd")) {
              "Short Vegetation Ordered by Hierarchy"
            } else {
              "Short Vegetation Table"
            }
          ),
          col_widths = c(6)
        ),
        layout_columns(
          selectInput(
            ns("veg_display_value"),
            "Display value",
            choices = c(
              "Presence + mean cover" = "standard",
              "Presence ratio - cover" = "presence_mean",
              "Presence class - significance" = "presence_signif",
              "Presence class - cover" = "rk",
              "Prominence class" = "prominence",
              "Goldstream class" = "goldstream",
              "Cover only" = "cover"
            ),
            selected = "presence_mean"
          ),
          col_widths = c(6)
        ),
        layout_columns(
          selectInput(
            ns("veg_group_by"),
            "Group by",
            choices = c("Layer" = "layer", "Strata" = "strata", "Lifeform" = "lifeform", "None" = "none"),
            selected = "layer"
          ),
          selectInput(
            ns("veg_order_by"),
            "Order by",
            choices = c("Species" = "species", "Presence" = "presence", "Cover" = "value"),
            selected = "species"
          ),
          selectInput(
            ns("veg_avg_type"),
            "Average type",
            choices = c(
              "By n Plots (incl. absences)"        = "by_n_plots",
              "Characteristic (present plots only)" = "characteristic"
            ),
            selected = "by_n_plots"
          ),
          col_widths = c(4, 4, 4)
        ),
        layout_columns(
          numericInput(ns("veg_presence_min"), "Presence min (%)", value = 0, min = 0, max = 100, step = 1),
          numericInput(ns("veg_cover_min"), "Cover min", value = 0, min = 0, step = 1),
          numericInput(ns("veg_value_limit"), "Value limit (order by value)", value = 0, min = 0, step = 0.01),
          col_widths = c(3, 3, 3)
        ),
        layout_columns(
          selectInput(
            ns("veg_show_common"),
            "Extra label",
            choices = c(
              "None" = "none",
              "English name" = "english",
              "Short guide name" = "short",
              "Combined English" = "combined",
              "Species code" = "code",
              "Species attribute" = "attribute"
            ),
            selected = "none"
          ),
          col_widths = c(6)
        ),
        # Long Vegetation only options 
        if (identical(input$report_template, "long_veg.qmd")) {
          tagList(
            tags$hr(),
            tags$h5("Long Vegetation Options"),
            layout_columns(
              selectInput(
                ns("lv_unit_groups"),
                "Plot source",
                choices = c(
                  "Site unit table"          = "site_unit",
                  "Selected fields"          = "selected_fields",
                  "None (plot numbers only)" = "none"
                ),
                selected = "site_unit"
              ),
              selectInput(
                ns("lv_show_field"),
                "Attribute field (when Extra label = Attribute)",
                choices = c(
                  "- none -"  = "",
                  "Red/Blue List"     = "RedBlueList",
                  "Wetland Indicator" = "Wetland_Ind",
                  "Weed Status"       = "WeedStatus"
                ),
                selected = ""
              ),
              col_widths = c(4, 4)
            ),
            layout_columns(
              checkboxInput(ns("lv_space_between_groups"), "Space between groups",   value = FALSE),
              checkboxInput(ns("lv_use_spp_codes_only"),   "Species codes only",     value = FALSE),
              checkboxInput(ns("lv_constant_spp_list"),    "Constant species list",  value = FALSE),
              checkboxInput(ns("lv_screen_report"),        "Screen report (faster)", value = TRUE),
              checkboxInput(ns("lv_create_summary"),       "Append summary section", value = FALSE),
              col_widths = c(3, 3, 2, 2, 2)
            ),
            tags$h6("Data Quality Gate"),
            layout_columns(
              checkboxInput(ns("lv_enforce_qc"), "Enforce quality control", value = FALSE),
              col_widths = c(4)
            ),
            conditionalPanel(
              condition = sprintf("input['%s'] == true", ns("lv_enforce_qc")),
              layout_columns(
                selectInput(
                  ns("lv_site_quality_min"), "Site quality min",
                  choices = c("- any -" = "", "Poor", "Fair", "Good", "Excellent"),
                  selected = ""
                ),
                checkboxInput(ns("lv_site_quality_include_null"), "Include null site quality", value = TRUE),
                col_widths = c(4, 4)
              ),
              layout_columns(
                selectInput(
                  ns("lv_veg_quality_min"), "Veg quality min",
                  choices = c("- any -" = "", "Poor", "Fair", "Good", "Excellent"),
                  selected = ""
                ),
                checkboxInput(ns("lv_veg_quality_include_null"), "Include null veg quality", value = TRUE),
                col_widths = c(4, 4)
              ),
              layout_columns(
                selectInput(
                  ns("lv_soil_quality_min"), "Soil quality min",
                  choices = c("- any -" = "", "Poor", "Fair", "Good", "Excellent"),
                  selected = ""
                ),
                checkboxInput(ns("lv_soil_quality_include_null"), "Include null soil quality", value = TRUE),
                col_widths = c(4, 4)
              )
            )
          )
        } else {
          NULL
        }
      )
    })

    output$hier_params_ui <- renderUI({
      req(input$report_template)
      if (!(input$report_template %in% c("hierarchy.qmd", "flat_hierarchy.qmd"))) return(NULL)

      default_title <- if (identical(input$report_template, "flat_hierarchy.qmd")) {
        "Flat Hierarchy"
      } else {
        "Hierarchy Diagram"
      }

      tagList(
        tags$hr(),
        tags$h5("Hierarchy Filters"),
        layout_columns(
          numericInput(ns("hier_cutoff_level"), "Lowest level", value = 11, min = 1, step = 1),
          col_widths = c(3)
        ),
        layout_columns(
          textInput(ns("hier_report_title"), "Report title", value = default_title),
          col_widths = c(6)
        )
      )
    })

    output$qc_params_ui <- renderUI({
      req(input$report_template)
      if (input$report_template != "quality_control.qmd") return(NULL)

      dq_choices <- c("All" = "")
      if (!is.null(con) && DBI::dbExistsTable(con, "lists.USysTableOfLists")) {
        dq <- DBI::dbGetQuery(
          con,
          "SELECT Item, ItemOrder FROM lists.USysTableOfLists WHERE lower(ListName) = 'dataquality' ORDER BY ItemOrder"
        )
        if (nrow(dq) > 0) {
          dq_choices <- c("All" = "", stats::setNames(dq$Item, dq$Item))
        }
      } else {
        dq_choices <- c("All" = "", "Poor" = "Poor", "Fair" = "Fair", "Good" = "Good", "Excellent" = "Excellent")
      }

      tagList(
        tags$hr(),
        tags$h5("Quality Control Filters"),
        layout_columns(
          textInput(ns("qc_report_title"), "Report title", value = "Quality Control"),
          col_widths = c(6)
        ),
        layout_columns(
          textInput(ns("qc_project_id"), "Project ID", value = value_or(sys_state$CurrProject, "")),
          checkboxInput(ns("qc_enforce_filter"), "Enforce data quality filter", value = TRUE),
          col_widths = c(4, 4)
        ),
        layout_columns(
          selectInput(ns("qc_site_min"), "Site quality min", choices = dq_choices, selected = "Good"),
          checkboxInput(ns("qc_site_allow_null"), "Allow null site", value = TRUE),
          col_widths = c(4, 4)
        ),
        layout_columns(
          selectInput(ns("qc_veg_min"), "Veg quality min", choices = dq_choices, selected = "Good"),
          checkboxInput(ns("qc_veg_allow_null"), "Allow null veg", value = TRUE),
          col_widths = c(4, 4)
        ),
        layout_columns(
          selectInput(ns("qc_soil_min"), "Soil quality min", choices = dq_choices, selected = "Good"),
          checkboxInput(ns("qc_soil_allow_null"), "Allow null soil", value = TRUE),
          col_widths = c(4, 4)
        ),
        layout_columns(
          textInput(ns("qc_bec_use_min"), "BEC use min", value = ""),
          checkboxInput(ns("qc_bec_allow_null"), "Allow null BEC", value = TRUE),
          col_widths = c(4, 4)
        )
      )
    })

    observeEvent(sys_state$CurrProject, {
      if (!is.null(input$qc_project_id)) {
        updateTextInput(session, "qc_project_id", value = sys_state$CurrProject)
      }
      if (!is.null(input$veg_project_id)) {
        updateTextInput(session, "veg_project_id", value = sys_state$CurrProject)
      }
      if (!is.null(input$plot_project_id)) {
        updateTextInput(session, "plot_project_id", value = sys_state$CurrProject)
      }
    }, ignoreInit = TRUE)

    observeEvent(sys_state$CurrSU, {
      if (!is.null(input$veg_plot_numbers)) {
        updateTextInput(session, "veg_plot_numbers", value = as.character(sys_state$CurrSU))
      }
      if (!is.null(input$plot_plot_numbers)) {
        updateTextInput(session, "plot_plot_numbers", value = as.character(sys_state$CurrSU))
      }
    }, ignoreInit = TRUE)

    build_report_params <- function(template_name, parquet_dir = "") {
      db_path <- normalizePath(file.path(getwd(), "data", "vpro.duckdb"), winslash = "/", mustWork = FALSE)
      project_root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
      if (identical(template_name, "quality_control.qmd")) {
        list(
          project_root = project_root,
          db_path = db_path,
          parquet_dir = parquet_dir,
          report_title = value_or(input$qc_report_title, "Quality Control"),
          colour_greater = as.numeric(value_or(input$opt_colour_greater, 5)),
          gray_greater = as.numeric(value_or(input$opt_gray_greater, 65)),
          apply_theme = isTRUE(input$opt_apply_theme),
          project_id = trimws(value_or(input$qc_project_id, "")),
          enforce_filter = isTRUE(input$qc_enforce_filter),
          site_quality_min = value_or(input$qc_site_min, ""),
          veg_quality_min = value_or(input$qc_veg_min, ""),
          soil_quality_min = value_or(input$qc_soil_min, ""),
          site_allow_null = isTRUE(input$qc_site_allow_null),
          veg_allow_null = isTRUE(input$qc_veg_allow_null),
          soil_allow_null = isTRUE(input$qc_soil_allow_null),
          bec_use_min = value_or(input$qc_bec_use_min, ""),
          bec_allow_null = isTRUE(input$qc_bec_allow_null)
        )
      } else if (template_name %in% c(
        "short_veg.qmd",
        "long_veg.qmd",
        "lifeform.qmd",
        "short_veg_env.qmd",
        "short_veg_hierarchy.qmd",
        "short_veg_order_hierarchy.qmd"
      )) {
        # Base params shared by all veg templates
        base_veg <- list(
          project_root     = project_root,
          plot_number      = as.character(sys_state$CurrSU),
          plot_numbers     = trimws(value_or(input$veg_plot_numbers, "")),
          site_unit        = trimws(value_or(input$veg_site_unit, "")),
          project_id       = trimws(value_or(input$veg_project_id, "")),
          group_by         = value_or(input$veg_group_by, "layer"),
          order_by         = value_or(input$veg_order_by, "species"),
          avg_type         = value_or(input$veg_avg_type, "by_n_plots"),
          presence_min     = as.numeric(value_or(input$veg_presence_min, 0)),
          cover_min        = as.numeric(value_or(input$veg_cover_min, 0)),
          value_limit      = as.numeric(value_or(input$veg_value_limit, 0)),
          show_common      = value_or(input$veg_show_common, "none"),
          display_value    = value_or(input$veg_display_value, "presence_mean"),
          report_title     = value_or(input$veg_report_title, "Short Vegetation Table"),
          apply_lumping    = isTRUE(input$veg_apply_lumping),
          constancy_format = isTRUE(input$veg_constancy_format),
          colour_greater   = as.numeric(value_or(input$opt_colour_greater, 5)),
          gray_greater     = as.numeric(value_or(input$opt_gray_greater, 65)),
          apply_theme      = isTRUE(input$opt_apply_theme),
          db_path          = db_path,
          parquet_dir      = parquet_dir
        )
        # Long Veg gets 14 additional params from the lv_* inputs
        if (identical(template_name, "long_veg.qmd")) {
          c(base_veg, list(
            show_field                = value_or(input$lv_show_field, ""),
            unit_groups               = value_or(input$lv_unit_groups, "site_unit"),
            space_between_groups      = isTRUE(input$lv_space_between_groups),
            use_spp_codes_only        = isTRUE(input$lv_use_spp_codes_only),
            constant_spp_list         = isTRUE(input$lv_constant_spp_list),
            screen_report             = isTRUE(input$lv_screen_report),
            create_summary            = isTRUE(input$lv_create_summary),
            enforce_qc                = isTRUE(input$lv_enforce_qc),
            site_quality_min          = value_or(input$lv_site_quality_min, ""),
            veg_quality_min           = value_or(input$lv_veg_quality_min, ""),
            soil_quality_min          = value_or(input$lv_soil_quality_min, ""),
            site_quality_include_null = isTRUE(input$lv_site_quality_include_null),
            veg_quality_include_null  = isTRUE(input$lv_veg_quality_include_null),
            soil_quality_include_null = isTRUE(input$lv_soil_quality_include_null)
          ))
        } else {
          base_veg
        }
      } else if (template_name %in% c("hierarchy.qmd", "flat_hierarchy.qmd")) {
        list(
          project_root = project_root,
          db_path = db_path,
          parquet_dir = parquet_dir,
          report_title = value_or(input$hier_report_title, if (identical(template_name, "flat_hierarchy.qmd")) "Flat Hierarchy" else "Hierarchy Diagram"),
          cutoff_level = as.integer(value_or(input$hier_cutoff_level, 11)),
          colour_greater = as.numeric(value_or(input$opt_colour_greater, 5)),
          gray_greater = as.numeric(value_or(input$opt_gray_greater, 65)),
          apply_theme = isTRUE(input$opt_apply_theme)
        )
      } else if (template_name %in% c(
        "site_summary.qmd",
        "env_summary.qmd",
        "long_env.qmd",
        "veg_layer_a.qmd",
        "veg_layer_c.qmd",
        "veg_layer_d.qmd",
        "bec_labels.qmd"
      )) {
        params <- list(
          project_root = project_root,
          plot_number = as.character(sys_state$CurrSU),
          plot_numbers = trimws(value_or(input$plot_plot_numbers, "")),
          site_unit = trimws(value_or(input$plot_site_unit, "")),
          project_id = trimws(value_or(input$plot_project_id, "")),
          colour_greater = as.numeric(value_or(input$opt_colour_greater, 5)),
          gray_greater = as.numeric(value_or(input$opt_gray_greater, 65)),
          apply_theme = isTRUE(input$opt_apply_theme),
          db_path = db_path,
          parquet_dir = parquet_dir
        )
        if (template_name %in% c("env_summary.qmd", "long_env.qmd")) {
          default_title <- if (identical(template_name, "long_env.qmd")) "Long Environment" else "Environment Summary"
          params$report_title <- value_or(input$env_report_title, default_title)
        } else if (identical(template_name, "bec_labels.qmd")) {
          params$report_title <- value_or(input$bec_labels_report_title, "BEC Labels")
        } else if (identical(template_name, "site_summary.qmd")) {
          params$report_title <- value_or(input$site_report_title, "Site Unit Report")
        } else if (template_name %in% c("veg_layer_a.qmd", "veg_layer_c.qmd", "veg_layer_d.qmd")) {
          default_title <- if (identical(template_name, "veg_layer_a.qmd")) {
            "Vegetation Layer A (Trees)"
          } else if (identical(template_name, "veg_layer_c.qmd")) {
            "Vegetation Layer C (Herbs)"
          } else {
            "Vegetation Layer D (Moss/Lichen)"
          }
          params$report_title <- value_or(input$veg_layer_report_title, default_title)
        }
        params
      } else if (identical(template_name, "field_checklist.qmd")) {
        list(
          project_root = project_root,
          report_title = value_or(input$field_report_title, "Field Checklist")
        )
      } else {
        list(
          project_root = project_root,
          plot_number = as.character(sys_state$CurrSU),
          db_path = db_path,
          parquet_dir = parquet_dir
        )
      }
    }
    
    preview_path <- reactiveVal(NULL)
    report_file <- reactiveVal(NULL)
    report_url <- reactiveVal(NULL)

    set_report_url <- function(report_path) {
      if (is.null(report_path) || !file.exists(report_path)) return(invisible(FALSE))
      addResourcePath("report_output", dirname(report_path))
      report_url(file.path("report_output", basename(report_path)))
      invisible(TRUE)
    }

    observeEvent(input$preview_report, {
      req(input$report_template)

      if (isTRUE(report_requires_plot(input$report_template))) {
        req(sys_state$CurrSU)
      }

      if (identical(input$report_template, "long_env.qmd")) {
        showNotification("HTML preview is disabled for Long Environment; use Excel export.", type = "warning")
        return()
      }

      old_quarto_root <- Sys.getenv("QUARTO_PROJECT_DIR", unset = NA)
      Sys.setenv(QUARTO_PROJECT_DIR = getwd())
      on.exit({
        if (is.na(old_quarto_root)) {
          Sys.unsetenv("QUARTO_PROJECT_DIR")
        } else {
          Sys.setenv(QUARTO_PROJECT_DIR = old_quarto_root)
        }
      }, add = TRUE)

      tmp_dir <- file.path(tempdir(), "report_preview")
      if (!dir.exists(tmp_dir)) dir.create(tmp_dir, recursive = TRUE)

      qmd_path <- file.path(getwd(), "reports", input$report_template)
      if (!file.exists(qmd_path)) {
        showNotification("Report template not found!", type = "error")
        return()
      }

      tmp_qmd <- file.path(tmp_dir, basename(input$report_template))
      file.copy(qmd_path, tmp_qmd, overwrite = TRUE)
      notif_id <- showNotification("Generating preview...", duration = NULL, closeButton = FALSE)
      on.exit(removeNotification(notif_id), add = TRUE)

      tryCatch({
        export_tables <- get_report_exports(input$report_template)
        parquet_dir <- ""
        if (!is.null(export_tables) && length(export_tables) > 0) {
          parquet_dir <- export_tables_to_parquet(export_tables)
        }
        quarto::quarto_render(
          input = tmp_qmd,
          output_format = "html",
          execute_params = build_report_params(input$report_template, parquet_dir = parquet_dir)
        )

        # Clean up parquet temp dir AFTER render completes
        if (nzchar(parquet_dir) && dir.exists(parquet_dir)) {
          unlink(parquet_dir, recursive = TRUE, force = TRUE)
        }

        out_generated <- file.path(tmp_dir, paste0(tools::file_path_sans_ext(basename(input$report_template)), ".html"))
        if (file.exists(out_generated)) {
          preview_path(out_generated)
          report_file(out_generated)
          set_report_url(out_generated)
        } else {
          showNotification("Preview generation failed - check R console for Quarto errors.", type = "error")
        }
      }, error = function(e) {
        showNotification(paste("Preview error:", conditionMessage(e)), type = "error")
      })
    }, ignoreInit = TRUE)

    output$report_preview <- renderUI({
      if (identical(input$report_template, "long_env.qmd")) return(NULL)
      preview_file <- preview_path()
      if (is.null(preview_file) || !file.exists(preview_file)) return(NULL)

      addResourcePath("report_preview", dirname(preview_file))
      tags$iframe(
        src = file.path("report_preview", basename(preview_file)),
        style = "width:100%; height:600px; border:1px solid #ccc;"
      )
    })

    observeEvent(report_file(), {
      set_report_url(report_file())
    })

    observeEvent(input$open_report, {
      target_url <- report_url()
      if (is.null(target_url) || !nzchar(target_url)) {
        showNotification("No report generated yet.", type = "warning")
        return()
      }
      shinyjs::runjs(paste0("window.open(", js_quote(target_url), ", '_blank');"))
    }, ignoreInit = TRUE)

    output$report_open_link <- renderUI({
      if (identical(input$report_template, "long_env.qmd")) return(NULL)
      report_path <- report_file()
      target_url <- report_url()
      if (is.null(report_path) || !file.exists(report_path) || is.null(target_url)) return(NULL)
      tags$div(
        class = "mt-2",
        tags$a(
          "Open report in new tab",
          href = target_url,
          target = "_blank",
          class = "btn btn-outline-secondary"
        )
      )
    })

    write_excel_report <- function(template_name, params, file_path) {
      if (!excel_available) {
        stop("writexl package is required for Excel export.")
      }
      data_list <- build_excel_report_data(con, template_name, params)
      if (is.null(data_list) || length(data_list) == 0) {
        data_list <- list("NoData" = data.frame(Message = "No data found.", stringsAsFactors = FALSE))
      }
      names(data_list) <- sanitize_sheet_names(names(data_list))
      writexl::write_xlsx(data_list, path = file_path)
    }

    output$dl_report <- downloadHandler(
      filename = function() {
        template_name <- tools::file_path_sans_ext(basename(input$report_template))
        plot_token <- if (isTRUE(report_requires_plot(input$report_template)) && !is.null(sys_state$CurrSU) && nzchar(sys_state$CurrSU)) {
          sys_state$CurrSU
        } else if (!is.null(sys_state$CurrProject) && nzchar(sys_state$CurrProject)) {
          sys_state$CurrProject
        } else {
          "all"
        }
        ext <- if (is.null(input$report_format) || input$report_format == "") "html" else input$report_format
        paste0(template_name, "_", plot_token, "_", Sys.Date(), ".", ext)
      },
      content = function(file) {
        req(input$report_template)

        if (isTRUE(report_requires_plot(input$report_template))) {
          req(sys_state$CurrSU)
        }

        old_quarto_root <- Sys.getenv("QUARTO_PROJECT_DIR", unset = NA)
        Sys.setenv(QUARTO_PROJECT_DIR = getwd())
        on.exit({
          if (is.na(old_quarto_root)) {
            Sys.unsetenv("QUARTO_PROJECT_DIR")
          } else {
            Sys.setenv(QUARTO_PROJECT_DIR = old_quarto_root)
          }
        }, add = TRUE)
        
        # Show Notification
        id <- showNotification("Generating Quarto Report...", duration = NULL, closeButton = FALSE)
        on.exit(removeNotification(id), add = TRUE)
        
        # Paths
        qmd_path <- file.path(getwd(), "reports", input$report_template)
        db_path <- file.path(getwd(), "data", "vpro.duckdb")
        
        # Validation
        if (!file.exists(qmd_path)) {
            showNotification("Report template not found!", type = "error")
            return(NULL)
        }
        
        # Render to temp file
        tmp_dir <- tempdir()
        tmp_qmd <- file.path(tmp_dir, basename(input$report_template))
        file.copy(qmd_path, tmp_qmd, overwrite = TRUE)
        
        out_format <- if (is.null(input$report_format) || input$report_format == "") "html" else input$report_format

        if (out_format == "xlsx") {
          if (!excel_available) {
            showNotification("Excel export requires the writexl package.", type = "error")
            return()
          }
          params <- build_report_params(input$report_template)
          tryCatch({
            write_excel_report(input$report_template, params, file)
            report_file(NULL)
            report_url(NULL)
          }, error = function(e) {
            showNotification(paste("Excel export failed:", e$message), type = "error")
          })
          return()
        }

        # Render
        # Note: Quarto generates output in the same dir as input by default
        export_tables <- get_report_exports(input$report_template)
        parquet_dir <- ""
        if (!is.null(export_tables) && length(export_tables) > 0) {
          parquet_dir <- export_tables_to_parquet(export_tables)
        }
        on.exit({
          if (nzchar(parquet_dir) && dir.exists(parquet_dir)) {
            unlink(parquet_dir, recursive = TRUE, force = TRUE)
          }
        }, add = TRUE)

        quarto::quarto_render(
          input = tmp_qmd,
          output_format = out_format,
          execute_params = build_report_params(input$report_template, parquet_dir = parquet_dir)
        )
        
        # Result file
        out_generated <- file.path(tmp_dir, paste0(tools::file_path_sans_ext(basename(input$report_template)), ".", out_format))
        
        if (file.exists(out_generated)) {
          report_file(out_generated)
          set_report_url(out_generated)
          file.copy(out_generated, file)
        } else {
            showNotification("Report generation failed.", type = "error")
        }
      }
    )

    rv_diag <- reactiveValues(matrix = NULL, diagnostics = NULL, compliance = NULL, status = "")

    observeEvent(input$run_diag, {
      req(con)
      avg_type <- if (!is.null(input$diag_average) && nzchar(input$diag_average)) input$diag_average else "plots"
      result <- build_diagnostic_matrix(con, project_id = sys_state$CurrProject, average_type = avg_type)
      rv_diag$matrix <- result$matrix
      rv_diag$diagnostics <- result$diagnostics
      rv_diag$status <- paste("Diagnostics rows:", nrow(result$diagnostics))
    })

    observeEvent(input$run_compliance, {
      req(con)
      rv_diag$compliance <- run_compliance_checks(con, sys_state$CurrProject)
      rv_diag$status <- paste("Compliance issues:", nrow(rv_diag$compliance$detail_tibble))
    })

    output$diag_status <- renderText({
      rv_diag$status
    })

    output$diag_matrix <- DT::renderDT({
      if (is.null(rv_diag$matrix) || nrow(rv_diag$matrix) == 0) return(NULL)
      DT::datatable(rv_diag$matrix, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
    })

    output$diag_results <- DT::renderDT({
      if (is.null(rv_diag$diagnostics) || nrow(rv_diag$diagnostics) == 0) return(NULL)
      DT::datatable(rv_diag$diagnostics, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
    })

    output$compliance_summary <- DT::renderDT({
      if (is.null(rv_diag$compliance) || nrow(rv_diag$compliance$summary_tibble) == 0) return(NULL)
      DT::datatable(rv_diag$compliance$summary_tibble, rownames = FALSE, options = list(pageLength = 10))
    })

    output$compliance_details <- DT::renderDT({
      if (is.null(rv_diag$compliance) || nrow(rv_diag$compliance$detail_tibble) == 0) return(NULL)
      DT::datatable(rv_diag$compliance$detail_tibble, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE))
    })
    
  })
}
