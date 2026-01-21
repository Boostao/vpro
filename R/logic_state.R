# Logic: Global State Management
# Replicates V7mdlGlobalDeclarations

# We use a list-based approach or R6, but for Shiny, passing a reactiveValues object 
# named `state` is the standard pattern. This file defines helper functions to mutators.

#' Initialize System State
#' @return A reactiveValues object with default fields
init_sys_state <- function() {
  reactiveValues(
    # Core Context
    CurrProject = NULL,      # Current Project ID (String)
    CurrSU = NULL,           # Current Plot/SiteUnit (String)
    CurrHierarchy = NULL,    # Classification Hierarchy Context
    
    # Settings
    LumpingTable = NULL,     # Active Lumping Table ID
    User = Sys.getenv("USER", "Unknown"),
    
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
  req(project_id)
  
  # Update State
  state$CurrProject <- project_id
  
  # Load Metadata
  # VPro: USysProjectMetadata
  meta <- dbGetQuery(con, sprintf("SELECT * FROM Sample_Metadata WHERE ProjectID = '%s'", project_id))
  
  if (nrow(meta) > 0) {
    state$ProjectMetadata <- as.list(meta[1, ])
  } else {
    state$ProjectMetadata <- list()
    warning(paste("No metadata found for project:", project_id))
  }
  
  # Reset dependent context
  state$CurrSU <- NULL
  
  # VPro Logic: Load default Lumping/Sort options if they exist in metadata
  # (Placeholder for expanding logic based on USysProjectMetadata columns)
}

#' Set Current Site Unit (Plot)
#' @param state The global reactiveValues object
#' @param plot_number The PlotNumber (String uniqueness across projects depends on VPro logic, typically unique)
set_su <- function(state, plot_number) {
    state$CurrSU <- plot_number
}
