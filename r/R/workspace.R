# Cross-OS VPro Desktop Workspace Bridge --------------------------------------

vpro_first_nonempty <- function(...) {
  vals <- list(...)
  for (v in vals) {
    if (is.character(v) && length(v) >= 1L && !is.na(v[[1L]]) && nzchar(v[[1L]])) {
      return(v[[1L]])
    }
  }
  ""
}

vpro_lexical_clean_path <- function(p, convert_backslash = (.Platform$OS.type == "windows")) {
  if (!is.character(p) || length(p) != 1L || is.na(p) || !nzchar(p)) {
    return(".")
  }
  s <- if (isTRUE(convert_backslash) || grepl("^([A-Za-z]:\\\\|\\\\\\\\)", p)) {
    gsub("\\\\", "/", p)
  } else {
    p
  }
  prefix <- ""
  rooted <- FALSE
  rest <- s
  if (grepl("^[A-Za-z]:(/|$)", s)) {
    prefix <- paste0(substr(s, 1L, 2L), "/")
    rooted <- TRUE
    rest <- substring(s, 4L)
  } else if (
    (isTRUE(convert_backslash) || grepl("^\\\\\\\\", p)) &&
      grepl("^//[^/]+/[^/]+", s)
  ) {
    m <- regexpr("^//[^/]+/[^/]+", s)
    prefix <- regmatches(s, m)
    rooted <- TRUE
    rest <- substring(s, nchar(prefix) + 1L)
  } else if (startsWith(s, "/")) {
    prefix <- "/"
    rooted <- TRUE
    rest <- sub("^/+", "", s)
  }

  raw_segs <- if (nzchar(rest)) strsplit(rest, "/", fixed = TRUE)[[1L]] else character()
  stk <- character()
  for (seg in raw_segs) {
    if (!nzchar(seg) || identical(seg, ".")) {
      next
    }
    if (identical(seg, "..")) {
      n_stk <- length(stk)
      if (n_stk > 0L && !identical(stk[[n_stk]], "..")) {
        stk <- stk[-n_stk]
      } else if (!rooted) {
        stk <- c(stk, "..")
      }
    } else {
      stk <- c(stk, seg)
    }
  }

  if (rooted) {
    if (identical(prefix, "/")) {
      return(paste0("/", paste(stk, collapse = "/")))
    }
    if (grepl("^[A-Za-z]:/$", prefix)) {
      return(paste0(prefix, paste(stk, collapse = "/")))
    }
    if (length(stk) == 0L) {
      return(prefix)
    }
    return(paste0(prefix, "/", paste(stk, collapse = "/")))
  }
  if (length(stk) == 0L) {
    return(".")
  }
  paste(stk, collapse = "/")
}

vpro_clean_posix_path <- function(p) {
  vpro_lexical_clean_path(p, convert_backslash = TRUE)
}

vpro_abs_path <- function(
  p,
  home = Sys.getenv("HOME", unset = ""),
  expand_tilde = TRUE,
  is_windows = (.Platform$OS.type == "windows")
) {
  if (isTRUE(expand_tilde)) {
    if (identical(p, "~")) {
      if (!nzchar(home)) {
        cli::cli_abort(
          "$HOME is not defined; cannot expand `~` in VPro directory path.",
          class = c("vpro_error_workspace", "vpro_error")
        )
      }
      p <- home
    } else if (startsWith(p, "~/") || (isTRUE(is_windows) && startsWith(p, "~\\"))) {
      if (!nzchar(home)) {
        cli::cli_abort(
          "$HOME is not defined; cannot expand `~` in VPro directory path.",
          class = c("vpro_error_workspace", "vpro_error")
        )
      }
      rest <- substring(p, 3L)
      base_home <- sub("[/\\\\]+$", "", home)
      p <- if (!nzchar(rest)) {
        home
      } else if (!nzchar(base_home)) {
        paste0("/", rest)
      } else {
        paste0(base_home, "/", rest)
      }
    }
  }
  is_abs <- grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", p)
  if (!is_abs) {
    wd <- sub("[/\\\\]+$", "", gsub("\\\\", "/", getwd()))
    p <- if (!nzchar(wd)) paste0("/", p) else paste0(wd, "/", p)
  }
  vpro_lexical_clean_path(p, convert_backslash = is_windows)
}

vpro_resolve_data_dir <- function(
  os = Sys.info()[["sysname"]],
  opt = getOption("vpro.data_dir"),
  env_data = Sys.getenv("VPRO_DATA_DIR", unset = ""),
  localappdata = Sys.getenv("LOCALAPPDATA", unset = ""),
  userprofile = Sys.getenv("USERPROFILE", unset = ""),
  xdg_data = Sys.getenv("XDG_DATA_HOME", unset = ""),
  home = Sys.getenv("HOME", unset = "")
) {
  os_low <- tolower(as.character(os))
  is_win <- grepl("windows|mingw", os_low)
  eff_home <- if (is_win) vpro_first_nonempty(userprofile, home) else home
  override <- vpro_first_nonempty(opt, env_data)
  if (nzchar(override)) {
    return(vpro_abs_path(override, home = eff_home, expand_tilde = TRUE, is_windows = is_win))
  }
  if (is_win) {
    if (nzchar(localappdata)) {
      p <- paste0(sub("[/\\\\]+$", "", localappdata), "/vpro")
    } else {
      if (!nzchar(eff_home)) {
        cli::cli_abort(
          "%USERPROFILE% is not defined; cannot resolve Windows VPro data directory.",
          class = c("vpro_error_workspace", "vpro_error")
        )
      }
      p <- paste0(sub("[/\\\\]+$", "", eff_home), "/AppData/Local/vpro")
    }
  } else if (identical(os_low, "darwin")) {
    if (!nzchar(home)) {
      cli::cli_abort(
        "$HOME is not defined; cannot resolve macOS VPro data directory.",
        class = c("vpro_error_workspace", "vpro_error")
      )
    }
    base_home <- sub("/+$", "", home)
    p <- if (nzchar(base_home)) {
      paste0(base_home, "/Library/Application Support/vpro")
    } else {
      "/Library/Application Support/vpro"
    }
  } else {
    if (nzchar(xdg_data) && startsWith(xdg_data, "/")) {
      base_xdg <- sub("/+$", "", xdg_data)
      p <- if (nzchar(base_xdg)) paste0(base_xdg, "/vpro") else "/vpro"
    } else {
      if (!nzchar(home)) {
        cli::cli_abort(
          "$HOME is not defined; cannot resolve VPro data directory.",
          class = c("vpro_error_workspace", "vpro_error")
        )
      }
      base_home <- sub("/+$", "", home)
      p <- if (nzchar(base_home)) paste0(base_home, "/.local/share/vpro") else "/.local/share/vpro"
    }
  }
  vpro_abs_path(p, home = eff_home, expand_tilde = FALSE, is_windows = is_win)
}

