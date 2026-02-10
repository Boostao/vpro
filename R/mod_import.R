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
      tags$hr(),
      tags$h5("Import from Access (Windows only)"),
      tags$p("Windows only: install the Microsoft Access ODBC driver. macOS/Linux users should export to CSV/ZIP first."),
      layout_columns(
        fileInput(ns("access_file"), "Access .mdb/.accdb", accept = c(".mdb", ".accdb")),
        textInput(ns("access_project_id"), "New Project ID (optional)", value = ""),
        selectInput(ns("access_project"), "Project", choices = NULL),
        actionButton(ns("access_analyze"), "Analyze", class = "btn-secondary"),
        shinyjs::disabled(actionButton(ns("access_import"), "Import Project", class = "btn-primary")),
        col_widths = c(4, 3, 2, 2, 1)
      ),
      verbatimTextOutput(ns("access_status")),
      DT::DTOutput(ns("access_results")),
      checkboxGroupInput(ns("zip_tables"), "ZIP Tables to Import", choices = NULL),
      uiOutput(ns("import_ready")),
      uiOutput(ns("import_compliance_summary")),
      verbatimTextOutput(ns("import_status")),
      DT::DTOutput(ns("import_validation")),
      DT::DTOutput(ns("import_preview")),
      DT::DTOutput(ns("import_results_summary")),
      DT::DTOutput(ns("import_compliance_by_project")),
      DT::DTOutput(ns("import_compliance"))
    )
  )
}

import_suffix_map <- function() {
  c(
    env = "Sample_Env",
    veg = "Sample_Veg",
    humus = "Sample_Humus",
    mineral = "Sample_Mineral",
    other = "Sample_Other",
    admin = "Sample_Admin",
    metadata = "Sample_Metadata",
    audit = "Sample_Audit",
    su = "Sample_SU"
  )
}

access_suffix_map <- function() {
  c(
    env = "Env",
    veg = "Veg",
    humus = "Humus",
    mineral = "Mineral",
    other = "Other",
    admin = "Admin",
    metadata = "Metadata",
    audit = "Audit",
    su = "SU"
  )
}

resolve_import_target <- function(file_base, tables) {
  base <- tools::file_path_sans_ext(basename(file_base))
  if (base %in% tables) return(list(table = base, project_id = NULL))

  suffixes <- names(import_suffix_map())
  pattern <- paste0("_(", paste(suffixes, collapse = "|"), ")$")
  match <- regexpr(pattern, base, ignore.case = TRUE)
  if (match[1] == -1) return(list(table = base, project_id = NULL))

  suffix <- tolower(regmatches(base, match))
  suffix <- sub("^_", "", suffix)
  project_id <- substr(base, 1, match[1] - 1)
  target <- import_suffix_map()[[suffix]]
  if (is.null(target)) target <- base

  list(table = target, project_id = project_id)
}

align_import_columns <- function(data, target_fields, allow_missing = character(0)) {
  if (is.null(target_fields) || length(target_fields) == 0) {
    return(list(data = data, missing = character(0), extra = character(0), ok = TRUE))
  }
  data_names <- names(data)
  target_lower <- tolower(target_fields)
  data_lower <- tolower(data_names)
  allow_missing <- tolower(allow_missing)

  missing <- setdiff(target_lower, data_lower)
  if (length(allow_missing) > 0) {
    missing <- setdiff(missing, allow_missing)
  }
  extra <- setdiff(data_lower, target_lower)
  ok <- length(missing) == 0 && length(extra) == 0

  if (ok) {
    order_idx <- match(target_lower, data_lower)
    data_out <- data.frame(stringsAsFactors = FALSE)
    for (i in seq_along(target_fields)) {
      if (!is.na(order_idx[i])) {
        data_out[[target_fields[i]]] <- data[[order_idx[i]]]
      } else if (target_lower[i] %in% allow_missing) {
        data_out[[target_fields[i]]] <- rep(NA, nrow(data))
      }
    }
    data <- data_out
  }

  list(data = data, missing = missing, extra = extra, ok = ok)
}

