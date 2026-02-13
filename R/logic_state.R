# Logic: Global State Management
# Replicates V7mdlGlobalDeclarations

# VBA-style message box constants
MB_OK <- 0
MB_OKCANCEL <- 1
MB_YESNOCANCEL <- 3
MB_YESNO <- 4
MB_ICONSTOP <- 16
MB_ICONQUESTION <- 32
MB_ICONEXCLAMATION <- 48
MB_ICONINFORMATION <- 64
MB_DEFBUTTON2 <- 256
IDYES <- 6
IDNO <- 7
SW_SHOW <- 1

# We use a list-based approach or R6, but for Shiny, passing a reactiveValues object 
# named `state` is the standard pattern. This file defines helper functions to mutators.

#' Initialize System State
#' @return A reactiveValues object with default fields
init_sys_state <- function() {
  shiny::reactiveValues(
    # Core Context
    CurrProject = NULL,      # Current Project ID (String)
    CurrSU = NULL,           # Current Plot/SiteUnit (String)
    CurrHierarchy = NULL,    # Classification Hierarchy Context
    CurrPicture = NULL,
    CurrForm = NULL,
    CurrFormLoc = list(left = 0L, top = 0L, right = 0L, bottom = 0L),
    CurrProjectName = NULL,
    
    # Settings
    LumpingTable = NULL,     # Active Lumping Table ID
    User = Sys.getenv("USER", "Unknown"),
    FileTitle = NULL,
    CancelEvent = 0L,
    UnattachObject = NULL,
    SaveTo = 0L,
    PlotNumber = NULL,
    PicturePlotNumber = NULL,
    System = NULL,
    OptShowClassValue = 0L,
    NewSpp = NULL,
    RemoteProject = NULL,
    RemoteDB = NULL,
    BreakSU = NULL,
    OldUnit = NULL,
    LumpMsg = NULL,
    ShowVegValue = NA_real_,
    CreateReportSummary = FALSE,
    HierarchyType = NULL,
    IncludeDiagnostic = FALSE,
    VENUSProject = NULL,
    SaveFilter2 = 0L,
    IncludeExisting = 0L,
    PickTable = NULL,
    ComboTable = NULL,
    PickItem = NULL,
    StopCode = FALSE,
    SelectedItems = list(),
    ExportProject = NULL,
    DoEvent = FALSE,
    HierarchyLongName = NULL,

    # Access-style aliases for compatibility with VBA naming
    sysFileTitle = NULL,
    sysCancelEvent = 0L,
    sysUnattachObject = NULL,
    sysSaveTo = 0L,
    sysplotnumber = NULL,
    sysPicturePlotNumber = NULL,
    sysLumpingTable = NULL,
    sysSystem = NULL,
    sysOptShowClassValue = 0L,
    sysNewSpp = NULL,
    sysRemoteProject = NULL,
    sysRemoteDB = NULL,
    sysCurrProject = NULL,
    sysCurrPicture = NULL,
    sysCurrSU = NULL,
    sysBreakSU = NULL,
    sysCurrHierarchy = NULL,
    sysOldUnit = NULL,
    sysLumpMsg = NULL,
    sysShowVegValue = NA_real_,
    sysCreateReportSummary = FALSE,
    sysHierarchyType = NULL,
    sysIncludeDiagnostic = FALSE,
    sysVENUSProject = NULL,
    sysSaveFilter2 = 0L,
    sysIncludeExisting = 0L,
    sysPickTable = NULL,
    sysCurrForm = NULL,
    sysComboTable = NULL,
    sysPickItem = NULL,
    sysStopCode = FALSE,
    sysSelectedItems = list(),
    sysExportProject = NULL,
    sysDoEvent = FALSE,
    sysHierarchyLongName = NULL,
    
    # Metadata Cache (loaded when Project changes)
    ProjectMetadata = NULL
  )
}

list_main_tables <- function(con) {
  tryCatch({
    tbl <- DBI::dbGetQuery(
      con,
      "SELECT table_name FROM duckdb_tables() WHERE internal = FALSE AND schema_name = 'main'"
    )
    unique(as.character(tbl$table_name))
  }, error = function(e) {
    unique(as.character(DBI::dbListTables(con)))
  })
}

