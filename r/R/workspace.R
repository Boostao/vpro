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

vpro_clean_posix_path <- function(p) {
  out <- gsub("\\\\", "/", p)
  out <- gsub("/+", "/", out)
  if (nchar(out) > 1L) {
    out <- sub("/+$", "", out)
  }
  out
}

vpro_abs_path <- function(p) {
  if (.Platform$OS.type == "windows" && grepl("^/[^/\\\\]", p)) {
    return(vpro_clean_posix_path(p))
  }
  is_abs <- grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", p)
  if (!is_abs && !startsWith(p, "~")) {
    p <- file.path(getwd(), p)
  }
  normalizePath(p, winslash = "/", mustWork = FALSE)
}

vpro_resolve_data_dir <- function(
  os = Sys.info()[["sysname"]],
  opt = getOption("vpro.data_dir"),
  env_data = Sys.getenv("VPRO_DATA_DIR", unset = ""),
  localappdata = Sys.getenv("LOCALAPPDATA", unset = ""),
  userprofile = Sys.getenv("USERPROFILE", unset = ""),
  xdg_data = Sys.getenv("XDG_DATA_HOME", unset = ""),
  home = Sys.getenv("HOME", unset = "~")
) {
  override <- vpro_first_nonempty(opt, env_data)
  if (nzchar(override)) {
    return(vpro_abs_path(override))
  }
  os_low <- tolower(as.character(os))
  if (grepl("windows|mingw", os_low)) {
    if (nzchar(localappdata)) {
      p <- file.path(localappdata, "vpro")
    } else {
      base_home <- vpro_first_nonempty(userprofile, home)
      p <- file.path(base_home, "AppData", "Local", "vpro")
    }
  } else if (identical(os_low, "darwin")) {
    p <- file.path(home, "Library", "Application Support", "vpro")
  } else {
    base_xdg <- if (nzchar(xdg_data)) xdg_data else file.path(home, ".local", "share")
    p <- file.path(base_xdg, "vpro")
  }
  vpro_abs_path(p)
}