apply_project_override <- function(data, target_fields, project_id) {
  if (is.null(project_id) || !nzchar(project_id)) return(data)
  if (is.null(target_fields) || length(target_fields) == 0) return(data)

  idx <- match("projectid", tolower(target_fields))
  if (is.na(idx)) return(data)

  col_name <- target_fields[[idx]]
  if (!col_name %in% names(data)) {
    data[[col_name]] <- project_id
    return(data)
  }

  missing <- is.na(data[[col_name]]) | data[[col_name]] == ""
  if (any(missing)) {
    data[[col_name]][missing] <- project_id
  }

  data
}

project_exists <- function(con, project_id) {
  if (is.null(project_id) || !nzchar(project_id)) return(FALSE)
  if (DBI::dbExistsTable(con, "Sample_Metadata")) {
    res <- DBI::dbGetQuery(con, "SELECT 1 FROM Sample_Metadata WHERE ProjectID = ? LIMIT 1", list(project_id))
    if (nrow(res) > 0) return(TRUE)
  }
  if (DBI::dbExistsTable(con, "Sample_Env")) {
    res <- DBI::dbGetQuery(con, "SELECT 1 FROM Sample_Env WHERE ProjectID = ? LIMIT 1", list(project_id))
    if (nrow(res) > 0) return(TRUE)
  }
  FALSE
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
      import_results = NULL,
      import_project_override = NULL,
      access_tables = NULL,
      access_projects = NULL,
      access_status = "",
      access_results = NULL
    )

    compliance_tables <- c("Sample_Env", "Sample_Veg")

    require_import_permission <- function() {
      if (!auth_is_authenticated(state)) {
        showNotification("Sign in required.", type = "error")
        return(FALSE)
      }
      allowed <- c("write:all", "manage:imports")
      if (!any(vapply(allowed, function(p) auth_user_has_permission(state, p), logical(1)))) {
        showNotification("Permission required: import data", type = "error")
        return(FALSE)
      }
      TRUE
    }

    observe({
      tables <- DBI::dbListTables(con)
      tables <- tables[!grepl("^duckdb_|^sqlite_", tables)]
      updateSelectInput(session, "target_table", choices = c("(none)" = "", tables))
    })

    is_windows_access <- function() {
      .Platform$OS.type == "windows"
    }

    get_access_driver <- function() {
      if (!requireNamespace("odbc", quietly = TRUE)) return(NULL)
      drivers <- tryCatch(odbc::odbcListDrivers(), error = function(e) NULL)
      if (is.null(drivers) || nrow(drivers) == 0) return(NULL)
      name_col <- names(drivers)[1]
      candidates <- drivers[[name_col]]
      access <- candidates[grepl("Access", candidates, ignore.case = TRUE)]
      if (length(access) == 0) return(NULL)
      access[[1]]
    }

    connect_access_db <- function(path) {
      driver <- get_access_driver()
      if (is.null(driver)) {
        stop("Microsoft Access ODBC driver not found.")
      }
      db_path <- normalizePath(path, winslash = "\\", mustWork = TRUE)
      DBI::dbConnect(
        odbc::odbc(),
        .connection_string = paste0("Driver={", driver, "};DBQ=", db_path, ";")
      )
    }

    list_access_projects <- function(table_names) {
      env_tables <- table_names[grepl("_Env$", table_names, ignore.case = TRUE)]
      projects <- gsub("(?i)_Env$", "", env_tables, perl = TRUE)
      sort(unique(projects))
    }

    infer_table_name <- function(file_name) {
      tools::file_path_sans_ext(basename(file_name))
    }

    csv_row_count <- function(path) {
      lines <- tryCatch(length(utils::count.fields(path)), error = function(e) NA_integer_)
      if (is.na(lines)) return(NA_integer_)
      max(lines - 1, 0)
    }

    build_csv_validation <- function(file_path, file_name, preview, target_table, project_override = NULL) {
      total_rows <- csv_row_count(file_path)
      validation <- data.frame(
        file = file_name,
        table = if (!is.null(target_table) && nzchar(target_table)) target_table else "",
        project_id = if (!is.null(project_override) && nzchar(project_override)) project_override else "",
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
        allow_missing <- if (!is.null(project_override) && nzchar(project_override)) c("projectid") else character(0)
        aligned <- align_import_columns(preview, target_fields, allow_missing = allow_missing)
        missing_cols <- aligned$missing
        extra_cols <- aligned$extra
        rv$preview <- aligned$data

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
          tables <- DBI::dbListTables(con)
          tables <- tables[!grepl("^duckdb_|^sqlite_", tables)]
          suggested <- resolve_import_target(infer_table_name(file_name), tables)
          rv$import_project_override <- suggested$project_id

          target_table <- input$target_table
          if (is.null(target_table) || !nzchar(target_table)) {
            target_table <- suggested$table
            if (nzchar(target_table) && target_table %in% tables) {
              updateSelectInput(session, "target_table", selected = target_table)
            }
          }

          rv$preview <- utils::read.csv(file_path, nrows = 100, stringsAsFactors = FALSE)
          result <- build_csv_validation(file_path, file_name, rv$preview, target_table, rv$import_project_override)
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
            resolved <- resolve_import_target(table_guess, tables)
            header <- tryCatch(utils::read.csv(path, nrows = 0, stringsAsFactors = FALSE),
                               error = function(e) NULL)
            cols <- if (is.null(header)) character(0) else names(header)
            row_count <- csv_row_count(path)

            if (resolved$table %in% tables) {
              target_fields <- DBI::dbListFields(con, resolved$table)
              allow_missing <- if (!is.null(resolved$project_id) && nzchar(resolved$project_id)) c("projectid") else character(0)
              aligned <- align_import_columns(as.data.frame(setNames(vector("list", length(cols)), cols)), target_fields, allow_missing = allow_missing)
              missing_cols <- aligned$missing
              extra_cols <- aligned$extra
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
              table = resolved$table,
              source = table_guess,
              project_id = resolved$project_id,
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
            project_id = rv$zip_meta$project_id,
            stringsAsFactors = FALSE
          )

          choice_labels <- ifelse(
            rv$zip_meta$status == "Columns match target",
            paste0(
              rv$zip_meta$table,
              ifelse(nzchar(rv$zip_meta$project_id), paste0(" [", rv$zip_meta$project_id, "]"), ""),
              " <- ", rv$zip_meta$file
            ),
            paste0(
              rv$zip_meta$table,
              ifelse(nzchar(rv$zip_meta$project_id), paste0(" [", rv$zip_meta$project_id, "]"), ""),
              " <- ", rv$zip_meta$file, " (", rv$zip_meta$status, ")"
            )
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

      tables <- DBI::dbListTables(con)
      tables <- tables[!grepl("^duckdb_|^sqlite_", tables)]
      suggested <- resolve_import_target(infer_table_name(file_name), tables)
      rv$import_project_override <- if (identical(input$target_table, suggested$table)) suggested$project_id else NULL

      result <- build_csv_validation(input$import_file$datapath, file_name, rv$preview, input$target_table, rv$import_project_override)
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

    combine_compliance <- function(results) {
      details <- do.call(rbind, lapply(results, function(x) x$detail_tibble))
      if (is.null(details)) details <- data.frame()
      summary <- if (nrow(details) == 0) {
        data.frame(rule = character(), count = integer())
      } else {
        aggregate(list(count = details$rule), by = list(rule = details$rule), FUN = length)
      }
      list(
        passed = all(vapply(results, function(x) isTRUE(x$passed), logical(1))),
        summary_tibble = summary,
        detail_tibble = details
      )
    }

    run_compliance_for_projects <- function(project_ids) {
      project_ids <- unique(project_ids[!is.na(project_ids) & nzchar(project_ids)])
      if (length(project_ids) == 0) project_ids <- state$CurrProject

      results <- lapply(project_ids, function(pid) {
        result <- run_compliance_checks(con, pid)
        if (!is.null(result$detail_tibble) && nrow(result$detail_tibble) > 0) {
          result$detail_tibble$project_id <- pid
        }
        result
      })
      names(results) <- project_ids
      combine_compliance(results)
    }

    access_ready <- reactive({
      if (is.null(input$access_file) || is.null(input$access_file$name)) return(FALSE)
      if (!is_windows_access()) return(FALSE)
      if (is.null(get_access_driver())) return(FALSE)
      if (is.null(input$access_project) || !nzchar(input$access_project)) return(FALSE)
      TRUE
    })

    observe({
      if (isTRUE(access_ready())) {
        shinyjs::enable("access_import")
      } else {
        shinyjs::disable("access_import")
      }
    })

    observeEvent(input$access_analyze, {
      rv$access_results <- NULL
      rv$access_projects <- NULL
      rv$access_tables <- NULL

      if (!is_windows_access()) {
        rv$access_status <- "Access import is supported on Windows only."
        updateSelectInput(session, "access_project", choices = c("(windows only)" = ""), selected = "")
        return()
      }

      if (is.null(get_access_driver())) {
        rv$access_status <- "Microsoft Access ODBC driver not found. Install the Access Database Engine."
        updateSelectInput(session, "access_project", choices = c("(driver missing)" = ""), selected = "")
        return()
      }

      req(input$access_file)
      file_path <- input$access_file$datapath

      con_access <- NULL
      on.exit({
        if (!is.null(con_access)) DBI::dbDisconnect(con_access)
      }, add = TRUE)

      tryCatch({
        con_access <- connect_access_db(file_path)
        tables <- DBI::dbListTables(con_access)
        rv$access_tables <- tables
        projects <- list_access_projects(tables)
        rv$access_projects <- projects

        if (length(projects) == 0) {
          rv$access_status <- "No projects found (no *_Env tables)."
          updateSelectInput(session, "access_project", choices = c("(none)" = ""), selected = "")
        } else {
          updateSelectInput(session, "access_project", choices = projects, selected = projects[[1]])
          rv$access_status <- paste("Found", length(projects), "projects in Access database.")
        }
      }, error = function(e) {
        rv$access_status <- paste("Access analyze error:", e$message)
        updateSelectInput(session, "access_project", choices = c("(error)" = ""), selected = "")
      })
    })

    observeEvent(input$access_import, {
      if (!require_import_permission()) return()
      req(input$access_file)
      req(input$access_project)

      if (!is_windows_access() || is.null(get_access_driver())) {
        rv$access_status <- "Access import requires Windows and the Access ODBC driver."
        return()
      }

      con_access <- NULL
      on.exit({
        if (!is.null(con_access)) DBI::dbDisconnect(con_access)
      }, add = TRUE)

      tryCatch({
        con_access <- connect_access_db(input$access_file$datapath)
        tables_access <- DBI::dbListTables(con_access)
        project_name <- input$access_project
        project_override <- trimws(input$access_project_id)
        if (!nzchar(project_override)) project_override <- project_name

        if (project_exists(con, project_override)) {
          rv$access_status <- paste("Import blocked: project already exists:", project_override)
          return()
        }

        import_plan <- list()
        for (suffix in names(access_suffix_map())) {
          access_table <- paste0(project_name, "_", access_suffix_map()[[suffix]])
          match_idx <- which(tolower(tables_access) == tolower(access_table))
          if (length(match_idx) == 0) next
          import_plan[[length(import_plan) + 1]] <- list(
            access_table = tables_access[[match_idx[[1]]]],
            target_table = import_suffix_map()[[suffix]]
          )
        }

        if (length(import_plan) == 0) {
          rv$access_status <- "No matching project tables found to import."
          return()
        }

        use_compliance <- any(vapply(import_plan, function(x) x$target_table %in% compliance_tables, logical(1)))
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

        results_status <- list()
        imported_payloads <- list()
        for (entry in import_plan) {
          data <- tryCatch(DBI::dbReadTable(con_access, entry$access_table), error = function(e) NULL)
          if (is.null(data)) {
            results_status[[length(results_status) + 1]] <- data.frame(
              table = entry$target_table,
              rows = 0,
              status = "Read error",
              project_id = project_override,
              stringsAsFactors = FALSE
            )
            next
          }

          target_fields <- DBI::dbListFields(con, entry$target_table)
          allow_missing <- c("projectid")
          aligned <- align_import_columns(data, target_fields, allow_missing = allow_missing)
          missing_cols <- aligned$missing
          extra_cols <- aligned$extra
          if (length(missing_cols) > 0 || length(extra_cols) > 0) {
            results_status[[length(results_status) + 1]] <- data.frame(
              table = entry$target_table,
              rows = nrow(data),
              status = "Column mismatch",
              project_id = project_override,
              stringsAsFactors = FALSE
            )
            next
          }

          import_data <- apply_project_override(aligned$data, target_fields, project_override)
          tryCatch({
            DBI::dbAppendTable(con, entry$target_table, import_data)
            imported_payloads[[entry$target_table]] <- import_data
            results_status[[length(results_status) + 1]] <- data.frame(
              table = entry$target_table,
              rows = nrow(import_data),
              status = "Imported",
              project_id = project_override,
              stringsAsFactors = FALSE
            )
          }, error = function(e) {
            results_status[[length(results_status) + 1]] <- data.frame(
              table = entry$target_table,
              rows = nrow(import_data),
              status = paste("Import error:", e$message),
              project_id = project_override,
              stringsAsFactors = FALSE
            )
          })
        }

        rv$access_results <- if (length(results_status) > 0) do.call(rbind, results_status) else data.frame()

        if (use_compliance) {
          rv$compliance <- run_compliance_for_projects(project_override)
          if (!isTRUE(rv$compliance$passed)) {
            rv$access_results$status <- "Rolled back (compliance failed)"
            rv$access_status <- "Import blocked: compliance checks failed"
            return()
          }
          DBI::dbCommit(con)
          commit_ok <- TRUE
        }

        for (entry in import_plan) {
          if (entry$target_table %in% compliance_tables && !is.null(imported_payloads[[entry$target_table]])) {
            log_audit_rows(con, project_override, "Import", entry$target_table, imported_payloads[[entry$target_table]])
          }
        }

        rv$access_status <- paste("Imported", sum(rv$access_results$status == "Imported"), "tables from Access project", project_name)
      }, error = function(e) {
        rv$access_status <- paste("Access import error:", e$message)
      })
    })

    observeEvent(input$import_apply, {
      if (!require_import_permission()) return()
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
              project_id = row$project_id[1],
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
              project_id = row$project_id[1],
              stringsAsFactors = FALSE
            )
            next
          }

          allow_missing <- if (!is.null(row$project_id[1]) && nzchar(row$project_id[1])) c("projectid") else character(0)
          aligned <- align_import_columns(data, target_fields, allow_missing = allow_missing)
          data <- apply_project_override(aligned$data, target_fields, row$project_id[1])
          missing_cols <- aligned$missing
          extra_cols <- aligned$extra
          if (length(missing_cols) > 0 || length(extra_cols) > 0) {
            results_status[[length(results_status) + 1]] <- data.frame(
              table = table,
              rows = nrow(data),
              status = "Column mismatch",
              project_id = row$project_id[1],
              stringsAsFactors = FALSE
            )
            next
          }

          pending_imports[[length(pending_imports) + 1]] <- list(
            table = table,
            data = data,
            project_id = row$project_id[1]
          )
        }

          if (length(pending_imports) > 0) {
            project_ids <- unique(na.omit(vapply(pending_imports, function(x) x$project_id, character(1))))
            existing <- project_ids[vapply(project_ids, function(pid) project_exists(con, pid), logical(1))]
            if (length(existing) > 0) {
              rv$status <- paste("Import blocked: project already exists:", paste(existing, collapse = ", "))
              return()
            }
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
              project_id = entry$project_id,
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
              project_id = entry$project_id,
              stringsAsFactors = FALSE
            )
          }, error = function(e) {
            results_status[[length(results_status) + 1]] <- data.frame(
              table = table,
              rows = nrow(data),
              status = paste("Import error:", e$message),
              project_id = entry$project_id,
              stringsAsFactors = FALSE
            )
          })
        }

        rv$import_results <- if (length(results_status) > 0) do.call(rbind, results_status) else data.frame()

        if (use_compliance) {
          project_scope <- vapply(pending_imports, function(x) x$project_id, character(1))
          rv$compliance <- run_compliance_for_projects(project_scope)
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
            log_project <- entry$project_id %||% state$CurrProject
            log_audit_rows(con, log_project, "Import", entry$table, entry$data)
          }
        }

        rv$preview <- rv$import_results
        rv$status <- paste("Imported", sum(rv$import_results$status == "Imported"), "tables")
        return()
      }

      req(input$target_table)

      if (!is.null(rv$import_project_override) && nzchar(rv$import_project_override)) {
        if (project_exists(con, rv$import_project_override)) {
          rv$status <- paste("Import blocked: project already exists:", rv$import_project_override)
          return()
        }
      }

      if (!is.null(rv$import_validation) && nrow(rv$import_validation) > 0) {
        if (rv$import_validation$status[1] != "Columns match target") {
          rv$status <- "Import blocked: validation errors detected"
          return()
        }
      }

      if (is.null(rv$target_fields)) {
        rv$target_fields <- DBI::dbListFields(con, input$target_table)
      }

      allow_missing <- if (!is.null(rv$import_project_override) && nzchar(rv$import_project_override)) c("projectid") else character(0)
      aligned <- align_import_columns(rv$preview, rv$target_fields, allow_missing = allow_missing)
      rv$preview <- aligned$data
      missing_cols <- aligned$missing
      extra_cols <- aligned$extra

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
        import_data <- apply_project_override(rv$preview, rv$target_fields, rv$import_project_override)
        DBI::dbAppendTable(con, input$target_table, import_data)
        if (use_compliance) {
          project_scope <- rv$import_project_override %||% state$CurrProject
          rv$compliance <- run_compliance_for_projects(project_scope)
          if (!isTRUE(rv$compliance$passed)) {
            rv$status <- "Import blocked: compliance checks failed"
            return()
          }

          DBI::dbCommit(con)
          commit_ok <- TRUE
        }

        if (input$target_table %in% compliance_tables) {
          log_project <- rv$import_project_override %||% state$CurrProject
          log_audit_rows(con, log_project, "Import", input$target_table, import_data)
        }

        rv$import_results <- data.frame(
          table = input$target_table,
          rows = nrow(import_data),
          status = "Imported",
          project_id = rv$import_project_override %||% "",
          stringsAsFactors = FALSE
        )
        rv$status <- paste("Imported", nrow(import_data), "rows into", input$target_table)
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
      project_count <- if (!is.null(rv$compliance$detail_tibble) && "project_id" %in% names(rv$compliance$detail_tibble)) {
        length(unique(rv$compliance$detail_tibble$project_id))
      } else {
        0
      }
      label <- if (passed) {
        "Compliance passed"
      } else {
        if (project_count > 1) {
          paste("Compliance issues:", issue_count, "(projects:", project_count, ")")
        } else {
          paste("Compliance issues:", issue_count)
        }
      }
      badge_class <- if (passed) "bg-success" else "bg-warning"

      tags$span(
        label,
        class = paste("badge", badge_class)
      )
    })

    output$import_compliance_by_project <- DT::renderDT({
      req(rv$compliance)
      details <- rv$compliance$detail_tibble
      if (is.null(details) || nrow(details) == 0) return(NULL)
      if (!"project_id" %in% names(details)) return(NULL)

      summary <- aggregate(
        list(count = details$rule),
        by = list(project_id = details$project_id, rule = details$rule),
        FUN = length
      )

      DT::datatable(summary, rownames = FALSE, options = list(pageLength = 6, ordering = FALSE))
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

    output$access_status <- renderText({
      rv$access_status
    })

    output$access_results <- DT::renderDT({
      req(rv$access_results)
      if (nrow(rv$access_results) == 0) return(NULL)
      DT::datatable(rv$access_results, rownames = FALSE, options = list(pageLength = 6, ordering = FALSE))
    })
  })
}
