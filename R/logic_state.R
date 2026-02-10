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

# Preferences storage (SaveSetting/GetSetting analog)
ensure_user_settings_table <- function(con, schema = "user_db.main", table = "user_settings") {
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
}

coerce_pref_value <- function(value, default) {
  if (is.null(default)) return(value)
  if (is.logical(default)) return(tolower(value) %in% c("true", "1", "yes"))
  if (is.integer(default)) return(as.integer(value))
  if (is.double(default)) return(as.numeric(value))
  return(value)
}

get_pref <- function(con, section, key, default = NULL, app = "VPro64", schema = "user_db.main", table = "user_settings") {
  ensure_user_settings_table(con, schema = schema, table = table)
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
  ensure_user_settings_table(con, schema = schema, table = table)
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
  
  # Load Metadata
  # VPro: USysProjectMetadata
  meta <- dbGetQuery(con, "SELECT * FROM Sample_Metadata WHERE ProjectID = ?", list(project_id))
  
  if (nrow(meta) > 0) {
    state$ProjectMetadata <- as.list(meta[1, ])
  } else {
    state$ProjectMetadata <- list()
    warning(paste("No metadata found for project:", project_id))
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