discover_prefixes_by_suffix <- function(con, suffix) {
  if (is.null(suffix) || !nzchar(suffix)) return(character(0))

  tables <- list_main_tables(con)
  if (length(tables) == 0) return(character(0))

  suffix_lower <- tolower(suffix)
  out <- character(0)

  for (tbl in tables) {
    tbl_lower <- tolower(tbl)
    if (!endsWith(tbl_lower, suffix_lower)) next
    if (startsWith(tbl_lower, "usys")) next
    out <- c(out, substr(tbl, 1, nchar(tbl) - nchar(suffix)))
  }

  sort(unique(out))
}

resolve_prefixed_table <- function(con, prefix, suffix) {
  if (is.null(prefix) || !nzchar(prefix) || is.null(suffix) || !nzchar(suffix)) {
    return(NULL)
  }

  target <- paste0(prefix, suffix)
  tables <- list_main_tables(con)
  if (target %in% tables) return(target)

  idx <- match(tolower(target), tolower(tables))
  if (!is.na(idx)) return(tables[[idx]])

  NULL
}

is_valid_project_prefix <- function(prefix) {
  is.character(prefix) &&
    length(prefix) == 1L &&
    !is.na(prefix) &&
    grepl("^[A-Za-z][A-Za-z0-9_]*$", prefix)
}

list_project_tables <- function(con, prefix) {
  if (!is_valid_project_prefix(prefix)) return(character(0))

  tables <- list_main_tables(con)
  pattern <- paste0("^", prefix, "_")
  tables[grepl(pattern, tables, ignore.case = TRUE)]
}

create_project_table_set <- function(con, prefix, template_prefix = "Sample", overwrite = FALSE) {
  if (!is_valid_project_prefix(prefix)) {
    stop("Invalid project prefix. Use letters, numbers, and underscore; must start with a letter.")
  }
  if (!is_valid_project_prefix(template_prefix)) {
    stop("Invalid template prefix.")
  }
  if (tolower(prefix) == tolower(template_prefix)) {
    stop("New project prefix must differ from template prefix.")
  }

  tables <- list_main_tables(con)
  template_pattern <- paste0("^", template_prefix, "_")
  template_tables <- tables[grepl(template_pattern, tables, ignore.case = TRUE)]

  if (length(template_tables) == 0) {
    stop("No template tables found for prefix '", template_prefix, "'.")
  }

  for (template_tbl in template_tables) {
    suffix <- sub(
      paste0("^", template_prefix),
      "",
      template_tbl,
      ignore.case = TRUE
    )
    target_tbl <- paste0(prefix, suffix)

    if (DBI::dbExistsTable(con, target_tbl)) {
      if (!isTRUE(overwrite)) {
        stop("Target table already exists: ", target_tbl)
      }
      DBI::dbExecute(con, paste0("DROP TABLE ", DBI::dbQuoteIdentifier(con, target_tbl)))
    }

    DBI::dbExecute(
      con,
      paste0(
        "CREATE TABLE ", DBI::dbQuoteIdentifier(con, target_tbl), " AS ",
        "SELECT * FROM ", DBI::dbQuoteIdentifier(con, template_tbl), " WHERE 1=0"
      )
    )
  }

  metadata_table <- resolve_prefixed_table(con, prefix, "_Metadata")
  if (!is.null(metadata_table)) {
    cols <- tryCatch(DBI::dbListFields(con, metadata_table), error = function(e) character(0))
    project_col <- cols[[match("projectid", tolower(cols))]]
    if (!is.null(project_col) && nzchar(project_col)) {
      DBI::dbExecute(
        con,
        paste0(
          "INSERT INTO ", DBI::dbQuoteIdentifier(con, metadata_table), " (",
          DBI::dbQuoteIdentifier(con, project_col), ") VALUES (?)"
        ),
        list(prefix)
      )
    }
  }

  invisible(prefix)
}