vpro_resolve_config_dir <- function(
  os = Sys.info()[["sysname"]],
  opt = getOption("vpro.config_dir"),
  env_cfg = Sys.getenv("VPRO_CONFIG_DIR", unset = ""),
  appdata = Sys.getenv("APPDATA", unset = ""),
  userprofile = Sys.getenv("USERPROFILE", unset = ""),
  xdg_cfg = Sys.getenv("XDG_CONFIG_HOME", unset = ""),
  home = Sys.getenv("HOME", unset = "")
) {
  os_low <- tolower(as.character(os))
  is_win <- grepl("windows|mingw", os_low)
  eff_home <- if (is_win) vpro_first_nonempty(userprofile, home) else home
  override <- vpro_first_nonempty(opt, env_cfg)
  if (nzchar(override)) {
    return(vpro_abs_path(override, home = eff_home, expand_tilde = TRUE, is_windows = is_win))
  }
  if (is_win) {
    if (!nzchar(appdata)) {
      cli::cli_abort(
        "%APPDATA% is not defined; cannot resolve Windows VPro configuration directory.",
        class = c("vpro_error_workspace", "vpro_error")
      )
    }
    p <- paste0(sub("[/\\\\]+$", "", appdata), "/vpro")
  } else if (identical(os_low, "darwin")) {
    if (!nzchar(home)) {
      cli::cli_abort(
        "$HOME is not defined; cannot resolve macOS VPro configuration directory.",
        class = c("vpro_error_workspace", "vpro_error")
      )
    }
    base_home <- sub("/+$", "", home)
    p <- if (nzchar(base_home)) {
      paste0(base_home, "/Library/Application Support/vpro")
    } else {
      "/Library/Application Support/vpro"
    }
  } else {
    if (nzchar(xdg_cfg) && startsWith(xdg_cfg, "/")) {
      base_xdg <- sub("/+$", "", xdg_cfg)
      p <- if (nzchar(base_xdg)) paste0(base_xdg, "/vpro") else "/vpro"
    } else {
      if (!nzchar(home)) {
        cli::cli_abort(
          "$HOME is not defined; cannot resolve VPro configuration directory.",
          class = c("vpro_error_workspace", "vpro_error")
        )
      }
      base_home <- sub("/+$", "", home)
      p <- if (nzchar(base_home)) paste0(base_home, "/.config/vpro") else "/.config/vpro"
    }
  }
  vpro_abs_path(p, home = eff_home, expand_tilde = FALSE, is_windows = is_win)
}

#' Locate the `VPro` desktop user data directory
#'
#' Matches VPro Desktop's user data directory byte-for-byte across Windows
#' (`%LOCALAPPDATA%/vpro`), macOS (`~/Library/Application Support/vpro`), and
#' Linux (`$XDG_DATA_HOME/vpro` or `~/.local/share/vpro`), honoring
#' `getOption("vpro.data_dir")` and `VPRO_DATA_DIR` overrides first.
#'
#' @return Normalized path string (`/` separators).
#' @export
vpro_data_dir <- function() {
  vpro_resolve_data_dir()
}

#' Locate the `VPro` desktop user configuration directory
#'
#' Matches VPro Desktop's user configuration directory byte-for-byte across
#' Windows (`%APPDATA%/vpro`), macOS (`~/Library/Application Support/vpro`), and
#' Linux (`$XDG_CONFIG_HOME/vpro` or `~/.config/vpro`), honoring
#' `getOption("vpro.config_dir")` and `VPRO_CONFIG_DIR` overrides first.
#'
#' @return Normalized path string (`/` separators).
#' @export
vpro_config_dir <- function() {
  vpro_resolve_config_dir()
}

vpro_project_name <- function(project) {
  if (!is.character(project) || length(project) != 1L || is.na(project) || !grepl("^[A-Za-z][A-Za-z0-9_]{0,30}$", project)) {
    cli::cli_abort(
      "VPro project names must start with a letter, contain only letters, digits, or underscores, and be at most 31 characters.",
      class = c("vpro_error_workspace", "vpro_error")
    )
  }
  project
}

