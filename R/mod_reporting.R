
mod_reporting_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("Reporting"),
      card_body(
        navset_tab(
          nav_panel("Reports",
            p("Generate Quarto reports for the current context."),
            selectInput(ns("report_template"), "Report Template", choices = NULL),
            radioButtons(ns("report_format"), "Format", choices = c("HTML" = "html", "PDF" = "pdf"), inline = TRUE),
            uiOutput(ns("veg_params_ui")),
            uiOutput(ns("hier_params_ui")),
            uiOutput(ns("qc_params_ui")),
            verbatimTextOutput(ns("report_ctx")),
            div(class="mt-3",
                actionButton(ns("preview_report"), "Preview HTML", class = "btn-secondary"),
                downloadButton(ns("dl_report"), "Generate Report", class="btn-lg btn-danger")
            ),
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
        try(DBI::dbExecute(con, sql), silent = TRUE)
      }

      export_dir
    }

    get_report_exports <- function(template_name) {
      exports <- list(
        "site_summary.qmd" = c("Sample_Env", "vw_USysAllVeg", "Sample_Humus", "Sample_Mineral"),
        "short_veg.qmd" = c("vw_USysAllVeg", "Sample_SU", "Sample_Lump", "LayerCode", "lists.USysAllSpecs"),
        "long_veg.qmd" = c("vw_USysAllVeg", "Sample_SU", "Sample_Lump", "LayerCode", "lists.USysAllSpecs"),
        "env_summary.qmd" = c("Sample_Env"),
        "short_veg_env.qmd" = c("vw_USysAllVeg", "Sample_Env", "Sample_SU", "Sample_Lump", "LayerCode", "lists.USysAllSpecs"),
        "lifeform.qmd" = c("vw_USysAllVeg", "Sample_SU", "Sample_Lump", "LayerCode", "lists.USysAllSpecs"),
        "flat_hierarchy.qmd" = c("Sample_Hierarchy"),
        "hierarchy.qmd" = c("Sample_Hierarchy"),
        "short_veg_hierarchy.qmd" = c("vw_USysAllVeg", "Sample_SU", "Sample_Lump", "LayerCode", "lists.USysAllSpecs"),
        "short_veg_order_hierarchy.qmd" = c("vw_USysAllVeg", "Sample_SU", "Sample_Lump", "LayerCode", "lists.USysAllSpecs"),
        "veg_layer_a.qmd" = c("vw_USysAllVeg"),
        "veg_layer_c.qmd" = c("vw_USysAllVeg"),
        "veg_layer_d.qmd" = c("vw_USysAllVeg"),
        "bec_labels.qmd" = c("Sample_Env"),
        "quality_control.qmd" = c("Sample_SU", "Sample_Admin", "Sample_Env", "Sample_Veg", "lists.USysTableOfLists")
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
    
    output$report_ctx <- renderText({
      req(sys_state$CurrSU)
      paste("Ready to generate report for Plot:", sys_state$CurrSU)
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
            choices = c("Mean cover" = "mean", "Sum per plot" = "sum_per_plot"),
            selected = "mean"
          ),
          col_widths = c(4, 4, 4)
        ),
        layout_columns(
          numericInput(ns("veg_presence_min"), "Presence min (%)", value = 0, min = 0, max = 100, step = 1),
          numericInput(ns("veg_cover_min"), "Cover min", value = 0, min = 0, step = 1),
          selectInput(
            ns("veg_show_common"),
            "Extra label",
            choices = c(
              "None" = "none",
              "English name" = "english",
              "Short guide name" = "short",
              "Combined English" = "combined",
              "Species code" = "code"
            ),
            selected = "none"
          ),
          col_widths = c(3, 3, 6)
        )
      )
    })

    output$hier_params_ui <- renderUI({
      req(input$report_template)
      if (!(input$report_template %in% c("hierarchy.qmd", "flat_hierarchy.qmd"))) return(NULL)

      tagList(
        tags$hr(),
        tags$h5("Hierarchy Filters"),
        layout_columns(
          numericInput(ns("hier_cutoff_level"), "Lowest level", value = 11, min = 1, step = 1),
          col_widths = c(3)
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
    }, ignoreInit = TRUE)

    observeEvent(sys_state$CurrSU, {
      if (!is.null(input$veg_plot_numbers)) {
        updateTextInput(session, "veg_plot_numbers", value = as.character(sys_state$CurrSU))
      }
    }, ignoreInit = TRUE)

    build_report_params <- function(template_name, parquet_dir = "") {
      db_path <- file.path(getwd(), "data", "vpro.duckdb")
      if (identical(template_name, "quality_control.qmd")) {
        list(
          db_path = db_path,
          parquet_dir = parquet_dir,
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
        list(
          plot_number = as.character(sys_state$CurrSU),
          plot_numbers = trimws(value_or(input$veg_plot_numbers, "")),
          site_unit = trimws(value_or(input$veg_site_unit, "")),
          project_id = trimws(value_or(input$veg_project_id, "")),
          group_by = value_or(input$veg_group_by, "layer"),
          order_by = value_or(input$veg_order_by, "species"),
          avg_type = value_or(input$veg_avg_type, "mean"),
          presence_min = as.numeric(value_or(input$veg_presence_min, 0)),
          cover_min = as.numeric(value_or(input$veg_cover_min, 0)),
          show_common = value_or(input$veg_show_common, "none"),
          apply_lumping = isTRUE(input$veg_apply_lumping),
          constancy_format = isTRUE(input$veg_constancy_format),
          db_path = db_path,
          parquet_dir = parquet_dir
        )
      } else if (template_name %in% c("hierarchy.qmd", "flat_hierarchy.qmd")) {
        list(
          db_path = db_path,
          parquet_dir = parquet_dir,
          cutoff_level = as.integer(value_or(input$hier_cutoff_level, 11))
        )
      } else {
        list(
          plot_number = as.character(sys_state$CurrSU),
          db_path = db_path,
          parquet_dir = parquet_dir
        )
      }
    }
    
    preview_path <- reactiveVal(NULL)
    report_file <- reactiveVal(NULL)
    report_url <- reactiveVal(NULL)

    observeEvent(input$preview_report, {
      req(sys_state$CurrSU)
      req(input$report_template)

      tmp_dir <- file.path(tempdir(), "report_preview")
      if (!dir.exists(tmp_dir)) dir.create(tmp_dir, recursive = TRUE)

      qmd_path <- file.path(getwd(), "reports", input$report_template)
      if (!file.exists(qmd_path)) {
        showNotification("Report template not found!", type = "error")
        return()
      }

      tmp_qmd <- file.path(tmp_dir, basename(input$report_template))
      file.copy(qmd_path, tmp_qmd, overwrite = TRUE)

      tryCatch({
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
          output_format = "html",
          execute_params = build_report_params(input$report_template, parquet_dir = parquet_dir)
        )

        out_generated <- file.path(tmp_dir, paste0(tools::file_path_sans_ext(basename(input$report_template)), ".html"))
        if (file.exists(out_generated)) {
          preview_path(out_generated)
          report_file(out_generated)
        } else {
          showNotification("Preview generation failed.", type = "error")
        }
      }, error = function(e) {
        showNotification(paste("Preview error:", e$message), type = "error")
      })
    })

    output$report_preview <- renderUI({
      preview_file <- preview_path()
      if (is.null(preview_file) || !file.exists(preview_file)) return(NULL)

      addResourcePath("report_preview", dirname(preview_file))
      tags$iframe(
        src = file.path("report_preview", basename(preview_file)),
        style = "width:100%; height:600px; border:1px solid #ccc;"
      )
    })

    observeEvent(report_file(), {
      report_path <- report_file()
      if (is.null(report_path) || !file.exists(report_path)) return()
      addResourcePath("report_output", dirname(report_path))
      report_url(file.path("report_output", basename(report_path)))
    })

    observeEvent(report_url(), {
      target_url <- report_url()
      if (is.null(target_url) || !nzchar(target_url)) return()
      shinyjs::runjs(paste0("window.open(", js_quote(target_url), ", '_blank');"))
    })

    output$report_open_link <- renderUI({
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

    output$dl_report <- downloadHandler(
      filename = function() {
        template_name <- tools::file_path_sans_ext(basename(input$report_template))
        ext <- if (is.null(input$report_format) || input$report_format == "") "html" else input$report_format
        paste0(template_name, "_", sys_state$CurrSU, "_", Sys.Date(), ".", ext)
      },
      content = function(file) {
        req(sys_state$CurrSU)
        req(input$report_template)
        
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
        tmp_qmd <- file.path(tmp_dir, "site_summary.qmd")
        file.copy(qmd_path, tmp_qmd, overwrite = TRUE)
        
        out_format <- if (is.null(input$report_format) || input$report_format == "") "html" else input$report_format

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
