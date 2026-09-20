# Shared report utilities for VPRO Quarto templates.
#
# Goal: allow Quarto reports to render even when optional styling packages like
# kableExtra are not installed.

has_kableExtra <- requireNamespace("kableExtra", quietly = TRUE)

#' kableExtra::kbl() with a knitr::kable() fallback
#'
#' This wrapper intentionally accepts a superset of common arguments used across
#' the project, but only forwards arguments that are supported by knitr when
#' kableExtra is unavailable.
#'
#' @param x A data.frame/matrix or object accepted by knitr::kable.
#' @param format Table format.
#' @param digits Digits for numeric columns.
#' @param row.names Row names display.
#' @param col.names Column names.
#' @param align Alignment.
#' @param caption Caption.
#' @param label Label.
#' @param format.args Format args passed to knitr.
#' @param escape Escape HTML.
#' @param ... Additional arguments passed to kableExtra::kbl() when available.
#' @return A knitr_kable / character table representation.
#' @export
kbl <- function(
  x,
  format = NULL,
  digits = getOption("digits"),
  row.names = NA,
  col.names = NA,
  align = NULL,
  caption = NULL,
  label = NULL,
  format.args = list(),
  escape = TRUE,
  ...
) {
  if (isTRUE(has_kableExtra)) {
    return(kableExtra::kbl(
      x = x,
      format = format,
      digits = digits,
      row.names = row.names,
      col.names = col.names,
      align = align,
      caption = caption,
      label = label,
      format.args = format.args,
      escape = escape,
      ...
    ))
  }

  # knitr::kable has a narrower signature; ignore extra styling args.
  knitr::kable(
    x = x,
    format = format,
    digits = digits,
    row.names = row.names,
    col.names = col.names,
    align = align,
    caption = caption,
    label = label,
    format.args = format.args,
    escape = escape
  )
}

#' kableExtra::kable_styling() no-op fallback
#'
#' @param x A kable object.
#' @param ... Styling args.
#' @return The styled table (or original `x` if kableExtra is unavailable).
#' @export
kable_styling <- function(x, ...) {
  if (isTRUE(has_kableExtra)) {
    return(kableExtra::kable_styling(x, ...))
  }
  x
}

#' kableExtra::cell_spec() no-op fallback
#'
#' @param x A vector of cell values.
#' @param ... Styling args.
#' @return Styled cell values (or unmodified values as character).
#' @export
cell_spec <- function(x, ...) {
  if (isTRUE(has_kableExtra)) {
    return(kableExtra::cell_spec(x, ...))
  }
  if (is.null(x)) {
    return(x)
  }
  as.character(x)
}

vpro_is_nonempty_string <- function(x) {
  is.character(x) && length(x) == 1 && nzchar(trimws(x))
}

vpro_report_dir <- function() {
  # Prefer the directory of the currently rendering input file.
  input_dir <- tryCatch(knitr::current_input(dir = TRUE), error = function(e) NA_character_)
  if (vpro_is_nonempty_string(input_dir) && dir.exists(input_dir)) {
    return(normalizePath(input_dir, winslash = "/", mustWork = FALSE))
  }

  # QUARTO_PROJECT_DIR typically points at the project root.
  quarto_root <- Sys.getenv("QUARTO_PROJECT_DIR", unset = "")
  if (vpro_is_nonempty_string(quarto_root) && dir.exists(quarto_root)) {
    candidate <- file.path(quarto_root, "reports")
    if (dir.exists(candidate)) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }

  # Fallback: assume working directory is project root.
  wd <- tryCatch(getwd(), error = function(e) "")
  if (vpro_is_nonempty_string(wd)) {
    wd_norm <- tryCatch(normalizePath(wd, winslash = "/", mustWork = FALSE), error = function(e) wd)
    if (identical(basename(wd_norm), "reports") && dir.exists(wd_norm)) {
      return(wd_norm)
    }
    candidate <- file.path(wd_norm, "reports")
    if (dir.exists(candidate)) {
      return(candidate)
    }
    return(wd_norm)
  }

  file.path(".")
}

vpro_project_root <- function(project_root_param = "") {
  candidates <- character()
  if (vpro_is_nonempty_string(project_root_param)) {
    candidates <- c(candidates, project_root_param)
  }

  quarto_root <- Sys.getenv("QUARTO_PROJECT_DIR", unset = "")
  if (vpro_is_nonempty_string(quarto_root)) {
    candidates <- c(candidates, quarto_root)
  }

  report_dir <- vpro_report_dir()
  if (vpro_is_nonempty_string(report_dir)) {
    candidates <- c(candidates, file.path(report_dir, ".."))
  }

  # Try a few obvious local fallbacks.
  candidates <- c(candidates, getwd(), file.path(getwd(), ".."), file.path(getwd(), "../.."))
  candidates <- unique(candidates[vapply(candidates, nzchar, logical(1))])

  for (candidate in candidates) {
    root <- tryCatch(normalizePath(candidate, winslash = "/", mustWork = FALSE), error = function(e) "")
    if (!nzchar(root) || !dir.exists(root)) next
    if (dir.exists(file.path(root, "R")) && file.exists(file.path(root, "config.yml"))) {
      return(root)
    }
  }

  stop("Unable to locate project root for report helpers.")
}

