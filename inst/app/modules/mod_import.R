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
      layout_columns(
        checkboxInput(ns("import_allow_replace"), "Replace existing project data", value = FALSE),
        checkboxInput(ns("import_confirm_replace"), "I understand this deletes existing project rows", value = FALSE),
        col_widths = c(6, 6)
      ),
      tags$hr(),
      tags$h5("Import from Access"),
      tags$p("Imports an Access project into a canonical SQLite project database under data/projects using mdbr"),
      layout_columns(
        fileInput(ns("access_file"), "Access .mdb/.accdb", accept = c(".mdb", ".accdb")),
        textInput(ns("access_project_id"), "New Project ID (optional)", value = ""),
        selectInput(ns("access_project"), "Project", choices = NULL),
        actionButton(ns("access_analyze"), "Analyze", class = "btn-secondary"),
        shinyjs::disabled(actionButton(ns("access_import"), "Import Project", class = "btn-primary")),
        col_widths = c(4, 3, 2, 2, 1)
      ),
      verbatimTextOutput(ns("access_status")),
      DT::DTOutput(ns("access_preview")),
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
    env = "Env",
    veg = "Veg",
    humus = "Humus",
    mineral = "Mineral",
    other = "Other",
    admin = "Admin",
    metadata = "Metadata",
    audit = "Audit",
    su = "SU",
    hierarchy = "Hierarchy",
    spplist = "VLists.SppList"
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
    su = "SU",
    hierarchy = "Hierarchy"
  )
}

import_table_id <- function(table_name) {
  if (grepl("\\.", table_name)) {
    parts <- strsplit(table_name, "\\.")[[1]]
    if (length(parts) == 2) {
      return(DBI::Id(schema = parts[1], table = parts[2]))
    }
  }
  table_name
}

import_get_table_fields <- function(con, table_name) {
  DBI::dbListFields(con, import_table_id(table_name))
}

import_append_table <- function(con, table_name, data) {
  DBI::dbAppendTable(con, import_table_id(table_name), data)
}

list_import_tables <- function(con) {
  base_tables <- DBI::dbListTables(con)
  base_tables <- base_tables[!grepl("^duckdb_|^sqlite_", base_tables)]

  schema_tables <- tryCatch(
    {
      DBI::dbGetQuery(
        con,
        "SELECT schema_name, table_name FROM duckdb_tables() WHERE internal = FALSE"
      )
    },
    error = function(e) data.frame()
  )

  qualified <- character(0)
  if (nrow(schema_tables) > 0) {
    schema_tables <- schema_tables[schema_tables$schema_name %in% c("lists", "user"), , drop = FALSE]
    if (nrow(schema_tables) > 0) {
      qualified <- paste(schema_tables$schema_name, schema_tables$table_name, sep = ".")
    }
  }

  unique(c(base_tables, qualified))
}

