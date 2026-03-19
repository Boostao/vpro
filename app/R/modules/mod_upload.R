mod_upload_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Upload"),
      p("Upload and stage datasets for review."),
      layout_columns(
        fileInput(ns("upload_file"), "Dataset", accept = c(".csv", ".zip")),
        selectInput(
          ns("upload_table"),
          "Target table",
          choices = c(
            "(auto from zip)" = "",
            "sample_env" = "sample_env",
            "sample_su" = "sample_su",
            "sample_veg" = "sample_veg"
          )
        ),
        textInput(ns("upload_project"), "Project ID", value = ""),
        actionButton(ns("upload_analyze"), "Analyze", class = "btn-secondary"),
        shinyjs::disabled(actionButton(ns("upload_stage"), "Stage Upload", class = "btn-primary")),
        col_widths = c(4, 3, 2, 2, 1)
      ),
      checkboxGroupInput(ns("upload_zip_tables"), "ZIP tables", choices = NULL),
      textOutput(ns("upload_status")),
      textOutput(ns("upload_compliance_status")),
      DT::DTOutput(ns("upload_validation")),
      DT::DTOutput(ns("upload_results")),
      DT::DTOutput(ns("upload_compliance"))
    )
  )
}

mod_upload_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(
      status = "",
      validation = NULL,
      zip_map = NULL,
      staged = NULL,
      compliance = NULL
    )

    staging_tables <- c("sample_env", "sample_su", "sample_veg")

    observe({
      if (!is.null(state$CurrProject) && nzchar(state$CurrProject) && !nzchar(input$upload_project)) {
        updateTextInput(session, "upload_project", value = state$CurrProject)
      }
    })

    get_staging_fields <- function(table_name) {
      sync_require_cloud(con, allow_attach = TRUE)
      DBI::dbListFields(con, paste0("master.staging.", table_name))
    }

    build_validation <- function(data, table_name, file_name) {
      fields <- get_staging_fields(table_name)
      required <- setdiff(fields, c("id", "merge_request_id", "modified_by", "row_version", "last_modified_utc"))
      missing_cols <- setdiff(required, names(data))
      extra_cols <- setdiff(names(data), fields)

      can_fill_project <- "project_id" %in% missing_cols && nzchar(input$upload_project)
      if (can_fill_project) {
        missing_cols <- setdiff(missing_cols, "project_id")
      }

      status <- if (length(missing_cols) == 0 && length(extra_cols) == 0) {
        "Columns match target"
      } else {
        paste(
          c(
            if (length(missing_cols) > 0) paste("Missing:", paste(missing_cols, collapse = ", ")) else NULL,
            if (length(extra_cols) > 0) paste("Extra:", paste(extra_cols, collapse = ", ")) else NULL
          ),
          collapse = " | "
        )
      }

      data.frame(
        file = file_name,
        table = table_name,
        rows = nrow(data),
        status = status,
        stringsAsFactors = FALSE
      )
    }


    observeEvent(input$upload_analyze, {
      req(input$upload_file)

      rv$validation <- NULL
      rv$zip_map <- NULL
      rv$staged <- NULL
      rv$compliance <- NULL
      updateCheckboxGroupInput(session, "upload_zip_tables", choices = NULL, selected = NULL)

      file_path <- input$upload_file$datapath
      file_name <- input$upload_file$name
      ext <- tolower(tools::file_ext(file_name))

      if (ext == "csv") {
        if (!nzchar(input$upload_table)) {
          rv$status <- "Select a target table for CSV uploads."
          return()
        }
        table_name <- input$upload_table
        if (!table_name %in% staging_tables) {
          rv$status <- "Unsupported target table."
          return()
        }
        data <- tryCatch(utils::read.csv(file_path, stringsAsFactors = FALSE), error = function(e) NULL)
        if (is.null(data)) {
          rv$status <- "CSV read error."
          return()
        }
        rv$validation <- build_validation(data, table_name, file_name)
        rv$status <- paste("Analyzed", file_name)
        return()
      }

      if (ext == "zip") {
        temp_dir <- tempfile("vpro_upload_")
        dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
        utils::unzip(file_path, exdir = temp_dir)
        csv_paths <- list.files(temp_dir, pattern = "\\.csv$", full.names = TRUE, recursive = TRUE)
        if (length(csv_paths) == 0) {
          rv$status <- "ZIP contains no CSV files."
          return()
        }

        meta <- list()
        for (path in csv_paths) {
          table_name <- tools::file_path_sans_ext(basename(path))
          if (!(table_name %in% staging_tables)) {
            next
          }
          data <- tryCatch(utils::read.csv(path, nrows = 50, stringsAsFactors = FALSE), error = function(e) NULL)
          if (is.null(data)) next
          meta[[length(meta) + 1]] <- build_validation(data, table_name, basename(path))
        }

        if (length(meta) == 0) {
          rv$status <- "ZIP contains no recognized staging tables."
          return()
        }

        rv$validation <- do.call(rbind, meta)
        rv$zip_map <- data.frame(
          id = seq_len(nrow(rv$validation)),
          table = rv$validation$table,
          path = csv_paths[match(rv$validation$file, basename(csv_paths))],
          stringsAsFactors = FALSE
        )

        choices <- setNames(rv$zip_map$id, paste0(rv$zip_map$table, " <- ", basename(rv$zip_map$path)))
        updateCheckboxGroupInput(session, "upload_zip_tables", choices = choices, selected = rv$zip_map$id)
        rv$status <- paste("Analyzed ZIP with", nrow(rv$validation), "tables")
        return()
      }

      rv$status <- "Unsupported file type."
    })

    observe({
      ready <- !is.null(rv$validation) && nrow(rv$validation) > 0 && all(rv$validation$status == "Columns match target")
      if (isTRUE(ready)) {
        shinyjs::enable("upload_stage")
      } else {
        shinyjs::disable("upload_stage")
      }
    })

    observeEvent(input$upload_stage, {
      req(input$upload_file)
      req(rv$validation)
      auth_init_state(state)
      tryCatch({
        auth_require_permission(state, "create:merge_requests")
      }, error = function(e) {
        rv$status <- e$message
        return()
      })
      sync_require_cloud(con, allow_attach = TRUE)

      if (!nzchar(input$upload_project)) {
        rv$status <- "Project ID is required to stage uploads."
        return()
      }

      file_name <- input$upload_file$name
      ext <- tolower(tools::file_ext(file_name))
      submitter <- Sys.getenv("USER", "unknown")
      merge_request_id <- sync_create_merge_request(con, input$upload_project, submitter)

      stage_one <- function(table_name, data) {
        fields <- get_staging_fields(table_name)
        required <- setdiff(fields, c("id", "merge_request_id", "modified_by", "row_version", "last_modified_utc"))
        missing_cols <- setdiff(required, names(data))

        if ("project_id" %in% missing_cols) {
          data$project_id <- input$upload_project
          missing_cols <- setdiff(missing_cols, "project_id")
        }

        if (length(missing_cols) > 0) {
          return(list(ok = FALSE, status = paste("Missing columns:", paste(missing_cols, collapse = ", "))))
        }

        data$merge_request_id <- merge_request_id
        data$modified_by <- submitter

        insert_cols <- intersect(fields, names(data))
        data <- data[, insert_cols, drop = FALSE]
        DBI::dbAppendTable(con, paste0("master.staging.", table_name), data)
        list(ok = TRUE, rows = nrow(data))
      }

      results <- list()

      if (ext == "csv") {
        table_name <- input$upload_table
        data <- utils::read.csv(input$upload_file$datapath, stringsAsFactors = FALSE)
        results[[table_name]] <- stage_one(table_name, data)
      }

      if (ext == "zip") {
        req(rv$zip_map)
        selected <- input$upload_zip_tables
        if (is.null(selected) || length(selected) == 0) {
          rv$status <- "Select at least one table to stage."
          return()
        }
        for (id in selected) {
          entry <- rv$zip_map[rv$zip_map$id == id, , drop = FALSE]
          if (nrow(entry) == 0) next
          data <- utils::read.csv(entry$path[1], stringsAsFactors = FALSE)
          results[[entry$table[1]]] <- stage_one(entry$table[1], data)
        }
      }

      status_rows <- lapply(names(results), function(name) {
        res <- results[[name]]
        data.frame(
          table = name,
          rows = if (isTRUE(res$ok)) res$rows else 0,
          status = if (isTRUE(res$ok)) "Staged" else res$status,
          stringsAsFactors = FALSE
        )
      })

      rv$staged <- if (length(status_rows) > 0) do.call(rbind, status_rows) else data.frame()

      env_count <- if (!is.null(results$sample_env) && isTRUE(results$sample_env$ok)) results$sample_env$rows else 0
      veg_count <- if (!is.null(results$sample_veg) && isTRUE(results$sample_veg$ok)) results$sample_veg$rows else 0

      DBI::dbExecute(
        con,
        "UPDATE master.admin.merge_requests SET env_record_count = ?, veg_record_count = ? WHERE id = ?",
        list(env_count, veg_count, merge_request_id)
      )

      rv$compliance <- staging_compliance_checks(con, merge_request_id, input$upload_project)

      report_json <- NULL
      if (!is.null(rv$compliance) && requireNamespace("jsonlite", quietly = TRUE)) {
        report_json <- jsonlite::toJSON(
          list(summary = rv$compliance$summary_tibble, details = rv$compliance$detail_tibble),
          auto_unbox = TRUE,
          na = "null"
        )
      }

      compliance_ok <- isTRUE(rv$compliance$passed)
      DBI::dbExecute(
        con,
        "UPDATE master.admin.merge_requests
         SET compliance_passed = ?, compliance_report = ?
         WHERE id = ?",
        list(compliance_ok, report_json, merge_request_id)
      )

      if (!compliance_ok) {
        DBI::dbExecute(
          con,
          "UPDATE master.admin.merge_requests
           SET status = 'rejected'
           WHERE id = ?",
          list(merge_request_id)
        )
        DBI::dbExecute(con, "DELETE FROM master.staging.sample_env WHERE merge_request_id = ?", list(merge_request_id))
        DBI::dbExecute(con, "DELETE FROM master.staging.sample_su WHERE merge_request_id = ?", list(merge_request_id))
        DBI::dbExecute(con, "DELETE FROM master.staging.sample_veg WHERE merge_request_id = ?", list(merge_request_id))
        rv$status <- paste("Compliance failed; staging cleared for request", merge_request_id)
        return()
      }

      rv$status <- paste("Staged merge request", merge_request_id)
    })

    output$upload_status <- renderText(rv$status)

    output$upload_compliance_status <- renderText({
      result <- rv$compliance
      if (is.null(result)) return("")
      issue_count <- if (!is.null(result$detail_tibble)) nrow(result$detail_tibble) else 0
      if (isTRUE(result$passed)) "Compliance passed" else paste("Compliance issues:", issue_count)
    })

    output$upload_validation <- DT::renderDT({
      req(rv$validation)
      DT::datatable(rv$validation, rownames = FALSE, options = list(pageLength = 6))
    })

    output$upload_results <- DT::renderDT({
      req(rv$staged)
      DT::datatable(rv$staged, rownames = FALSE, options = list(pageLength = 6))
    })

    output$upload_compliance <- DT::renderDT({
      req(rv$compliance)
      if (is.null(rv$compliance$detail_tibble) || nrow(rv$compliance$detail_tibble) == 0) return(NULL)
      DT::datatable(rv$compliance$detail_tibble, rownames = FALSE, options = list(pageLength = 6, scrollX = TRUE))
    })
  })
}