vpro_sqlite_physical_tables <- function(path) {
  con <- vpro_sqlite_ro(path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(
    con,
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
  )$name
}

# Discover VPro project families in a SQLite database
.vpro_project_discover <- function(path) {
  tables <- vpro_sqlite_physical_tables(path)
  env_tables <- grep("^[A-Za-z][A-Za-z0-9_]{0,30}_Env$", tables, value = TRUE)
  env_tables <- setdiff(env_tables, c("Filtered_Env", "USysEnv", "UsysEnv"))
  projects <- sub("_Env$", "", env_tables)
  if (length(projects) == 0L) {
    return(tibble::tibble(
      project = character(),
      core_tables = integer(),
      optional_tables = integer(),
      complete = logical(),
      version = character()
    ))
  }

  con <- vpro_sqlite_ro(path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  meta_map <- character()
  if ("_table_metadata" %in% tables) {
    md <- DBI::dbGetQuery(con, 'SELECT "table_name", "description" FROM "_table_metadata"')
    if (nrow(md) > 0L) {
      meta_map <- stats::setNames(as.character(md$description), as.character(md$table_name))
    }
  }

  rows <- lapply(projects, function(prj) {
    core <- paste0(prj, "_", .vpro_core_project_suffixes)
    opt <- paste0(prj, "_", .vpro_optional_project_suffixes)
    ver <- unname(meta_map[paste0(prj, "_Env")])
    if (length(ver) == 0L || is.na(ver) || !nzchar(ver)) {
      ver <- "Unknown"
    }
    tibble::tibble(
      project = prj,
      core_tables = as.integer(sum(core %in% tables)),
      optional_tables = as.integer(sum(opt %in% tables)),
      complete = all(core %in% tables),
      version = ver
    )
  })
  do.call(rbind, rows)
}

.vpro_project_validate <- function(path, project) {
  project <- vpro_project_name(project)
  tables <- vpro_sqlite_physical_tables(path)
  expected <- paste0(project, "_", .vpro_core_project_suffixes)
  tibble::tibble(
    suffix = .vpro_core_project_suffixes,
    table = expected,
    present = expected %in% tables
  )
}

#' Inspect a VPro project SQLite database for `VP08` compatibility and schema completeness
#'
#' Validates the required 8-table `VP08` family (`_Admin`, `_Audit`, `_Env`,
#' `_Humus`, `_Metadata`, `_Mineral`, `_Other`, `_Veg`) and `_table_metadata`
#' version tag, returning standard compatibility fields (`path`, `project`,
#' `version`, `compatible`, `validation`).
#'
#' @param path Path to a VPro project SQLite database.
#' @param project Optional project prefix inside `path`. When `NULL`, auto-detects
#'   the primary project in `path`.
#' @return A list with `path`, `project`, `version`, `compatible`, and `validation`.
#' @export
vpro_project_inspect <- function(path, project = NULL) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (!file.exists(path)) {
    cli::cli_abort(
      .vpro_cli_escape(paste0("VPro project database does not exist: ", path)),
      class = c("vpro_error_workspace", "vpro_error")
    )
  }
  if (is.null(project)) {
    disc <- .vpro_project_discover(path)
    if (nrow(disc) == 0L) {
      cli::cli_abort(
        .vpro_cli_escape(paste0("Database contains no `<Project>_Env` table: ", path)),
        class = c("vpro_error_workspace", "vpro_error")
      )
    }
    stem <- tools::file_path_sans_ext(basename(path))
    project <- if (stem %in% disc$project) stem else disc$project[[1L]]
  }
  project <- vpro_project_name(project)
  validation <- .vpro_project_validate(path, project)
  dbc <- vpro_sqlite_ro(path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  version <- "Unknown"
  if (DBI::dbExistsTable(dbc, "_table_metadata")) {
    res <- DBI::dbGetQuery(
      dbc,
      'SELECT "description" FROM "_table_metadata" WHERE "table_name" = ?',
      params = list(paste0(project, "_Env"))
    )
    if (nrow(res) == 1L && !is.na(res$description[[1L]]) && nzchar(res$description[[1L]])) {
      version <- as.character(res$description[[1L]])
    }
  }
  list(
    path = path,
    project = project,
    version = version,
    compatible = identical(version, "VP08") && all(validation$present),
    validation = validation
  )
}

vpro_resolve_table_suffix <- function(tables, requested, suffix, default_prefix = NULL) {
  pattern <- paste0("_", suffix, "$")
  candidates <- grep(pattern, tables, value = TRUE, ignore.case = TRUE)
  candidates <- candidates[!grepl("^USys", candidates, ignore.case = TRUE)]
  if (is.null(requested) || is.na(requested) || !nzchar(trimws(requested)) || identical(tolower(trimws(requested)), "none")) {
    if (identical(tolower(trimws(as.character(requested))), "none")) {
      return(NULL)
    }
    if (!is.null(default_prefix)) {
      def_tbl <- paste0(default_prefix, "_", suffix)
      hit <- candidates[tolower(candidates) == tolower(def_tbl)]
      if (length(hit) >= 1L) return(hit[[1L]])
    }
    if (length(candidates) >= 1L) {
      return(candidates[[1L]])
    }
    return(NULL)
  }
  req <- trimws(requested)
  req_full <- if (grepl(pattern, req, ignore.case = TRUE)) req else paste0(req, "_", suffix)
  hit <- candidates[tolower(candidates) == tolower(req_full)]
  if (length(hit) == 0L) {
    cli::cli_abort(
      .vpro_cli_escape(paste0(
        "Table `",
        req_full,
        "` was not found. Available `*",
        "_",
        suffix,
        "` tables: ",
        if (length(candidates)) paste(candidates, collapse = ", ") else "<none>"
      )),
      class = c("vpro_error_workspace", "vpro_error")
    )
  }
  hit[[1L]]
}

.vpro_support_db_required_tables <- function(name) {
  switch(
    tolower(basename(as.character(name))),
    "vlists.db" = "USysAllSpecs",
    "vuser.db" = "USysUserSpp",
    "vpro64.db" = "USysEnvTable",
    "vmetadata.db" = "ProjectMetadata",
    "vmessageboard.db" = "tblMessageBoard",
    "vpics.db" = "tblVPics",
    character()
  )
}

.vpro_is_valid_support_db <- function(path, name = basename(path)) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    return(FALSE)
  }
  if (!file.exists(path) || dir.exists(path)) {
    return(FALSE)
  }
  sz <- file.info(path)$size
  if (is.na(sz) || sz <= 0) {
    return(FALSE)
  }
  req_tbls <- .vpro_support_db_required_tables(name)
  tryCatch(
    {
      con <- vpro_sqlite_ro(path)
      on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE)
      tbls <- DBI::dbGetQuery(
        con,
        "SELECT name FROM sqlite_master WHERE type = 'table'"
      )$name
      if (length(req_tbls) == 0L) {
        TRUE
      } else {
        all(tolower(req_tbls) %in% tolower(as.character(tbls)))
      }
    },
    error = function(e) FALSE
  )
}