resolve_import_target <- function(file_base, tables) {
  base <- tools::file_path_sans_ext(basename(file_base))
  schema_match <- tables[grepl(paste0("\\.", base, "$"), tables, ignore.case = TRUE)]
  if (length(schema_match) > 0) {
    lists_match <- schema_match[grepl("^lists\\.", schema_match, ignore.case = TRUE)]
    if (length(lists_match) > 0) {
      return(list(table = lists_match[[1]], project_id = NULL))
    }
    return(list(table = schema_match[[1]], project_id = NULL))
  }

  if (base %in% tables) {
    return(list(table = base, project_id = NULL))
  }

  base_match <- tables[tolower(tables) == tolower(base)]
  if (length(base_match) > 0) {
    return(list(table = base_match[[1]], project_id = NULL))
  }

  suffixes <- names(import_suffix_map())
  pattern <- paste0("_(", paste(suffixes, collapse = "|"), ")$")
  match <- regexpr(pattern, base, ignore.case = TRUE)
  if (match[1] == -1) {
    return(list(table = base, project_id = NULL))
  }

  suffix <- tolower(regmatches(base, match))
  suffix <- sub("^_", "", suffix)
  project_id <- substr(base, 1, match[1] - 1)
  target <- import_suffix_map()[[suffix]]
  if (is.null(target)) {
    target <- base
  }

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
    data_out <- data.frame(matrix(nrow = nrow(data), ncol = 0), stringsAsFactors = FALSE)
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
  if (is.null(project_id) || !nzchar(project_id)) {
    return(data)
  }
  if (is.null(target_fields) || length(target_fields) == 0) {
    return(data)
  }

  idx <- match("projectid", tolower(target_fields))
  if (is.na(idx)) {
    return(data)
  }

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

delete_project_rows <- function(con, table, project_id) {
  fields <- tryCatch(import_get_table_fields(con, table), error = function(e) character(0))
  if (length(fields) == 0) {
    return(list(status = "No fields", deleted = 0L))
  }

  field_lower <- tolower(fields)
  project_col <- if ("projectid" %in% field_lower) {
    fields[[match("projectid", field_lower)]]
  } else if ("project_id" %in% field_lower) {
    fields[[match("project_id", field_lower)]]
  } else {
    NULL
  }

  if (is.null(project_col)) {
    return(list(status = "No ProjectID column", deleted = 0L))
  }

  res <- DBI::dbExecute(
    con,
    paste0("DELETE FROM ", table, " WHERE ", project_col, " = ?"),
    list(project_id)
  )
  list(status = "Deleted", deleted = as.integer(res %||% 0))
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
      access_results = NULL,
      access_preview = NULL
    )

    compliance_tables <- c("Env", "Veg")
    is_compliance_table <- function(table_name) {
      tolower(table_name) %in% tolower(compliance_tables)
    }

    require_import_permission <- function() {
      if (!auth_is_authenticated(state)) {
        show_toast(toast("Sign in required.", type = "danger"))
        return(FALSE)
      }
      allowed <- c("write:all", "manage:imports")
      if (!any(vapply(allowed, function(p) auth_user_has_permission(state, p), logical(1)))) {
        show_toast(toast("Permission required: import data", type = "danger"))
        return(FALSE)
      }
      TRUE
    }

    observe({
      tables <- list_import_tables(con)
      updateSelectInput(session, "target_table", choices = c("(none)" = "", tables))
    })

    is_legacy_access_project <- function(project_name) {
      if (is.null(project_name) || !nzchar(project_name)) {
        return(FALSE)
      }
      grepl("^vpro\\d+$", tolower(project_name))
    }

    connect_access_db <- function(path) {
      if (!requireNamespace("mdbr", quietly = TRUE)) {
        stop("Package 'mdbr' is required for Access import.")
      }
      DBI::dbConnect(mdbr::mdb(), normalizePath(path, mustWork = TRUE))
    }

    list_access_projects <- function(table_names) {
      env_tables <- table_names[grepl("_Env$", table_names, ignore.case = TRUE)]
      projects <- gsub("(?i)_Env$", "", env_tables, perl = TRUE)
      sort(unique(projects))
    }

    access_table_count <- function(con_access, table_name) {
      count_res <- tryCatch(
        DBI::dbGetQuery(con_access, paste0("SELECT COUNT(*) AS n FROM [", table_name, "]")),
        error = function(e) NULL
      )
      if (is.null(count_res) || nrow(count_res) == 0) {
        return(NA_integer_)
      }
      as.integer(count_res$n[[1]])
    }

    build_access_preview <- function(project_name) {
      if (is.null(project_name) || !nzchar(project_name)) {
        return(NULL)
      }
      if (is.null(rv$access_tables) || length(rv$access_tables) == 0) {
        return(NULL)
      }

      con_access <- NULL
      on.exit(
        {
          if (!is.null(con_access)) DBI::dbDisconnect(con_access)
        },
        add = TRUE
      )

      con_access <- tryCatch(connect_access_db(input$access_file$datapath), error = function(e) NULL)
      if (is.null(con_access)) {
        return(NULL)
      }

      rows <- list()
      for (suffix in names(access_suffix_map())) {
        access_table <- paste0(project_name, "_", access_suffix_map()[[suffix]])
        match_idx <- which(tolower(rv$access_tables) == tolower(access_table))
        if (length(match_idx) == 0) {
          rows[[length(rows) + 1]] <- data.frame(
            access_table = access_table,
            target_table = import_suffix_map()[[suffix]],
            rows = NA_integer_,
            status = "Missing",
            stringsAsFactors = FALSE
          )
          next
        }
        actual_table <- rv$access_tables[[match_idx[[1]]]]
        row_count <- access_table_count(con_access, actual_table)
        rows[[length(rows) + 1]] <- data.frame(
          access_table = actual_table,
          target_table = import_suffix_map()[[suffix]],
          rows = row_count,
          status = "Ready",
          stringsAsFactors = FALSE
        )
      }

      do.call(rbind, rows)
    }

    infer_table_name <- function(file_name) {
      tools::file_path_sans_ext(basename(file_name))
    }

    csv_row_count <- function(path) {
      lines <- tryCatch(length(utils::count.fields(path)), error = function(e) NA_integer_)
      if (is.na(lines)) {
        return(NA_integer_)
      }
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
        target_fields <- import_get_table_fields(con, target_table)
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
        tryCatch(
          {
            tables <- list_import_tables(con)
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
          },
          error = function(e) {
            rv$status <- paste("CSV read error:", e$message)
            rv$preview <- NULL
            rv$import_validation <- NULL
          }
        )
        return()
      }

      if (ext == "zip") {
        tryCatch(
          {
            temp_dir <- tempfile("vpro_import_")
            dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
            utils::unzip(file_path, exdir = temp_dir)
            csv_paths <- list.files(temp_dir, pattern = "\\.csv$", full.names = TRUE, recursive = TRUE)

            if (length(csv_paths) == 0) {
              rv$status <- "ZIP contains no CSV files"
              rv$preview <- NULL
              return()
            }

            tables <- list_import_tables(con)

            meta <- lapply(csv_paths, function(path) {
              table_guess <- infer_table_name(path)
              resolved <- resolve_import_target(table_guess, tables)
              project_id <- if (is.null(resolved$project_id)) "" else resolved$project_id
              header <- tryCatch(utils::read.csv(path, nrows = 0, stringsAsFactors = FALSE), error = function(e) NULL)
              cols <- if (is.null(header)) character(0) else names(header)
              row_count <- csv_row_count(path)

              if (resolved$table %in% tables) {
                target_fields <- import_get_table_fields(con, resolved$table)
                allow_missing <- if (!is.null(resolved$project_id) && nzchar(resolved$project_id)) c("projectid") else character(0)
                preview_stub <- setNames(
                  as.data.frame(matrix(nrow = 0, ncol = length(cols))),
                  cols
                )
                aligned <- align_import_columns(preview_stub, target_fields, allow_missing = allow_missing)
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
                project_id = project_id,
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
                " <- ",
                rv$zip_meta$file
              ),
              selected = rv$zip_map$id[selectable]
            )

            rv$preview <- rv$zip_meta
            rv$status <- paste("ZIP contains", nrow(rv$zip_meta), "CSV files")
            rv$import_validation <- rv$zip_meta
          },
          error = function(e) {
            rv$status <- paste("ZIP read error:", e$message)
            rv$preview <- NULL
            rv$import_validation <- NULL
          }
        )
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
      if (ext != "csv") {
        return()
      }

      tables <- list_import_tables(con)
      suggested <- resolve_import_target(infer_table_name(file_name), tables)
      rv$import_project_override <- if (identical(input$target_table, suggested$table)) suggested$project_id else NULL

      result <- build_csv_validation(input$import_file$datapath, file_name, rv$preview, input$target_table, rv$import_project_override)
      rv$status <- result$status
      rv$import_validation <- result$validation
    })

    import_ready <- reactive({
      req(input$import_file)
      if (is.null(rv$import_validation) || nrow(rv$import_validation) == 0) {
        return(FALSE)
      }

      file_name <- input$import_file$name
      ext <- tolower(tools::file_ext(file_name))

      if (ext == "zip") {
        if (is.null(input$zip_tables) || length(input$zip_tables) == 0) {
          return(FALSE)
        }
        selected_tables <- rv$zip_map$table[rv$zip_map$id %in% input$zip_tables]
        selected_rows <- rv$import_validation[rv$import_validation$table %in% selected_tables, , drop = FALSE]
        if (nrow(selected_rows) == 0) {
          return(FALSE)
        }
        return(all(selected_rows$status == "Columns match target"))
      }

      if (ext == "csv") {
        if (is.null(input$target_table) || !nzchar(input$target_table)) {
          return(FALSE)
        }
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
      if (is.null(details)) {
        details <- data.frame()
      }
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
      if (length(project_ids) == 0) {
        project_ids <- state$CurrProject
      }

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
      if (is.null(input$access_file) || is.null(input$access_file$name)) {
        return(FALSE)
      }
      if (is.null(input$access_project) || !nzchar(input$access_project)) {
        return(FALSE)
      }
      if (is_legacy_access_project(input$access_project) && !nzchar(trimws(input$access_project_id))) {
        return(FALSE)
      }
      TRUE
    })

    replace_ready <- reactive({
      isTRUE(input$import_allow_replace) && isTRUE(input$import_confirm_replace)
    })

    observe({
      if (isTRUE(input$import_allow_replace)) {
        shinyjs::enable("import_confirm_replace")
      } else {
        shinyjs::disable("import_confirm_replace")
        updateCheckboxInput(session, "import_confirm_replace", value = FALSE)
      }
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

      if (!requireNamespace("mdbr", quietly = TRUE)) {
        rv$access_status <- "Access import requires the mdbr package."
        updateSelectInput(session, "access_project", choices = c("(mdbr missing)" = ""), selected = "")
        return()
      }

      req(input$access_file)
      file_path <- input$access_file$datapath

      con_access <- NULL
      on.exit(
        {
          if (!is.null(con_access)) DBI::dbDisconnect(con_access)
        },
        add = TRUE
      )

      tryCatch(
        {
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
            rv$access_preview <- build_access_preview(projects[[1]])
          }
        },
        error = function(e) {
          rv$access_status <- paste("Access analyze error:", e$message)
          updateSelectInput(session, "access_project", choices = c("(error)" = ""), selected = "")
        }
      )
    })

    observeEvent(input$access_project, {
      rv$access_preview <- build_access_preview(input$access_project)
      if (is_legacy_access_project(input$access_project)) {
        rv$access_status <- "Legacy export detected. Provide a new Project ID before importing."
      }
    })

    observeEvent(input$access_import, {
      if (!require_import_permission()) {
        return()
      }
      req(input$access_file)
      req(input$access_project)

      tryCatch(
        {
          project_name <- input$access_project
          project_override <- trimws(input$access_project_id)
          if (!nzchar(project_override)) {
            project_override <- project_name
          }

          if (is_legacy_access_project(project_name) && identical(project_override, project_name)) {
            rv$access_status <- "Legacy export requires a new Project ID."
            return()
          }

          if (project_exists(con, project_override) && !isTRUE(replace_ready())) {
            rv$access_status <- paste("Import blocked: project already exists:", project_override)
            return()
          }
          imported <- project_import_access_project(
            con = con,
            access_path = input$access_file$datapath,
            source_project_id = project_name,
            target_project_id = project_override,
            overwrite = isTRUE(replace_ready())
          )

          imported_tables <- imported$tables %||% list()
          rv$access_results <- if (length(imported_tables) > 0) {
            do.call(
              rbind,
              lapply(names(imported_tables), function(table_name) {
                data.frame(
                  table = table_name,
                  rows = as.integer(imported_tables[[table_name]] %||% 0L),
                  status = "Imported",
                  project_id = imported$project_id,
                  stringsAsFactors = FALSE
                )
              })
            )
          } else {
            data.frame()
          }

          # Removed project_exists function
          rv$access_status <- paste(
            "Imported",
            length(imported_tables),
            "tables into canonical project database",
            basename(imported$path)
          )
        },
        error = function(e) {
          rv$access_status <- paste("Access import error:", e$message)
        }
      )
    })

    observeEvent(input$import_apply, {
      if (!require_import_permission()) {
        return()
      }
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
          if (nrow(row) == 0) {
            next
          }

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

          target_fields <- import_get_table_fields(con, table)
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
          if (length(project_ids) > 0) {
            existing <- project_ids[vapply(project_ids, function(pid) project_exists(con, pid), logical(1))]
            if (length(existing) > 0 && !isTRUE(replace_ready())) {
              rv$status <- paste("Import blocked: project already exists:", paste(existing, collapse = ", "))
              return()
            }
            if (length(existing) > 0 && isTRUE(replace_ready())) {
              for (table_name in unique(vapply(pending_imports, function(x) x$table, character(1)))) {
                for (pid in existing) {
                  delete_project_rows(con, table_name, pid)
                }
              }
            }
          }
        }

        use_compliance <- any(vapply(selected_tables, is_compliance_table, logical(1)))
        commit_ok <- TRUE

        if (use_compliance) {
          commit_ok <- FALSE
          DBI::dbBegin(con)
          on.exit(
            {
              if (!commit_ok) {
                try(DBI::dbRollback(con), silent = TRUE)
              }
            },
            add = TRUE
          )
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

          tryCatch(
            {
              import_append_table(con, table, data)
              results_status[[length(results_status) + 1]] <- data.frame(
                table = table,
                rows = nrow(data),
                status = "Imported",
                project_id = entry$project_id,
                stringsAsFactors = FALSE
              )
            },
            error = function(e) {
              results_status[[length(results_status) + 1]] <- data.frame(
                table = table,
                rows = nrow(data),
                status = paste("Import error:", e$message),
                project_id = entry$project_id,
                stringsAsFactors = FALSE
              )
            }
          )
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
          if (is_compliance_table(entry$table)) {
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
        if (project_exists(con, rv$import_project_override) && !isTRUE(replace_ready())) {
          rv$status <- paste("Import blocked: project already exists:", rv$import_project_override)
          return()
        }
        if (project_exists(con, rv$import_project_override) && isTRUE(replace_ready())) {
          delete_project_rows(con, input$target_table, rv$import_project_override)
        }
      }

      if (!is.null(rv$import_validation) && nrow(rv$import_validation) > 0) {
        if (rv$import_validation$status[1] != "Columns match target") {
          rv$status <- "Import blocked: validation errors detected"
          return()
        }
      }

      if (is.null(rv$target_fields)) {
        rv$target_fields <- import_get_table_fields(con, input$target_table)
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

      use_compliance <- is_compliance_table(input$target_table)
      commit_ok <- TRUE
      if (use_compliance) {
        commit_ok <- FALSE
        DBI::dbBegin(con)
        on.exit(
          {
            if (!commit_ok) {
              try(DBI::dbRollback(con), silent = TRUE)
            }
          },
          add = TRUE
        )
      }

      tryCatch(
        {
          import_data <- apply_project_override(rv$preview, rv$target_fields, rv$import_project_override)
          import_append_table(con, input$target_table, import_data)
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

          if (is_compliance_table(input$target_table)) {
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
        },
        error = function(e) {
          rv$status <- paste("Import error:", e$message)
        }
      )
    })

    output$import_status <- renderText({
      rv$status
    })

    output$import_ready <- renderUI({
      req(rv$import_validation)
      if (nrow(rv$import_validation) == 0) {
        return(NULL)
      }

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
      if (is.null(details) || nrow(details) == 0) {
        return(NULL)
      }
      if (!"project_id" %in% names(details)) {
        return(NULL)
      }

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
      if (nrow(rv$import_results) == 0) {
        return(NULL)
      }
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
      if (nrow(rv$access_results) == 0) {
        return(NULL)
      }
      DT::datatable(rv$access_results, rownames = FALSE, options = list(pageLength = 6, ordering = FALSE))
    })

    output$access_preview <- DT::renderDT({
      req(rv$access_preview)
      if (nrow(rv$access_preview) == 0) {
        return(NULL)
      }
      DT::datatable(rv$access_preview, rownames = FALSE, options = list(pageLength = 8, ordering = FALSE))
    })
  })
}
