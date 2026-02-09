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