unattach_project_table_set <- function(con, prefix, protected_prefixes = c("Sample")) {
  if (!is_valid_project_prefix(prefix)) {
    stop("Invalid project prefix.")
  }

  protected <- tolower(protected_prefixes)
  if (tolower(prefix) %in% protected) {
    stop("Cannot unattach protected project prefix: ", prefix)
  }

  project_tables <- list_project_tables(con, prefix)
  if (length(project_tables) == 0) {
    return(invisible(character(0)))
  }

  for (tbl in project_tables) {
    DBI::dbExecute(con, paste0("DROP TABLE ", DBI::dbQuoteIdentifier(con, tbl)))
  }

  invisible(project_tables)
}

attach_project_table_set <- function(con, db_path, prefix, replace_existing = FALSE, alias = "tmp_project_attach") {
  if (!is_valid_project_prefix(prefix)) {
    stop("Invalid project prefix.")
  }
  if (!is.character(db_path) || length(db_path) != 1L || is.na(db_path) || !nzchar(db_path)) {
    stop("Database path is required.")
  }
  if (!file.exists(db_path)) {
    stop("Database file does not exist: ", db_path)
  }

  attached <- list_attached_dbs(con)
  if (alias %in% attached) {
    detach_db(con, alias)
  }

  path_literal <- DBI::dbQuoteString(con, db_path)
  alias_ident <- DBI::dbQuoteIdentifier(con, alias)
  DBI::dbExecute(con, paste0("ATTACH ", path_literal, " AS ", alias_ident))

  on.exit({
    try(detach_db(con, alias), silent = TRUE)
  }, add = TRUE)

  src_tables <- DBI::dbGetQuery(
    con,
    "SELECT table_name FROM duckdb_tables() WHERE internal = FALSE AND schema_name = 'main' AND database_name = ?",
    list(alias)
  )$table_name

  pattern <- paste0("^", prefix, "_")
  src_tables <- src_tables[grepl(pattern, src_tables, ignore.case = TRUE)]
  if (length(src_tables) == 0) {
    stop("No project tables found in source DB for prefix: ", prefix)
  }

  copied <- character(0)
  for (tbl in src_tables) {
    if (DBI::dbExistsTable(con, tbl)) {
      if (!isTRUE(replace_existing)) {
        stop("Target table already exists: ", tbl)
      }
      DBI::dbExecute(con, paste0("DROP TABLE ", DBI::dbQuoteIdentifier(con, tbl)))
    }

    DBI::dbExecute(
      con,
      paste0(
        "CREATE TABLE ", DBI::dbQuoteIdentifier(con, tbl), " AS ",
        "SELECT * FROM ", DBI::dbQuoteIdentifier(con, alias), ".", DBI::dbQuoteIdentifier(con, tbl)
      )
    )
    copied <- c(copied, tbl)
  }

  invisible(copied)
}

create_prefixed_table_from_template <- function(con, prefix, suffix, template_prefix = "Sample", overwrite = FALSE) {
  if (!is_valid_project_prefix(prefix)) {
    stop("Invalid project prefix. Use letters, numbers, and underscore; must start with a letter.")
  }
  if (!is_valid_project_prefix(template_prefix)) {
    stop("Invalid template prefix.")
  }
  if (is.null(suffix) || !nzchar(suffix) || !grepl("^_[A-Za-z0-9_]+$", suffix)) {
    stop("Invalid suffix.")
  }

  template_tbl <- resolve_prefixed_table(con, template_prefix, suffix)
  if (is.null(template_tbl)) {
    stop("Template table not found: ", paste0(template_prefix, suffix))
  }

  target_tbl <- paste0(prefix, suffix)
  if (DBI::dbExistsTable(con, target_tbl)) {
    if (!isTRUE(overwrite)) {
      stop("Target table already exists: ", target_tbl)
    }
    DBI::dbExecute(con, paste0("DROP TABLE ", DBI::dbQuoteIdentifier(con, target_tbl)))
  }

  DBI::dbExecute(
    con,
    paste0(
      "CREATE TABLE ", DBI::dbQuoteIdentifier(con, target_tbl), " AS ",
      "SELECT * FROM ", DBI::dbQuoteIdentifier(con, template_tbl), " WHERE 1=0"
    )
  )

  invisible(target_tbl)
}