vpro_resolve_config_dir <- function(
  os = Sys.info()[["sysname"]],
  opt = getOption("vpro.config_dir"),
  env_cfg = Sys.getenv("VPRO_CONFIG_DIR", unset = ""),
  appdata = Sys.getenv("APPDATA", unset = ""),
  userprofile = Sys.getenv("USERPROFILE", unset = ""),
  xdg_cfg = Sys.getenv("XDG_CONFIG_HOME", unset = ""),
  home = Sys.getenv("HOME", unset = "~")
) {
  override <- vpro_first_nonempty(opt, env_cfg)
  if (nzchar(override)) {
    return(vpro_abs_path(override))
  }
  os_low <- tolower(as.character(os))
  if (grepl("windows|mingw", os_low)) {
    if (!nzchar(appdata)) {
      rlang::abort("%APPDATA% is not defined; cannot resolve Windows VPro configuration directory.")
    }
    p <- file.path(appdata, "vpro")
  } else if (identical(os_low, "darwin")) {
    p <- file.path(home, "Library", "Application Support", "vpro")
  } else {
    base_xdg <- if (nzchar(xdg_cfg)) xdg_cfg else file.path(home, ".config")
    p <- file.path(base_xdg, "vpro")
  }
  vpro_abs_path(p)
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
    rlang::abort(
      "VPro project names must start with a letter, contain only letters, digits, or underscores, and be at most 31 characters."
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
    rlang::abort(paste0("VPro project database does not exist: ", path))
  }
  if (is.null(project)) {
    disc <- .vpro_project_discover(path)
    if (nrow(disc) == 0L) {
      rlang::abort(paste0("Database contains no `<Project>_Env` table: ", path))
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
    rlang::abort(paste0(
      "Table `",
      req_full,
      "` was not found. Available `*",
      "_",
      suffix,
      "` tables: ",
      if (length(candidates)) paste(candidates, collapse = ", ") else "<none>"
    ))
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

#' Connect to a live `VPro` workspace, bundled `Sample`, SQLite `.db`, or Access archive
#'
#' Creates a lightweight, read-only-by-default S3 `vpro_workspace` handle.
#' Called with zero arguments (`vpro_connect()`), auto-discovers the user's
#' active `VPro` `config.yml` and VPro Desktop project workspace. Passing `"Sample"`
#' (with default `data_dir`) opens the bundled read-only 2026 `VP08` `Sample`
#' teaching workspace. Also accepts an explicit project name in `data_dir`, a
#' `.db` / `.sqlite` / `.rds` file path, a directory containing `.db` projects,
#' or an `.accdb` / `.mdb` archive (which is non-destructively converted into a
#' session-temporary `VP08` SQLite file).
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
  data_dir_missing <- missing(data_dir)
  data_dir <- normalizePath(data_dir, winslash = "/", mustWork = FALSE)
  config_dir <- normalizePath(config_dir, winslash = "/", mustWork = FALSE)
  cfg_path <- file.path(config_dir, "config.yml")
  cfg_cur <- list()
  if (file.exists(cfg_path)) {
    parsed <- tryCatch(yaml::read_yaml(cfg_path, readLines.warn = FALSE), error = function(e) NULL)
    if (is.list(parsed) && is.list(parsed$Current)) {
      cfg_cur <- parsed$Current
    }
  }

  source_kind <- "workspace"
  project_path <- NULL
  project_name <- NULL
  su_db_override <- NULL
  hier_db_override <- NULL

  if (is.null(project)) {
    # Auto-discover from config.yml + data_dir
    cfg_prj <- if (!is.null(cfg_cur$CurrProject) && nzchar(trimws(as.character(cfg_cur$CurrProject)))) {
      trimws(as.character(cfg_cur$CurrProject))
    } else {
      NULL
    }
    cfg_prj_path <- if (!is.null(cfg_cur$ProjectPath) && nzchar(trimws(as.character(cfg_cur$ProjectPath)))) {
      trimws(as.character(cfg_cur$ProjectPath))
    } else {
      NULL
    }
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
      if (nrow(listed) > 0L) {
        project_path <- listed$path[[1L]]
        project_name <- listed$project[[1L]]
      } else {
        rlang::abort(c(
          "No VPro project database was found in the workspace.",
          "i" = paste0("Checked data_dir: ", data_dir),
          "i" = "Pass an explicit `.db` path or call `vpro_connect(\"Sample\")` for the bundled Sample workspace."
        ))
      }
    }
    if (is.null(su) && !is.null(cfg_cur$CurrPlotlist) && nzchar(trimws(as.character(cfg_cur$CurrPlotlist)))) {
      su <- trimws(as.character(cfg_cur$CurrPlotlist))
    }
    if (
      !is.null(cfg_cur$SUPath) &&
        nzchar(trimws(as.character(cfg_cur$SUPath))) &&
        file.exists(trimws(as.character(cfg_cur$SUPath))) &&
        !dir.exists(trimws(as.character(cfg_cur$SUPath)))
    ) {
      su_db_override <- normalizePath(trimws(as.character(cfg_cur$SUPath)), winslash = "/", mustWork = TRUE)
    }
    if (is.null(hierarchy) && !is.null(cfg_cur$CurrHierarchy) && nzchar(trimws(as.character(cfg_cur$CurrHierarchy)))) {
      hierarchy <- trimws(as.character(cfg_cur$CurrHierarchy))
    }
    if (
      !is.null(cfg_cur$HierarchyPath) &&
        nzchar(trimws(as.character(cfg_cur$HierarchyPath))) &&
        file.exists(trimws(as.character(cfg_cur$HierarchyPath))) &&
        !dir.exists(trimws(as.character(cfg_cur$HierarchyPath)))
    ) {
      hier_db_override <- normalizePath(trimws(as.character(cfg_cur$HierarchyPath)), winslash = "/", mustWork = TRUE)
    }
    if (is.null(lump) && !is.null(cfg_cur$CurrLump) && nzchar(trimws(as.character(cfg_cur$CurrLump)))) {
      lump <- trimws(as.character(cfg_cur$CurrLump))
    }
  } else {
    if (!is.character(project) || length(project) != 1L || is.na(project) || !nzchar(trimws(project))) {
      rlang::abort("`project` must be NULL or a single non-empty character string.")
    }
    req <- trimws(project)
    if (dir.exists(req)) {
      listed <- vpro_list_projects(path = req)
      if (nrow(listed) == 0L) {
        rlang::abort(paste0("No VPro `.db` projects were found in directory: ", req))
      }
      project_path <- listed$path[[1L]]
      project_name <- listed$project[[1L]]
      data_dir <- normalizePath(req, winslash = "/", mustWork = TRUE)
      source_kind <- "directory"
    } else if (file.exists(req)) {
      ext <- tolower(tools::file_ext(req))
      if (ext %in% c("accdb", "mdb")) {
        tmp_db <- tempfile(pattern = "vpro-access-ws-", fileext = ".db")
        imp <- vpro_import_access(req, dest_db = tmp_db)
        project_path <- imp$target_db
        project_name <- imp$target_project
        source_kind <- "access_import"
      } else if (identical(ext, "rds")) {
        return(vpro_import_rds(req, su = su, lump = lump))
      } else {
        project_path <- normalizePath(req, winslash = "/", mustWork = TRUE)
        bundled_sample <- normalizePath(vpro_bundled_db("Sample.db"), winslash = "/", mustWork = FALSE)
        source_kind <- if (identical(project_path, bundled_sample)) "sample" else "file"
      }
    } else if (identical(tolower(req), "sample") && data_dir_missing) {
      sample_path <- vpro_bundled_db("Sample.db")
      project_path <- normalizePath(sample_path, winslash = "/", mustWork = TRUE)
      project_name <- "Sample"
      data_dir <- dirname(project_path)
      config_dir <- tempdir()
      source_kind <- "sample"
      if (is.null(su)) {
        su <- "Sample_SU"
      }
      if (is.null(hierarchy)) {
        hierarchy <- "Sample_Hierarchy"
      }
      if (is.null(lump)) lump <- "Sample_Lump"
    } else {
      # Look up project name inside data_dir
      base <- sub("\\.(db|sqlite|sqlite3)$", "", req, ignore.case = TRUE)
      candidates <- c(
        file.path(data_dir, "projects", paste0(base, ".db")),
        file.path(data_dir, paste0(base, ".db"))
      )
      existing <- candidates[file.exists(candidates) & !dir.exists(candidates)]
      if (length(existing) > 0L) {
        project_path <- normalizePath(existing[[1L]], winslash = "/", mustWork = TRUE)
        project_name <- base
      } else if (identical(tolower(base), "sample")) {
        sample_path <- vpro_bundled_db("Sample.db")
        project_path <- normalizePath(sample_path, winslash = "/", mustWork = TRUE)
        project_name <- "Sample"
        data_dir <- dirname(project_path)
        config_dir <- tempdir()
        source_kind <- "sample"
        if (is.null(su)) {
          su <- "Sample_SU"
        }
        if (is.null(hierarchy)) {
          hierarchy <- "Sample_Hierarchy"
        }
        if (is.null(lump)) lump <- "Sample_Lump"
      } else {
        rlang::abort(paste0("Could not find VPro project `", req, "` as a file or inside `", data_dir, "`."))
      }
    }
  }

  fams <- .vpro_project_discover(project_path)
  if (nrow(fams) == 0L) {
    rlang::abort(paste0("Database contains no `<Project>_Env` table: ", project_path))
  }
  if (is.null(project_name) || !(project_name %in% fams$project)) {
    stem <- tools::file_path_sans_ext(basename(project_path))
    if (stem %in% fams$project) {
      project_name <- stem
    } else {
      project_name <- fams$project[[1L]]
    }
  }

  tables <- vpro_sqlite_physical_tables(project_path)
  su_path <- if (!is.null(su_db_override)) su_db_override else project_path
  su_tables <- if (identical(su_path, project_path)) tables else vpro_sqlite_physical_tables(su_path)
  resolved_su <- tryCatch(
    vpro_resolve_table_suffix(su_tables, su, "SU", default_prefix = project_name),
    error = function(e) {
      if (identical(source_kind, "workspace") && is.null(su)) NULL else stop(e)
    }
  )

  hier_path <- if (!is.null(hier_db_override)) hier_db_override else project_path
  hier_tables <- if (identical(hier_path, project_path)) tables else vpro_sqlite_physical_tables(hier_path)
  resolved_hier <- tryCatch(
    vpro_resolve_table_suffix(hier_tables, hierarchy, "Hierarchy", default_prefix = project_name),
    error = function(e) {
      if (identical(source_kind, "workspace") && is.null(hierarchy)) NULL else stop(e)
    }
  )

  resolved_lump <- vpro_resolve_table_suffix(tables, lump, "Lump", default_prefix = project_name)

  proj_dir <- dirname(project_path)
  ws_obj <- structure(
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
  ws_obj
}

vpro_assert_workspace <- function(ws) {
  if (inherits(ws, "vpro_pg_conn")) {
    rlang::abort(c(
      "`ws` is a PostgreSQL `vpro_pg_conn` handle, not a local `vpro_workspace`.",
      "i" = "Use `vpro_master_env(pg, ...)` / `vpro_master_veg(pg, ...)` for direct cloud tibbles, or wrap a filtered cloud subset with `vpro_master_workspace(pg, ...)` / `vpro_master_pull(pg, ...)`."
    ))
  }
  if (!inherits(ws, "vpro_workspace") || !is.list(ws) || is.null(ws$project_path) || !file.exists(ws$project_path)) {
    rlang::abort("`ws` must be a valid `vpro_workspace` created by `vpro_connect()`.")
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
      rlang::abort(paste0("Project `", project, "` not found in ", out$project_path))
    }
    out$project <- project
  }
  if (!is.null(su)) {
    su_tables <- if (identical(out$su_path, out$project_path)) tables else vpro_sqlite_physical_tables(out$su_path)
    out$su <- vpro_resolve_table_suffix(su_tables, su, "SU", default_prefix = out$project)
  }
  if (!is.null(hierarchy)) {
    h_tables <- if (identical(out$hierarchy_path, out$project_path)) tables else vpro_sqlite_physical_tables(out$hierarchy_path)
    out$hierarchy <- vpro_resolve_table_suffix(h_tables, hierarchy, "Hierarchy", default_prefix = out$project)
  }
  if (!is.null(lump)) {
    out$lump <- vpro_resolve_table_suffix(tables, lump, "Lump", default_prefix = out$project)
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
  for (p in sort(unique(normalizePath(db_files, winslash = "/", mustWork = TRUE)))) {
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
    "*" = "Database: {.path {x$project_path}} ({n_env} plots)",
    "*" = "Active SU: {.val {if (is.null(x$su)) '<none>' else x$su}}{if (!is.na(n_su)) paste0(' (', n_su, ' assignments)') else ''}",
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
