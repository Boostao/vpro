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
        shinyjs::disabled(actionButton(ns("import_apply"), "Import", class = "btn-primary")),
        col_widths = c(5, 3, 2, 2)
      ),
      checkboxGroupInput(ns("zip_tables"), "ZIP Tables to Import", choices = NULL),
      uiOutput(ns("import_ready")),
      uiOutput(ns("import_compliance_summary")),
      verbatimTextOutput(ns("import_status")),
      DT::DTOutput(ns("import_validation")),
      DT::DTOutput(ns("import_preview")),
      DT::DTOutput(ns("import_results_summary")),
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
      import_validation = NULL,
      zip_meta = NULL,
      zip_map = NULL,
      import_results = NULL
    )

    compliance_tables <- c("Sample_Env", "Sample_Veg")

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

    build_csv_validation <- function(file_path, file_name, preview, target_table) {
      total_rows <- csv_row_count(file_path)
      validation <- data.frame(
        file = file_name,
        table = if (!is.null(target_table) && nzchar(target_table)) target_table else "",
        rows = total_rows,
        missing = "",
        extra = "",
        status = "No target selected",
        stringsAsFactors = FALSE
      )

      status <- paste("Loaded", nrow(preview), "rows from", file_name)

      if (!is.null(target_table) && nzchar(target_table)) {
        target_fields <- DBI::dbListFields(con, target_table)
        rv$target_fields <- target_fields
        missing_cols <- setdiff(target_fields, names(preview))
        extra_cols <- setdiff(names(preview), target_fields)

        validation$missing <- if (length(missing_cols) > 0) paste(missing_cols, collapse = ", ") else ""
        validation$extra <- if (length(extra_cols) > 0) paste(extra_cols, collapse = ", ") else ""
        validation$status <- if (length(missing_cols) == 0 && length(extra_cols) == 0) {
          "Columns match target"
        } else {
          "Column mismatch"
        }

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

      list(status = status, validation = validation)
    }

    observeEvent(input$import_analyze, {
      req(input$import_file)

      file_path <- input$import_file$datapath
      file_name <- input$import_file$name
      ext <- tolower(tools::file_ext(file_name))

      rv$import_results <- NULL
      rv$zip_meta <- NULL
      rv$zip_map <- NULL
      rv$import_validation <- NULL
      updateCheckboxGroupInput(session, "zip_tables", choices = NULL, selected = NULL)

      if (ext == "csv") {
        tryCatch({
          rv$preview <- utils::read.csv(file_path, nrows = 100, stringsAsFactors = FALSE)
          result <- build_csv_validation(file_path, file_name, rv$preview, input$target_table)
          rv$status <- result$status
          rv$import_validation <- result$validation
        }, error = function(e) {
          rv$status <- paste("CSV read error:", e$message)
          rv$preview <- NULL
          rv$import_validation <- NULL
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

          choice_labels <- ifelse(
            rv$zip_meta$status == "Columns match target",
            paste0(rv$zip_meta$table, " <- ", rv$zip_meta$file),
            paste0(rv$zip_meta$table, " <- ", rv$zip_meta$file, " (", rv$zip_meta$status, ")")
          )
          choices <- setNames(rv$zip_map$id, choice_labels)
          selectable <- rv$zip_meta$table %in% tables
          updateCheckboxGroupInput(
            session,
            "zip_tables",
            choices = choices,
            selected = rv$zip_map$id[selectable]
          )

          rv$preview <- rv$zip_meta
          rv$status <- paste("ZIP contains", nrow(rv$zip_meta), "CSV files")
          rv$import_validation <- rv$zip_meta
        }, error = function(e) {
          rv$status <- paste("ZIP read error:", e$message)
          rv$preview <- NULL
          rv$import_validation <- NULL
        })
        return()
      }

      rv$status <- "Unsupported file type"
      rv$preview <- NULL
      rv$import_validation <- NULL
    })

    observeEvent(input$target_table, {
      req(input$import_file)
      req(rv$preview)

      file_name <- input$import_file$name
      ext <- tolower(tools::file_ext(file_name))
      if (ext != "csv") return()

      result <- build_csv_validation(input$import_file$datapath, file_name, rv$preview, input$target_table)
      rv$status <- result$status
      rv$import_validation <- result$validation
    })

    import_ready <- reactive({
      req(input$import_file)
      if (is.null(rv$import_validation) || nrow(rv$import_validation) == 0) return(FALSE)

      file_name <- input$import_file$name
      ext <- tolower(tools::file_ext(file_name))

      if (ext == "zip") {
        if (is.null(input$zip_tables) || length(input$zip_tables) == 0) return(FALSE)
        selected_tables <- rv$zip_map$table[rv$zip_map$id %in% input$zip_tables]
        selected_rows <- rv$import_validation[rv$import_validation$table %in% selected_tables, , drop = FALSE]
        if (nrow(selected_rows) == 0) return(FALSE)
        return(all(selected_rows$status == "Columns match target"))
      }

      if (ext == "csv") {
        if (is.null(input$target_table) || !nzchar(input$target_table)) return(FALSE)
        return(all(rv$import_validation$status == "Columns match target"))
      }

      FALSE
    })

    observe({
      if (isTRUE(import_ready())) {
        shinyjs::enable("import_apply")
      } else {
        shinyjs::disable("import_apply")
      }
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

        if (!is.null(rv$import_validation) && nrow(rv$import_validation) > 0) {
          selected_rows <- rv$import_validation[rv$import_validation$table %in% rv$zip_map$table[rv$zip_map$id %in% selected], , drop = FALSE]
          bad_rows <- selected_rows$status != "Columns match target"
          if (length(bad_rows) > 0 && any(bad_rows)) {
            rv$status <- "Import blocked: validation errors detected"
            return()
          }
        }

        selected_tables <- character()

        pending_imports <- list()
        results_status <- list()
        for (id in selected) {
          row <- rv$zip_map[rv$zip_map$id == id, , drop = FALSE]
          if (nrow(row) == 0) next

          table <- row$table[1]
          path <- row$path[1]
          selected_tables <- c(selected_tables, table)
          if (!nzchar(table)) {
            results_status[[length(results_status) + 1]] <- data.frame(
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
            results_status[[length(results_status) + 1]] <- data.frame(
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
            results_status[[length(results_status) + 1]] <- data.frame(
              table = table,
              rows = nrow(data),
              status = "Column mismatch",
              stringsAsFactors = FALSE
            )
            next
          }

          pending_imports[[length(pending_imports) + 1]] <- list(table = table, data = data)
        }

        use_compliance <- any(selected_tables %in% compliance_tables)
        commit_ok <- TRUE

        if (use_compliance) {
          commit_ok <- FALSE
          DBI::dbBegin(con)
          on.exit({
            if (!commit_ok) {
              try(DBI::dbRollback(con), silent = TRUE)
            }
          }, add = TRUE)
        }

        for (entry in pending_imports) {
          table <- entry$table
          data <- entry$data

          if (!is.data.frame(data)) {
            results_status[[length(results_status) + 1]] <- data.frame(
              table = table,
              rows = 0,
              status = "CSV read error",
              stringsAsFactors = FALSE
            )
            next
          }

          tryCatch({
            DBI::dbAppendTable(con, table, data)
            results_status[[length(results_status) + 1]] <- data.frame(
              table = table,
              rows = nrow(data),
              status = "Imported",
              stringsAsFactors = FALSE
            )
          }, error = function(e) {
            results_status[[length(results_status) + 1]] <- data.frame(
              table = table,
              rows = nrow(data),
              status = paste("Import error:", e$message),
              stringsAsFactors = FALSE
            )
          })
        }

        rv$import_results <- if (length(results_status) > 0) do.call(rbind, results_status) else data.frame()

        if (use_compliance) {
          rv$compliance <- run_compliance_checks(con, state$CurrProject)
          if (!isTRUE(rv$compliance$passed)) {
            rv$import_results$status <- "Rolled back (compliance failed)"
            rv$preview <- rv$import_results
            rv$status <- "Import blocked: compliance checks failed"
            return()
          }

          DBI::dbCommit(con)
          commit_ok <- TRUE
        }

        for (entry in pending_imports) {
          if (entry$table %in% compliance_tables) {
            log_audit_rows(con, state$CurrProject, "Import", entry$table, entry$data)
          }
        }

        rv$preview <- rv$import_results
        rv$status <- paste("Imported", sum(rv$import_results$status == "Imported"), "tables")
        return()
      }

      req(input$target_table)

      if (!is.null(rv$import_validation) && nrow(rv$import_validation) > 0) {
        if (rv$import_validation$status[1] != "Columns match target") {
          rv$status <- "Import blocked: validation errors detected"
          return()
        }
      }

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

      use_compliance <- input$target_table %in% compliance_tables
      commit_ok <- TRUE
      if (use_compliance) {
        commit_ok <- FALSE
        DBI::dbBegin(con)
        on.exit({
          if (!commit_ok) {
            try(DBI::dbRollback(con), silent = TRUE)
          }
        }, add = TRUE)
      }

      tryCatch({
        DBI::dbAppendTable(con, input$target_table, rv$preview)
        if (use_compliance) {
          rv$compliance <- run_compliance_checks(con, state$CurrProject)
          if (!isTRUE(rv$compliance$passed)) {
            rv$status <- "Import blocked: compliance checks failed"
            return()
          }

          DBI::dbCommit(con)
          commit_ok <- TRUE
        }

        if (input$target_table %in% compliance_tables) {
          log_audit_rows(con, state$CurrProject, "Import", input$target_table, rv$preview)
        }

        rv$import_results <- data.frame(
          table = input$target_table,
          rows = nrow(rv$preview),
          status = "Imported",
          stringsAsFactors = FALSE
        )
        rv$status <- paste("Imported", nrow(rv$preview), "rows into", input$target_table)
      }, error = function(e) {
        rv$status <- paste("Import error:", e$message)
      })
    })

    output$import_status <- renderText({
      rv$status
    })

    output$import_ready <- renderUI({
      req(rv$import_validation)
      if (nrow(rv$import_validation) == 0) return(NULL)

      all_ok <- all(rv$import_validation$status == "Columns match target")
      label <- if (all_ok) "Ready to import" else "Not ready: validation errors"
      badge_class <- if (all_ok) "bg-success" else "bg-danger"

      tags$span(
        label,
        class = paste("badge", badge_class)
      )
    })

    output$import_compliance_summary <- renderUI({
      req(rv$compliance)

      passed <- isTRUE(rv$compliance$passed)
      issue_count <- if (!is.null(rv$compliance$detail_tibble)) nrow(rv$compliance$detail_tibble) else 0
      label <- if (passed) {
        "Compliance passed"
      } else {
        paste("Compliance issues:", issue_count)
      }
      badge_class <- if (passed) "bg-success" else "bg-warning"

      tags$span(
        label,
        class = paste("badge", badge_class)
      )
    })

    output$import_validation <- DT::renderDT({
      req(rv$import_validation)
      DT::datatable(rv$import_validation, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })

    output$import_preview <- DT::renderDT({
      req(rv$preview)
      DT::datatable(rv$preview, rownames = FALSE, options = list(pageLength = 10, ordering = FALSE))
    })

    output$import_results_summary <- DT::renderDT({
      req(rv$import_results)
      if (nrow(rv$import_results) == 0) return(NULL)
      summary <- aggregate(
        list(count = rv$import_results$status),
        by = list(status = rv$import_results$status),
        FUN = length
      )
      DT::datatable(summary, rownames = FALSE, options = list(pageLength = 6, ordering = FALSE))
    })

    output$import_compliance <- DT::renderDT({
      req(rv$compliance)
      DT::datatable(rv$compliance$detail_tibble, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })
  })
}