unattach_prefixed_table <- function(con, prefix, suffix, protected_prefixes = c("Sample")) {
  if (!is_valid_project_prefix(prefix)) {
    stop("Invalid project prefix.")
  }
  if (is.null(suffix) || !nzchar(suffix) || !grepl("^_[A-Za-z0-9_]+$", suffix)) {
    stop("Invalid suffix.")
  }

  if (tolower(prefix) %in% tolower(protected_prefixes)) {
    stop("Cannot unattach protected prefix: ", prefix)
  }

  target_tbl <- resolve_prefixed_table(con, prefix, suffix)
  if (is.null(target_tbl)) {
    return(invisible(NULL))
  }

  DBI::dbExecute(con, paste0("DROP TABLE ", DBI::dbQuoteIdentifier(con, target_tbl)))
  invisible(target_tbl)
}

attach_prefixed_table <- function(con, db_path, prefix, suffix, replace_existing = FALSE, alias = "tmp_single_attach") {
  if (!is_valid_project_prefix(prefix)) {
    stop("Invalid project prefix.")
  }
  if (is.null(suffix) || !nzchar(suffix) || !grepl("^_[A-Za-z0-9_]+$", suffix)) {
    stop("Invalid suffix.")
  }
  if (!is.character(db_path) || length(db_path) != 1L || is.na(db_path) || !nzchar(db_path)) {
    stop("Database path is required.")
  }
  if (!file.exists(db_path)) {
    stop("Database file does not exist: ", db_path)
  }

  attached <- list_attached_dbs(con)
  if (alias %in% attached) {
    detach_db(con, alias)
  }

  path_literal <- DBI::dbQuoteString(con, db_path)
  alias_ident <- DBI::dbQuoteIdentifier(con, alias)
  DBI::dbExecute(con, paste0("ATTACH ", path_literal, " AS ", alias_ident))

  on.exit({
    try(detach_db(con, alias), silent = TRUE)
  }, add = TRUE)

  src_table <- paste0(prefix, suffix)
  src_exists <- DBI::dbGetQuery(
    con,
    "SELECT COUNT(*) AS n FROM duckdb_tables() WHERE internal = FALSE AND schema_name = 'main' AND database_name = ? AND lower(table_name) = lower(?)",
    list(alias, src_table)
  )$n[[1]] > 0

  if (!isTRUE(src_exists)) {
    stop("Source table not found in attached DB: ", src_table)
  }

  if (DBI::dbExistsTable(con, src_table)) {
    if (!isTRUE(replace_existing)) {
      stop("Target table already exists: ", src_table)
    }
    DBI::dbExecute(con, paste0("DROP TABLE ", DBI::dbQuoteIdentifier(con, src_table)))
  }

  DBI::dbExecute(
    con,
    paste0(
      "CREATE TABLE ", DBI::dbQuoteIdentifier(con, src_table), " AS ",
      "SELECT * FROM ", DBI::dbQuoteIdentifier(con, alias), ".", DBI::dbQuoteIdentifier(con, src_table)
    )
  )

  invisible(src_table)
}

# Preferences storage (SaveSetting/GetSetting analog)
resolve_pref_schema <- function(con, schema) {
  if (!is.character(schema) || length(schema) != 1L || is.na(schema) || !nzchar(schema)) {
    return("main")
  }

  schema_parts <- strsplit(schema, "\\.", fixed = FALSE)[[1]]
  if (length(schema_parts) >= 2L && identical(schema_parts[[1]], "user_db")) {
    dbs <- tryCatch(DBI::dbGetQuery(con, "PRAGMA database_list"), error = function(e) NULL)
    if (is.null(dbs) || !("name" %in% names(dbs)) || !("user_db" %in% dbs$name)) {
      return("main")
    }
  }

  schema
}

ensure_user_settings_table <- function(con, schema = "user_db.main", table = "user_settings") {
  schema <- resolve_pref_schema(con, schema)
  DBI::dbExecute(
    con,
    paste0(
      "CREATE TABLE IF NOT EXISTS ", schema, ".", table, " (",
      "app TEXT, ",
      "section TEXT, ",
      "key TEXT, ",
      "value TEXT, ",
      "updated_at TIMESTAMP, ",
      "PRIMARY KEY(app, section, key)",
      ")"
    )
  )
  invisible(schema)
}

coerce_pref_value <- function(value, default) {
  if (is.null(default)) return(value)
  if (is.logical(default)) return(tolower(value) %in% c("true", "1", "yes"))
  if (is.integer(default)) return(as.integer(value))
  if (is.double(default)) return(as.numeric(value))
  return(value)
}