vpro_resolve_path <- function(path, root_dir) {
  if (!vpro_is_nonempty_string(path)) return(NA_character_)
  if (grepl("^/|^[A-Za-z]:[/\\\\]", path)) {
    return(tryCatch(normalizePath(path, winslash = "/", mustWork = FALSE), error = function(e) path))
  }
  tryCatch(normalizePath(file.path(root_dir, path), winslash = "/", mustWork = FALSE), error = function(e) file.path(root_dir, path))
}

vpro_resolve_existing_path <- function(path, base_dirs) {
  if (!vpro_is_nonempty_string(path)) return(NA_character_)
  if (grepl("^/|^[A-Za-z]:[/\\\\]", path)) {
    resolved <- tryCatch(normalizePath(path, winslash = "/", mustWork = FALSE), error = function(e) path)
    if (file.exists(resolved)) return(resolved)
    return(resolved)
  }

  base_dirs <- base_dirs[vapply(base_dirs, vpro_is_nonempty_string, logical(1))]
  base_dirs <- unique(base_dirs)
  for (base_dir in base_dirs) {
    candidate <- tryCatch(
      normalizePath(file.path(base_dir, path), winslash = "/", mustWork = FALSE),
      error = function(e) file.path(base_dir, path)
    )
    if (file.exists(candidate)) {
      return(candidate)
    }
  }

  # If nothing exists, still return the first candidate for diagnostics.
  if (length(base_dirs) > 0) {
    return(tryCatch(
      normalizePath(file.path(base_dirs[[1]], path), winslash = "/", mustWork = FALSE),
      error = function(e) file.path(base_dirs[[1]], path)
    ))
  }

  NA_character_
}

vpro_duckdb_connect <- function(db_path, root_dir, read_only = TRUE, attach_lists = TRUE) {
  if (!requireNamespace("DBI", quietly = TRUE) || !requireNamespace("duckdb", quietly = TRUE)) {
    stop("DBI and duckdb packages are required to render this report.")
  }

  report_dir <- vpro_report_dir()
  resolved_db <- if (vpro_is_nonempty_string(db_path)) {
    # Quarto/knitr executes reports with db_path typically specified relative to the
    # report directory (e.g., "../data/vpro.duckdb"). Prefer that resolution first.
    vpro_resolve_existing_path(db_path, base_dirs = c(report_dir, root_dir))
  } else {
    file.path(root_dir, "data", "vpro.duckdb")
  }

  if (!vpro_is_nonempty_string(resolved_db) || !file.exists(resolved_db)) {
    attempted <- character()
    if (vpro_is_nonempty_string(db_path) && !grepl("^/|^[A-Za-z]:[/\\\\]", db_path)) {
      attempted <- c(
        tryCatch(normalizePath(file.path(report_dir, db_path), winslash = "/", mustWork = FALSE), error = function(e) file.path(report_dir, db_path)),
        tryCatch(normalizePath(file.path(root_dir, db_path), winslash = "/", mustWork = FALSE), error = function(e) file.path(root_dir, db_path))
      )
    } else if (vpro_is_nonempty_string(db_path)) {
      attempted <- c(tryCatch(normalizePath(db_path, winslash = "/", mustWork = FALSE), error = function(e) db_path))
    } else {
      attempted <- c(file.path(root_dir, "data", "vpro.duckdb"))
    }

    stop(
      sprintf(
        "DuckDB database file not found. db_path='%s'\nResolved: %s\nTried:\n- %s",
        if (is.null(db_path)) "" else as.character(db_path),
        if (vpro_is_nonempty_string(resolved_db)) resolved_db else "<NA>",
        paste(unique(attempted[nzchar(attempted)]), collapse = "\n- ")
      )
    )
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = resolved_db, read_only = isTRUE(read_only))

  if (isTRUE(attach_lists)) {
    lists_path <- file.path(root_dir, "data", "vpro_lists.duckdb")
    if (file.exists(lists_path)) {
      DBI::dbExecute(con, sprintf("ATTACH '%s' AS lists (READ_ONLY)", gsub("'", "''", lists_path)))
    }
  }

  con
}

vpro_first_existing_col <- function(df, candidates) {
  if (is.null(df) || nrow(df) == 0) return(NA_character_)
  cols <- names(df)
  for (cand in candidates) {
    idx <- which(tolower(cols) == tolower(cand))
    if (length(idx) > 0) return(cols[[idx[1]]])
  }
  NA_character_
}

vpro_ensure_col <- function(df, target, candidates) {
  if (is.null(df) || nrow(df) == 0) return(df)
  if (target %in% names(df)) return(df)
  src <- vpro_first_existing_col(df, candidates)
  if (!is.na(src)) {
    df[[target]] <- df[[src]]
  }
  df
}

vpro_sql_in_list <- function(con, values) {
  if (length(values) == 0) return(NULL)
  values <- as.character(values)
  values <- values[!is.na(values) & nzchar(trimws(values))]
  if (length(values) == 0) return(NULL)
  paste(DBI::dbQuoteString(con, values), collapse = ", ")
}