vpro_same_dir <- function(a, b) {
  if (is.null(a) || is.null(b) || !nzchar(a) || !nzchar(b)) {
    return(FALSE)
  }
  na <- normalizePath(a, winslash = "/", mustWork = FALSE)
  nb <- normalizePath(b, winslash = "/", mustWork = FALSE)
  if (.Platform$OS.type == "windows" || identical(tolower(Sys.info()[["sysname"]]), "darwin")) {
    identical(tolower(na), tolower(nb))
  } else {
    identical(na, nb)
  }
}

vpro_find_support_db <- function(name, data_dir, project_dir = NULL) {
  candidates <- character()
  has_data_dir <- !is.null(data_dir) && nzchar(data_dir)
  has_proj_dir <- !is.null(project_dir) && nzchar(project_dir)
  if (has_proj_dir && (!has_data_dir || !vpro_same_dir(project_dir, data_dir))) {
    candidates <- c(
      candidates,
      file.path(project_dir, "database-family", name),
      file.path(project_dir, name)
    )
  }
  if (has_data_dir) {
    candidates <- c(
      candidates,
      file.path(data_dir, "database-family", name),
      file.path(data_dir, name)
    )
  }
  for (cand in unique(candidates)) {
    if (.vpro_is_valid_support_db(cand, name)) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  vpro_bundled_db(name)
}

.vpro_support_db_filenames <- tolower(c(
  "vpro64.db",
  "vlists.db",
  "vlists-lookup.db",
  "vuser.db",
  "vmetadata.db",
  "vmessageboard.db",
  "vpics.db",
  "bec.db",
  "working-unit.db",
  "site-codes.db",
  "soil-codes.db",
  "parent-codes.db",
  "region-codes.db",
  "geology-codes.db",
  "plot-quality-site.db"
))

.vpro_find_workspace_project_db <- function(data_dir, base) {
  if (is.null(data_dir) || !nzchar(data_dir)) {
    return(character())
  }
  target_lower <- tolower(paste0(base, ".db"))
  if (target_lower %in% .vpro_support_db_filenames) {
    return(character())
  }
  direct <- c(
    file.path(data_dir, "projects", paste0(base, ".db")),
    file.path(data_dir, paste0(base, ".db"))
  )
  hits <- direct[file.exists(direct) & !dir.exists(direct)]
  if (length(hits) > 0L) {
    return(hits[[1L]])
  }
  for (d in c(file.path(data_dir, "projects"), data_dir)) {
    if (!dir.exists(d)) {
      next
    }
    entries <- list.files(d, full.names = FALSE)
    m <- entries[tolower(entries) == target_lower]
    if (length(m) > 0L) {
      cand <- file.path(d, m[[1L]])
      if (file.exists(cand) && !dir.exists(cand)) {
        return(cand)
      }
    }
  }
  character()
}

.vpro_nonempty_cfg_str <- function(val) {
  if (is.null(val)) {
    return(NULL)
  }
  s <- trimws(as.character(val))
  if (nzchar(s)) s else NULL
}

.vpro_existing_cfg_file <- function(val) {
  s <- .vpro_nonempty_cfg_str(val)
  if (!is.null(s) && file.exists(s) && !dir.exists(s)) {
    normalizePath(s, winslash = "/", mustWork = TRUE)
  } else {
    NULL
  }
}

.vpro_apply_cfg_selections <- function(cfg_cur, su, hierarchy, lump) {
  list(
    su = if (is.null(su)) .vpro_nonempty_cfg_str(cfg_cur$CurrPlotlist) else su,
    su_db_override = .vpro_existing_cfg_file(cfg_cur$SUPath),
    hierarchy = if (is.null(hierarchy)) .vpro_nonempty_cfg_str(cfg_cur$CurrHierarchy) else hierarchy,
    hier_db_override = .vpro_existing_cfg_file(cfg_cur$HierarchyPath),
    lump = if (is.null(lump)) .vpro_nonempty_cfg_str(cfg_cur$CurrLump) else lump
  )
}

.vpro_connect_auto_discover <- function(data_dir, config_dir, cfg_cur, su, hierarchy, lump) {
  cfg_prj <- .vpro_nonempty_cfg_str(cfg_cur$CurrProject)
  cfg_prj_path <- .vpro_nonempty_cfg_str(cfg_cur$ProjectPath)
  candidates <- character()
  if (!is.null(cfg_prj_path)) {
    candidates <- c(candidates, cfg_prj_path)
    if (!is.null(cfg_prj)) {
      candidates <- c(candidates, file.path(cfg_prj_path, paste0(cfg_prj, ".db")))
    }
  }
  if (!is.null(cfg_prj)) {
    candidates <- c(
      candidates,
      file.path(data_dir, "projects", paste0(cfg_prj, ".db")),
      file.path(data_dir, paste0(cfg_prj, ".db"))
    )
  }
  existing <- candidates[file.exists(candidates) & !dir.exists(candidates)]
  if (length(existing) > 0L) {
    project_path <- normalizePath(existing[[1L]], winslash = "/", mustWork = TRUE)
    project_name <- cfg_prj
  } else {
    listed <- vpro_list_projects(path = data_dir)
    if (nrow(listed) == 0L) {
      cli::cli_abort(
        .vpro_cli_escape(c(
          "No VPro project database was found in the workspace.",
          "i" = paste0("Checked data_dir: ", data_dir),
          "i" = "Pass an explicit `.db` path or call `vpro_connect(\"Sample\")` for the bundled Sample workspace."
        )),
        class = c("vpro_error_workspace", "vpro_error")
      )
    }
    project_path <- listed$path[[1L]]
    project_name <- listed$project[[1L]]
  }
  sel <- .vpro_apply_cfg_selections(cfg_cur, su, hierarchy, lump)
  list(
    early_return = NULL,
    project_path = project_path,
    project_name = project_name,
    data_dir = data_dir,
    config_dir = config_dir,
    source_kind = "workspace",
    su = sel$su,
    su_db_override = sel$su_db_override,
    hierarchy = sel$hierarchy,
    hier_db_override = sel$hier_db_override,
    lump = sel$lump
  )
}

.vpro_connect_explicit_target <- function(project, data_dir, config_dir, cfg_cur, su, hierarchy, lump) {
  if (!is.character(project) || length(project) != 1L || is.na(project) || !nzchar(trimws(project))) {
    cli::cli_abort(
      "`project` must be NULL or a single non-empty character string.",
      class = c("vpro_error_workspace", "vpro_error")
    )
  }
  req <- trimws(project)
  if (dir.exists(req)) {
    listed <- vpro_list_projects(path = req)
    if (nrow(listed) == 0L) {
      cli::cli_abort(
        .vpro_cli_escape(paste0("No VPro `.db` projects were found in directory: ", req)),
        class = c("vpro_error_workspace", "vpro_error")
      )
    }
    return(list(
      early_return = NULL,
      project_path = listed$path[[1L]],
      project_name = listed$project[[1L]],
      data_dir = normalizePath(req, winslash = "/", mustWork = TRUE),
      config_dir = config_dir,
      source_kind = "directory",
      su = su,
      su_db_override = NULL,
      hierarchy = hierarchy,
      hier_db_override = NULL,
      lump = lump
    ))
  }
  if (file.exists(req)) {
    ext <- tolower(tools::file_ext(req))
    if (ext %in% c("accdb", "mdb")) {
      tmp_db <- tempfile(pattern = "vpro-access-ws-", fileext = ".db")
      imp <- vpro_import_access(req, dest_db = tmp_db)
      return(list(
        early_return = NULL,
        project_path = imp$target_db,
        project_name = imp$target_project,
        data_dir = data_dir,
        config_dir = config_dir,
        source_kind = "access_import",
        su = su,
        su_db_override = NULL,
        hierarchy = hierarchy,
        hier_db_override = NULL,
        lump = lump
      ))
    }
    if (identical(ext, "rds")) {
      return(list(early_return = vpro_import_rds(req, su = su, lump = lump)))
    }
    project_path <- normalizePath(req, winslash = "/", mustWork = TRUE)
    bundled_sample <- normalizePath(vpro_bundled_db("Sample.db"), winslash = "/", mustWork = FALSE)
    return(list(
      early_return = NULL,
      project_path = project_path,
      project_name = NULL,
      data_dir = data_dir,
      config_dir = config_dir,
      source_kind = if (identical(project_path, bundled_sample)) "sample" else "file",
      su = su,
      su_db_override = NULL,
      hierarchy = hierarchy,
      hier_db_override = NULL,
      lump = lump
    ))
  }
  base <- sub("\\.(db|sqlite|sqlite3)$", "", req, ignore.case = TRUE)
  ws_hit <- .vpro_find_workspace_project_db(data_dir, base)
  if (length(ws_hit) > 0L) {
    project_path <- normalizePath(ws_hit, winslash = "/", mustWork = TRUE)
    project_name <- tools::file_path_sans_ext(basename(ws_hit))
    cfg_prj <- .vpro_nonempty_cfg_str(cfg_cur$CurrProject)
    sel <- if (!is.null(cfg_prj) && identical(tolower(cfg_prj), tolower(project_name))) {
      .vpro_apply_cfg_selections(cfg_cur, su, hierarchy, lump)
    } else {
      list(su = su, su_db_override = NULL, hierarchy = hierarchy, hier_db_override = NULL, lump = lump)
    }
    if (is.null(sel$su)) {
      sel$su <- "None"
    }
    return(list(
      early_return = NULL,
      project_path = project_path,
      project_name = project_name,
      data_dir = data_dir,
      config_dir = config_dir,
      source_kind = "workspace",
      su = sel$su,
      su_db_override = sel$su_db_override,
      hierarchy = sel$hierarchy,
      hier_db_override = sel$hier_db_override,
      lump = sel$lump
    ))
  }
  if (identical(tolower(base), "sample")) {
    project_path <- normalizePath(vpro_bundled_db("Sample.db"), winslash = "/", mustWork = TRUE)
    return(list(
      early_return = NULL,
      project_path = project_path,
      project_name = "Sample",
      data_dir = dirname(project_path),
      config_dir = tempdir(),
      source_kind = "sample",
      su = if (is.null(su)) "Sample_SU" else su,
      su_db_override = NULL,
      hierarchy = if (is.null(hierarchy)) "Sample_Hierarchy" else hierarchy,
      hier_db_override = NULL,
      lump = if (is.null(lump)) "Sample_Lump" else lump
    ))
  }
  cli::cli_abort(
    .vpro_cli_escape(paste0("Could not find VPro project `", req, "` as a file or inside `", data_dir, "`.")),
    class = c("vpro_error_workspace", "vpro_error")
  )
}

#' Connect to a live `VPro` workspace, bundled `Sample`, SQLite `.db`, or Access archive
#'
#' Creates a lightweight, read-only-by-default S3 `vpro_workspace` handle.
#' Called with zero arguments (`vpro_connect()`), auto-discovers the user's
#' active `VPro` `config.yml` and VPro Desktop project workspace. Passing `"Sample"`
#' opens the workspace `Sample.db` when present in `data_dir`, or falls back to
#' the bundled read-only 2026 `VP08` `Sample` teaching workspace. Also accepts
#' an explicit project name in `data_dir`, a `.db` / `.sqlite` / `.rds` file
#' path, a directory containing `.db` projects, or an `.accdb` / `.mdb` archive
#' (which is non-destructively converted into a session-temporary `VP08` SQLite
#' file).
#'
#' @param project Optional project name, `"Sample"`, `.db` / `.rds` path,
#'   directory path, or `.accdb`/`.mdb` path. When `NULL`, reads
#'   `Current$CurrProject` from `config.yml` or discovers projects in `data_dir`.
#' @param su Optional site-unit table name (with or without `_SU` suffix), or
#'   `"None"` to disable SU scoping.
#' @param hierarchy Optional hierarchy table name (with or without `_Hierarchy`
#'   suffix).
#' @param lump Optional species lump table name (with or without `_Lump` suffix),
#'   or `"None"`.
#' @param data_dir Workspace data directory (defaults to [vpro_data_dir()]).
#' @param config_dir Workspace configuration directory (defaults to
#'   [vpro_config_dir()]).
#' @return An S3 object of class `vpro_workspace`.
#' @export
vpro_connect <- function(
  project = NULL,
  su = NULL,
  hierarchy = NULL,
  lump = NULL,
  data_dir = vpro_data_dir(),
  config_dir = vpro_config_dir()
) {
  can_fallback_dirs <- !is.null(project) &&
    is.character(project) &&
    length(project) == 1L &&
    !is.na(project) &&
    (file.exists(trimws(project)) || identical(tolower(trimws(project)), "sample"))
  data_dir <- tryCatch(
    vpro_abs_path(data_dir),
    error = function(e) if (missing(data_dir) && can_fallback_dirs) tempdir() else rlang::cnd_signal(e)
  )
  config_dir <- tryCatch(
    vpro_abs_path(config_dir),
    error = function(e) if (missing(config_dir) && can_fallback_dirs) tempdir() else rlang::cnd_signal(e)
  )
  cfg_path <- file.path(config_dir, "config.yml")
  cfg_cur <- list()
  if (file.exists(cfg_path)) {
    parsed <- tryCatch(yaml::read_yaml(cfg_path, readLines.warn = FALSE), error = function(e) NULL)
    if (is.list(parsed) && is.list(parsed$Current)) {
      cfg_cur <- parsed$Current
    }
  }

  target <- if (is.null(project)) {
    .vpro_connect_auto_discover(data_dir, config_dir, cfg_cur, su, hierarchy, lump)
  } else {
    .vpro_connect_explicit_target(project, data_dir, config_dir, cfg_cur, su, hierarchy, lump)
  }
  if (!is.null(target$early_return)) {
    return(target$early_return)
  }

  project_path <- target$project_path
  project_name <- target$project_name
  data_dir <- target$data_dir
  config_dir <- target$config_dir
  source_kind <- target$source_kind

  fams <- .vpro_project_discover(project_path)
  if (nrow(fams) == 0L) {
    cli::cli_abort(
      .vpro_cli_escape(paste0("Database contains no `<Project>_Env` table: ", project_path)),
      class = c("vpro_error_workspace", "vpro_error")
    )
  }
  if (is.null(project_name) || !(project_name %in% fams$project)) {
    stem <- tools::file_path_sans_ext(basename(project_path))
    project_name <- if (stem %in% fams$project) stem else fams$project[[1L]]
  }

  tables <- vpro_sqlite_physical_tables(project_path)
  su_path <- if (!is.null(target$su_db_override)) target$su_db_override else project_path
  su_tables <- if (identical(su_path, project_path)) tables else vpro_sqlite_physical_tables(su_path)
  resolved_su <- tryCatch(
    vpro_resolve_table_suffix(su_tables, target$su, "SU", default_prefix = project_name),
    error = function(e) {
      if (identical(source_kind, "workspace") && is.null(target$su)) NULL else rlang::cnd_signal(e)
    }
  )

  hier_path <- if (!is.null(target$hier_db_override)) target$hier_db_override else project_path
  hier_tables <- if (identical(hier_path, project_path)) tables else vpro_sqlite_physical_tables(hier_path)
  resolved_hier <- tryCatch(
    vpro_resolve_table_suffix(hier_tables, target$hierarchy, "Hierarchy", default_prefix = project_name),
    error = function(e) {
      if (identical(source_kind, "workspace") && is.null(target$hierarchy)) NULL else rlang::cnd_signal(e)
    }
  )

  resolved_lump <- vpro_resolve_table_suffix(tables, target$lump, "Lump", default_prefix = project_name)

  proj_dir <- dirname(project_path)
  structure(
    list(
      project = project_name,
      project_path = project_path,
      su = resolved_su,
      su_path = su_path,
      hierarchy = resolved_hier,
      hierarchy_path = hier_path,
      lump = resolved_lump,
      lump_path = project_path,
      vlists_path = vpro_find_support_db("VLists.db", data_dir, proj_dir),
      vuser_path = vpro_find_support_db("VUser.db", data_dir, proj_dir),
      vpro64_path = vpro_find_support_db("VPro64.db", data_dir, proj_dir),
      vmetadata_path = vpro_find_support_db("VMetaData.db", data_dir, proj_dir),
      data_dir = data_dir,
      config_dir = config_dir,
      source = source_kind
    ),
    class = "vpro_workspace"
  )
}

vpro_assert_workspace <- function(ws) {
  if (inherits(ws, "vpro_pg_conn")) {
    cli::cli_abort(
      c(
        "`ws` is a PostgreSQL `vpro_pg_conn` handle, not a local `vpro_workspace`.",
        "i" = "Use `vpro_master_env(pg, ...)` / `vpro_master_veg(pg, ...)` for direct cloud tibbles, or wrap a filtered cloud subset with `vpro_master_workspace(pg, ...)` / `vpro_master_pull(pg, ...)`."
      ),
      class = c("vpro_error_workspace", "vpro_error")
    )
  }
  if (!inherits(ws, "vpro_workspace") || !is.list(ws) || is.null(ws$project_path) || !file.exists(ws$project_path)) {
    cli::cli_abort(
      "`ws` must be a valid `vpro_workspace` created by `vpro_connect()`.",
      class = c("vpro_error_workspace", "vpro_error")
    )
  }
  invisible(ws)
}

#' Switch active project, SiteUnit (`*_SU`), hierarchy, or lump table on a workspace
#'
#' Returns an updated `vpro_workspace` handle without mutating disk files.
#'
#' @param ws A `vpro_workspace` handle.
#' @param project Optional project prefix inside `ws$project_path`.
#' @param su Optional `*_SU` table name (or `"None"` to clear).
#' @param hierarchy Optional `*_Hierarchy` table name (or `"None"` to clear).
#' @param lump Optional `*_Lump` table name (or `"None"` to clear).
#' @return An updated `vpro_workspace` object.
#' @export
vpro_use <- function(ws, project = NULL, su = NULL, hierarchy = NULL, lump = NULL) {
  vpro_assert_workspace(ws)
  out <- ws
  tables <- vpro_sqlite_physical_tables(out$project_path)
  if (!is.null(project)) {
    fams <- .vpro_project_discover(out$project_path)
    if (!(project %in% fams$project)) {
      cli::cli_abort(
        .vpro_cli_escape(paste0("Project `", project, "` not found in ", out$project_path)),
        class = c("vpro_error_workspace", "vpro_error")
      )
    }
    out$project <- project
  }
  if (!is.null(su)) {
    su_tables <- if (identical(out$su_path, out$project_path)) tables else vpro_sqlite_physical_tables(out$su_path)
    out["su"] <- list(vpro_resolve_table_suffix(su_tables, su, "SU", default_prefix = out$project))
  }
  if (!is.null(hierarchy)) {
    h_tables <- if (identical(out$hierarchy_path, out$project_path)) tables else vpro_sqlite_physical_tables(out$hierarchy_path)
    out["hierarchy"] <- list(vpro_resolve_table_suffix(h_tables, hierarchy, "Hierarchy", default_prefix = out$project))
  }
  if (!is.null(lump)) {
    out["lump"] <- list(vpro_resolve_table_suffix(tables, lump, "Lump", default_prefix = out$project))
  }
  out
}

#' Discover and list VPro projects in a workspace, directory, or `.db` file
#'
#' @param ws Optional `vpro_workspace` handle. When supplied (and `path` is not
#'   overridden), inspects `ws$project_path` and scans `ws$data_dir` and
#'   `file.path(ws$data_dir, "projects")` for `.db` project files.
#' @param path Optional directory or single `.db` file path to inspect (defaults
#'   to [vpro_data_dir()]).
#' @return A tibble with `project`, `path`, `version`, `complete`,
#'   `core_tables`, `optional_tables`, and `n_plots`.
#' @export
vpro_list_projects <- function(ws = NULL, path = vpro_data_dir()) {
  empty_tbl <- tibble::tibble(
    project = character(),
    path = character(),
    version = character(),
    complete = logical(),
    core_tables = integer(),
    optional_tables = integer(),
    n_plots = integer()
  )
  db_files <- character()
  if (!is.null(ws) && missing(path)) {
    vpro_assert_workspace(ws)
    db_files <- unique(c(
      ws$project_path,
      Sys.glob(file.path(ws$data_dir, "*.db")),
      Sys.glob(file.path(ws$data_dir, "projects", "*.db"))
    ))
  } else if (is.character(path) && length(path) == 1L && !is.na(path) && nzchar(trimws(path))) {
    p_clean <- trimws(path)
    if (file.exists(p_clean) && !dir.exists(p_clean)) {
      db_files <- p_clean
    } else if (dir.exists(p_clean)) {
      db_files <- unique(c(
        Sys.glob(file.path(p_clean, "*.db")),
        Sys.glob(file.path(p_clean, "projects", "*.db"))
      ))
    }
  }
  support_names <- tolower(c(
    "vpro64.db",
    "vlists.db",
    "vlists-lookup.db",
    "vuser.db",
    "vmetadata.db",
    "vmessageboard.db",
    "vpics.db",
    "bec.db",
    "working-unit.db",
    "site-codes.db",
    "soil-codes.db",
    "parent-codes.db",
    "region-codes.db",
    "geology-codes.db",
    "plot-quality-site.db"
  ))
  db_files <- db_files[file.exists(db_files) & !(tolower(basename(db_files)) %in% support_names)]
  if (length(db_files) == 0L) {
    return(empty_tbl)
  }
  rows <- list()
  for (p in sort(unique(as.character(normalizePath(db_files, winslash = "/", mustWork = TRUE))), method = "radix")) {
    disc <- tryCatch(.vpro_project_discover(p), error = function(e) NULL)
    if (is.null(disc) || nrow(disc) == 0L) {
      next
    }
    dbc <- vpro_sqlite_ro(p)
    for (i in seq_len(nrow(disc))) {
      prj <- disc$project[[i]]
      n_plots <- tryCatch(
        as.integer(DBI::dbGetQuery(dbc, paste0("SELECT COUNT(*) AS n FROM ", vpro_quote_ident(paste0(prj, "_Env"))))$n[[1L]]),
        error = function(e) NA_integer_
      )
      rows[[length(rows) + 1L]] <- tibble::tibble(
        project = prj,
        path = p,
        version = disc$version[[i]],
        complete = disc$complete[[i]],
        core_tables = disc$core_tables[[i]],
        optional_tables = disc$optional_tables[[i]],
        n_plots = n_plots
      )
    }
    DBI::dbDisconnect(dbc)
  }
  if (length(rows) == 0L) {
    return(empty_tbl)
  }
  do.call(rbind, rows)
}

vpro_list_suffixed_tables <- function(db_path, suffix, active_name = NULL, count_distinct = NULL) {
  tables <- vpro_sqlite_physical_tables(db_path)
  pat <- paste0("_", suffix, "$")
  hits <- grep(pat, tables, value = TRUE, ignore.case = TRUE)
  hits <- hits[!grepl("^USys", hits, ignore.case = TRUE)]
  if (length(hits) == 0L) {
    return(tibble::tibble(
      name = character(),
      table = character(),
      n_rows = integer(),
      n_distinct = integer(),
      active = logical()
    ))
  }
  dbc <- vpro_sqlite_ro(db_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  rows <- lapply(hits, function(tbl) {
    qt <- vpro_quote_ident(tbl)
    n_rows <- as.integer(DBI::dbGetQuery(dbc, paste0("SELECT COUNT(*) AS n FROM ", qt))$n[[1L]])
    n_dist <- if (!is.null(count_distinct) && count_distinct %in% DBI::dbListFields(dbc, tbl)) {
      as.integer(DBI::dbGetQuery(
        dbc,
        paste0("SELECT COUNT(DISTINCT ", vpro_quote_ident(count_distinct), ") AS n FROM ", qt)
      )$n[[1L]])
    } else {
      NA_integer_
    }
    tibble::tibble(
      name = sub(pat, "", tbl, ignore.case = TRUE),
      table = tbl,
      n_rows = n_rows,
      n_distinct = n_dist,
      active = !is.null(active_name) && identical(tolower(tbl), tolower(active_name))
    )
  })
  do.call(rbind, rows)
}

#' List site-unit (`*_SU`) tables in a workspace
#'
#' @param ws A `vpro_workspace` handle.
#' @return A tibble with `name`, `table`, `n_plots`, `n_units`, and `active`.
#' @export
vpro_list_su <- function(ws) {
  vpro_assert_workspace(ws)
  res <- vpro_list_suffixed_tables(ws$su_path, "SU", ws$su, count_distinct = "SiteUnit")
  names(res)[names(res) == "n_rows"] <- "n_plots"
  names(res)[names(res) == "n_distinct"] <- "n_units"
  res
}

#' List classification hierarchy (`*_Hierarchy`) tables in a workspace
#'
#' @param ws A `vpro_workspace` handle.
#' @return A tibble with `name`, `table`, `n_nodes`, and `active`.
#' @export
vpro_list_hierarchies <- function(ws) {
  vpro_assert_workspace(ws)
  res <- vpro_list_suffixed_tables(ws$hierarchy_path, "Hierarchy", ws$hierarchy)
  res$n_distinct <- NULL
  names(res)[names(res) == "n_rows"] <- "n_nodes"
  res
}

#' List species lump (`*_Lump`) tables in a workspace
#'
#' @param ws A `vpro_workspace` handle.
#' @return A tibble with `name`, `table`, `n_rows`, `n_lump_codes`, and `active`.
#' @export
vpro_list_lumps <- function(ws) {
  vpro_assert_workspace(ws)
  res <- vpro_list_suffixed_tables(ws$lump_path, "Lump", ws$lump, count_distinct = "LumpCode")
  names(res)[names(res) == "n_distinct"] <- "n_lump_codes"
  res
}

#' Open an explicit read-only in-memory DuckDB coordinator across workspace SQLite DBs
#'
#' Attaches `<Project>.db` as `project`, `VLists.db` as `vlists`, and `VUser.db`
#' as `vuser` in `READ_ONLY` mode via DuckDB's SQLite scanner. The caller owns
#' the returned `DBI` connection and should close it with `DBI::dbDisconnect()`.
#'
#' @param ws A `vpro_workspace` handle.
#' @return A `DBI` connection to an in-memory `duckdb` instance.
#' @export
vpro_duckdb <- function(ws) {
  vpro_assert_workspace(ws)
  rlang::check_installed("duckdb", reason = "to run cross-database DuckDB SQLite queries.")
  dcon <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  ok <- FALSE
  on.exit(if (!ok && DBI::dbIsValid(dcon)) DBI::dbDisconnect(dcon, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(dcon, paste0("ATTACH ", DBI::dbQuoteString(dcon, ws$project_path), " AS project (TYPE SQLITE, READ_ONLY)"))
  DBI::dbExecute(dcon, paste0("ATTACH ", DBI::dbQuoteString(dcon, ws$vlists_path), " AS vlists (TYPE SQLITE, READ_ONLY)"))
  DBI::dbExecute(dcon, paste0("ATTACH ", DBI::dbQuoteString(dcon, ws$vuser_path), " AS vuser (TYPE SQLITE, READ_ONLY)"))
  ok <- TRUE
  dcon
}

#' @export
print.vpro_workspace <- function(x, ...) {
  dbc <- vpro_sqlite_ro(x$project_path)
  on.exit(DBI::dbDisconnect(dbc), add = TRUE)
  n_env <- tryCatch(
    DBI::dbGetQuery(dbc, paste0("SELECT COUNT(*) AS n FROM ", vpro_quote_ident(paste0(x$project, "_Env"))))$n[[1L]],
    error = function(e) NA_integer_
  )
  n_su <- if (!is.null(x$su)) {
    dbc_su <- if (identical(x$su_path, x$project_path)) dbc else vpro_sqlite_ro(x$su_path)
    if (!identical(x$su_path, x$project_path)) {
      on.exit(DBI::dbDisconnect(dbc_su), add = TRUE)
    }
    tryCatch(
      DBI::dbGetQuery(dbc_su, paste0("SELECT COUNT(*) AS n FROM ", vpro_quote_ident(x$su)))$n[[1L]],
      error = function(e) NA_integer_
    )
  } else {
    NA_integer_
  }
  cli::cli_h3("vpro_workspace: {.val {x$project}} ({x$source})")
  cli::cli_bullets(c(
    "*" = paste0("Database: {.path {x$project_path}} (", n_env, " plots)"),
    "*" = paste0(
      "Active SU: {.val {if (is.null(x$su)) '<none>' else x$su}}",
      if (!is.na(n_su)) paste0(" (", n_su, " assignments)") else ""
    ),
    "*" = "Hierarchy: {.val {if (is.null(x$hierarchy)) '<none>' else x$hierarchy}} | Lump: {.val {if (is.null(x$lump)) '<none>' else x$lump}}"
  ))
  invisible(x)
}

#' @export
summary.vpro_workspace <- function(object, ...) {
  list(
    project = object$project,
    project_path = object$project_path,
    su = object$su,
    hierarchy = object$hierarchy,
    lump = object$lump,
    projects = vpro_list_projects(object),
    su_tables = vpro_list_su(object),
    hierarchies = vpro_list_hierarchies(object),
    lumps = vpro_list_lumps(object)
  )
}