get_pref <- function(con, section, key, default = NULL, app = "VPro64", schema = "user_db.main", table = "user_settings") {
  schema <- ensure_user_settings_table(con, schema = schema, table = table)
  res <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT value FROM ", schema, ".", table, " ",
      "WHERE app = ? AND section = ? AND key = ?"
    ),
    list(app, section, key)
  )
  if (nrow(res) == 0) return(default)
  coerce_pref_value(res$value[[1]], default)
}

set_pref <- function(con, section, key, value, app = "VPro64", schema = "user_db.main", table = "user_settings") {
  schema <- ensure_user_settings_table(con, schema = schema, table = table)
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO ", schema, ".", table, " (app, section, key, value, updated_at) ",
      "VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP) ",
      "ON CONFLICT (app, section, key) DO UPDATE SET ",
      "value = excluded.value, updated_at = excluded.updated_at"
    ),
    list(app, section, key, as.character(value))
  )
}

seed_pref_default <- function(con, section, key, value, app = "VPro64") {
  existing <- get_pref(con, section, key, default = NULL, app = app)
  if (is.null(existing)) {
    set_pref(con, section, key, value, app = app)
  }
}

seed_default_preferences <- function(con, app = "VPro64") {
  seed_pref_default(con, "Current", "CurrProject", "Sample", app = app)
  seed_pref_default(con, "Current", "CurrPlotList", "None", app = app)
  seed_pref_default(con, "Current", "CurrHierarchy", "Sample", app = app)
  seed_pref_default(con, "Current", "DataFormName", "FS882-6x4", app = app)
  seed_pref_default(con, "ReportOptions", "cmbColourGreater", 5, app = app)
  seed_pref_default(con, "ReportOptions", "cmbGrayGreater", 65, app = app)
  seed_pref_default(con, "ReportOptions", "cmbApplyTheme", 1, app = app)
  seed_pref_default(con, "System", "Version", 3, app = app)
  seed_pref_default(con, "System", "Build", format(Sys.Date(), "%Y-%m-%d"), app = app)
  seed_pref_default(con, "System", "Installed", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), app = app)
  seed_pref_default(con, "Message", "ShowWhatsNew", TRUE, app = app)
}

#' Set Current Project
#' Updates state and loads relevant metadata
#' @param state The global reactiveValues object
#' @param project_id The ProjectID to switch to
#' @param con Database connection
set_project <- function(state, project_id, con) {
  shiny::req(project_id)
  
  # Update State
  state$CurrProject <- project_id
  state$sysCurrProject <- project_id
  state$CurrProjectName <- project_id
  
  meta <- data.frame()

  project_meta_table <- resolve_prefixed_table(con, project_id, "_Metadata")
  if (!is.null(project_meta_table)) {
    meta <- tryCatch(
      DBI::dbGetQuery(con, paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(con, project_meta_table), " LIMIT 1")),
      error = function(e) data.frame()
    )
  }

  if (nrow(meta) == 0 && DBI::dbExistsTable(con, "Sample_Metadata")) {
    meta <- tryCatch(
      DBI::dbGetQuery(con, "SELECT * FROM Sample_Metadata WHERE ProjectID = ?", list(project_id)),
      error = function(e) data.frame()
    )
  }

  if (nrow(meta) > 0) {
    state$ProjectMetadata <- as.list(meta[1, , drop = FALSE])
  } else {
    state$ProjectMetadata <- list(projectid = project_id)
  }
  
  # Reset dependent context
  state$CurrSU <- NULL
  state$sysCurrSU <- NULL
  
  # VPro Logic: Load default Lumping/Sort options if they exist in metadata
  # (Placeholder for expanding logic based on USysProjectMetadata columns)
}

#' Set Current Site Unit (Plot)
#' @param state The global reactiveValues object
#' @param plot_number The PlotNumber (String uniqueness across projects depends on VPro logic, typically unique)
set_su <- function(state, plot_number) {
  state$CurrSU <- plot_number
  state$sysCurrSU <- plot_number
  state$PlotNumber <- plot_number
  state$sysplotnumber <- plot_number
}
