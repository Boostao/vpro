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
    # VBA global declarations
    CurrFormLoc = list(left = 0L, top = 0L, right = 0L, bottom = 0L),
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

    # Additional module-level VBA globals discovered outside V7mdlGlobalDeclarations.
    sysSpeciesTestNext = 0L,
    sysSpeciesToChange = NULL,
    sysActiveForm = NULL,
    BreakUnit = NULL,
    sysApply2AllPlots = FALSE,
    SuErr = NULL,
    MyQuartXl = NULL,
    tmpFuncResults = NULL
  )
}

is_valid_project_prefix <- function(prefix) {
  is.character(prefix) &&
    length(prefix) == 1L &&
    !is.na(prefix) &&
    grepl("^[A-Za-z][A-Za-z0-9_]*$", prefix)
}

#' Set Current Project
#' Updates state and loads relevant metadata
#' @param state The global reactiveValues object
#' @param project_id The ProjectID to switch to
#' @param con Database connection
set_project <- function(state, project_id, con) {
  shiny::req(project_id)

  config("Current", "CurrProject", project_id)
  
  # Update State
  state$CurrProject <- project_id
  state$sysCurrProject <- project_id
  state$CurrProjectName <- project_id

  project_metadata_id <- tryCatch(db_id("Metadata", project_id, prj = TRUE), error = function(e) NULL)
  
  meta <- tryCatch(DBI::dbReadTable(con, project_metadata_id, check.names = FALSE), error = function(e) data.frame())
  if (nrow(meta) > 0) {
    project_col <- names(meta)[match("projectid", tolower(names(meta)), nomatch = 0L)]
    if (nzchar(project_col %||% "")) {
      meta <- meta[tolower(as.character(meta[[project_col]] %||% "")) == tolower(project_id), , drop = FALSE]
    }
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
