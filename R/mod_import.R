mod_import_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      full_screen = TRUE,
      card_header("Import"),
      layout_columns(
        fileInput(ns("import_file"), "CSV or ZIP", accept = c(".csv", ".zip")),
        selectInput(ns("target_table"), "Target Table", choices = NULL),
        actionButton(ns("import_analyze"), "Analyze", class = "btn-secondary"),
        actionButton(ns("import_apply"), "Import", class = "btn-primary"),
        col_widths = c(5, 3, 2, 2)
      ),
      checkboxGroupInput(ns("zip_tables"), "ZIP Tables to Import", choices = NULL),
      verbatimTextOutput(ns("import_status")),
      DT::DTOutput(ns("import_preview")),
      DT::DTOutput(ns("import_compliance"))
    )
  )
}

mod_import_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    rv <- reactiveValues(
      status = "",
      preview = NULL,
      target_fields = NULL,
      compliance = NULL,
      zip_meta = NULL,
      zip_map = NULL,
      import_results = NULL
    )

    observe({
      tables <- DBI::dbListTables(con)
      tables <- tables[!grepl("^duckdb_|^sqlite_", tables)]
      updateSelectInput(session, "target_table", choices = c("(none)" = "", tables))
    })

    infer_table_name <- function(file_name) {
      base <- tools::file_path_sans_ext(basename(file_name))
      base
    }

    csv_row_count <- function(path) {
      lines <- tryCatch(length(utils::count.fields(path)), error = function(e) NA_integer_)
      if (is.na(lines)) return(NA_integer_)
      max(lines - 1, 0)
    }

    observeEvent(input$import_analyze, {
      req(input$import_file)

      file_path <- input$import_file$datapath
      file_name <- input$import_file$name
      ext <- tolower(tools::file_ext(file_name))

      rv$import_results <- NULL
      rv$zip_meta <- NULL
      rv$zip_map <- NULL
      updateCheckboxGroupInput(session, "zip_tables", choices = NULL, selected = NULL)

      if (ext == "csv") {
        tryCatch({
          rv$preview <- utils::read.csv(file_path, nrows = 100, stringsAsFactors = FALSE)
          status <- paste("Loaded", nrow(rv$preview), "rows from", file_name)

          if (!is.null(input$target_table) && nzchar(input$target_table)) {
            target_fields <- DBI::dbListFields(con, input$target_table)
            rv$target_fields <- target_fields
            missing_cols <- setdiff(target_fields, names(rv$preview))
            extra_cols <- setdiff(names(rv$preview), target_fields)

            if (length(missing_cols) > 0) {
              status <- paste0(status, " | Missing: ", paste(missing_cols, collapse = ", "))
            }
            if (length(extra_cols) > 0) {
              status <- paste0(status, " | Extra: ", paste(extra_cols, collapse = ", "))
            }
            if (length(missing_cols) == 0 && length(extra_cols) == 0) {
              status <- paste0(status, " | Columns match target")
            }
          }

          rv$status <- status
        }, error = function(e) {
          rv$status <- paste("CSV read error:", e$message)
          rv$preview <- NULL
        })
        return()
      }

      if (ext == "zip") {
        tryCatch({
          temp_dir <- tempfile("vpro_import_")
          dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
          utils::unzip(file_path, exdir = temp_dir)
          csv_paths <- list.files(temp_dir, pattern = "\\.csv$", full.names = TRUE, recursive = TRUE)

          if (length(csv_paths) == 0) {
            rv$status <- "ZIP contains no CSV files"
            rv$preview <- NULL
            return()
          }

          tables <- DBI::dbListTables(con)
          tables <- tables[!grepl("^duckdb_|^sqlite_", tables)]

          meta <- lapply(csv_paths, function(path) {
            table_guess <- infer_table_name(path)
            header <- tryCatch(utils::read.csv(path, nrows = 0, stringsAsFactors = FALSE),
                               error = function(e) NULL)
            cols <- if (is.null(header)) character(0) else names(header)
            row_count <- csv_row_count(path)

            if (table_guess %in% tables) {
              target_fields <- DBI::dbListFields(con, table_guess)
              missing_cols <- setdiff(target_fields, cols)
              extra_cols <- setdiff(cols, target_fields)
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
            } else {
              status <- "Unknown table"
              target_fields <- character(0)
            }

            data.frame(
              file = basename(path),
              table = table_guess,
              rows = row_count,
              status = status,
              stringsAsFactors = FALSE
            )
          })

          rv$zip_meta <- do.call(rbind, meta)
          rv$zip_map <- data.frame(
            id = seq_len(nrow(rv$zip_meta)),
            path = csv_paths,
            table = rv$zip_meta$table,
            stringsAsFactors = FALSE
          )

          choices <- setNames(
            rv$zip_map$id,
            paste0(rv$zip_meta$table, " <- ", rv$zip_meta$file)
          )
          selectable <- rv$zip_meta$table %in% tables
          updateCheckboxGroupInput(
            session,
            "zip_tables",
            choices = choices,
            selected = rv$zip_map$id[selectable]
          )

          rv$preview <- rv$zip_meta
          rv$status <- paste("ZIP contains", nrow(rv$zip_meta), "CSV files")
        }, error = function(e) {
          rv$status <- paste("ZIP read error:", e$message)
          rv$preview <- NULL
        })
        return()
      }

      rv$status <- "Unsupported file type"
      rv$preview <- NULL
    })

    observeEvent(input$import_apply, {
      req(rv$preview)

      file_name <- input$import_file$name
      ext <- tolower(tools::file_ext(file_name))

      if (ext == "zip") {
        req(rv$zip_map)
        selected <- input$zip_tables
        if (is.null(selected) || length(selected) == 0) {
          rv$status <- "Import blocked: select at least one table"
          return()
        }

        results <- list()
        for (id in selected) {
          row <- rv$zip_map[rv$zip_map$id == id, , drop = FALSE]
          if (nrow(row) == 0) next

          table <- row$table[1]
          path <- row$path[1]
          if (!nzchar(table)) {
            results[[length(results) + 1]] <- data.frame(
              table = table,
              rows = 0,
              status = "Unknown table",
              stringsAsFactors = FALSE
            )
            next
          }

          target_fields <- DBI::dbListFields(con, table)
          data <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
          if (is.null(data)) {
            results[[length(results) + 1]] <- data.frame(
              table = table,
              rows = 0,
              status = "CSV read error",
              stringsAsFactors = FALSE
            )
            next
          }

          missing_cols <- setdiff(target_fields, names(data))
          extra_cols <- setdiff(names(data), target_fields)
          if (length(missing_cols) > 0 || length(extra_cols) > 0) {
            results[[length(results) + 1]] <- data.frame(
              table = table,
              rows = nrow(data),
              status = "Column mismatch",
              stringsAsFactors = FALSE
            )
            next
          }

          tryCatch({
            DBI::dbAppendTable(con, table, data)
            results[[length(results) + 1]] <- data.frame(
              table = table,
              rows = nrow(data),
              status = "Imported",
              stringsAsFactors = FALSE
            )
          }, error = function(e) {
            results[[length(results) + 1]] <- data.frame(
              table = table,
              rows = nrow(data),
              status = paste("Import error:", e$message),
              stringsAsFactors = FALSE
            )
          })
        }

        rv$import_results <- do.call(rbind, results)
        rv$preview <- rv$import_results
        rv$status <- paste("Imported", sum(rv$import_results$status == "Imported"), "tables")
        rv$compliance <- run_compliance_checks(con, state$CurrProject)
        return()
      }

      req(input$target_table)

      if (is.null(rv$target_fields)) {
        rv$target_fields <- DBI::dbListFields(con, input$target_table)
      }

      missing_cols <- setdiff(rv$target_fields, names(rv$preview))
      extra_cols <- setdiff(names(rv$preview), rv$target_fields)

      if (length(missing_cols) > 0) {
        rv$status <- paste("Import blocked: missing columns", paste(missing_cols, collapse = ", "))
        return()
      }

      if (length(extra_cols) > 0) {
        rv$status <- paste("Import blocked: extra columns", paste(extra_cols, collapse = ", "))
        return()
      }

      tryCatch({
        DBI::dbAppendTable(con, input$target_table, rv$preview)
        rv$status <- paste("Imported", nrow(rv$preview), "rows into", input$target_table)
        rv$compliance <- run_compliance_checks(con, state$CurrProject)
      }, error = function(e) {
        rv$status <- paste("Import error:", e$message)
      })
    })

    output$import_status <- renderText({
      rv$status
    })

    output$import_preview <- DT::renderDT({
      req(rv$preview)
      DT::datatable(rv$preview, rownames = FALSE, options = list(pageLength = 10, ordering = FALSE))
    })

    output$import_compliance <- DT::renderDT({
      req(rv$compliance)
      DT::datatable(rv$compliance$detail_tibble, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })
  })
}
