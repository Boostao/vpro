splash <- function() {
  
  local({
  
    config_file <- "config.yml"
    NeverRanBefore <- !file.exists(config_file)
    active <- Sys.getenv("R_CONFIG_ACTIVE", "default")
  
    config <- if (file.exists(config_file)) yaml::read_yaml(config_file) else list()
  
    config[[active]]$Program$Name <- file.path(getwd(), "app.R")
  
    if (is.null(config[[active]]$System$Location)) {
      config[[active]]$System$Location <- getwd()
    }
  
    IveBeenMoved <- {config[[active]]$System$Location != getwd()}
    if (IveBeenMoved) {
      warning("-- VPro here.\n   Looks like I've been moved.\n   I used to live at {'%s'}.\n   It's a little dark in here, but now it looks like I'm at {'%s'}.\n   I'm going to assume that you moved all my sub-directories when you moved me,\n   but just to be sure, please double-check by looking at Directories in User-setup.\n   Thanks, and have a nice day." |> sprintf(config[[active]]$System$Location, getwd()))
    }
  
    if (is.null(config[[active]]$System$RLocation) || IveBeenMoved) {
      config[[active]]$System$RLocation <- file.path(getwd(), "R")
    }
  
    if (is.null(config[[active]]$System$GELocation) || IveBeenMoved) {
      config[[active]]$System$GELocation <- file.path(getwd(), "GoogleEarth")
    }
  
    if (is.null(config[[active]]$System$PictureDir) || IveBeenMoved) {
      config[[active]]$System$PictureDir <- file.path(getwd(), "pics")
    }
  
    if (is.null(config[[active]]$System$MetadataLocation) || IveBeenMoved) {
      config[[active]]$System$MetadataLocation <- file.path(getwd(), "data", "VMetaData.db")
    }
  
    # Ribbon icon block non applicable
  
    table_hash <- function(con, table_name) {
      table_name <- DBI::Id(strsplit(table_name, "\\.")[[1]])
      query <- sprintf(
        "SELECT bit_xor(hash(*columns(*)))::VARCHAR AS table_hash FROM %s;",
        DBI::dbQuoteIdentifier(con, table_name)
      )
      result <- DBI::dbGetQuery(con, query)
      result$table_hash
    }
  
    remoteDB <- DBI::dbConnect(duckdb::duckdb(), file.path(config[[active]]$System$Location, "data", "VLists.db"))
    USysAllSpecsVer <- table_hash(remoteDB, "USysAllSpecs")
    USysTableOfListsVer <- table_hash(remoteDB, "USysTableOfLists")
    DBI::dbDisconnect(remoteDB, shutdown = TRUE)
    rm(remoteDB)
  
    if (!USysAllSpecsVer %in% config[[active]]$Current$USysAllSpecsVer) {
      config[[active]]$Current$USysAllSpecsVer <- USysAllSpecsVer
    }
    if (!USysTableOfListsVer %in% config[[active]]$Current$USysTableOfListsVer) {
      config[[active]]$Current$USysTableOfListsVer <- USysTableOfListsVer
    }
  
    if (NeverRanBefore) {
      config[[active]]$Current$User <- Sys.info()[["user"]]
      config[[active]]$Current$CurrProject <- "Sample"
      config[[active]]$Current$CurrPlotList <- "None"
      config[[active]]$Current$CurrHierarchy <- "Sample"
      config[[active]]$Current$DataFormName <- "FS882-6x4"
      config[[active]]$System$Version <- 3
      config[[active]]$System$Build <- format(as.Date("2023/02/23"), "%A, %B %d, %Y")
      config[[active]]$System$Installed <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      config[[active]]$ReportOptions$cmbColourGreater <- 5
      config[[active]]$ReportOptions$cmbGrayGreater <- 65
      config[[active]]$ReportOptions$cmbApplyTheme <- 1
      config[[active]]$Audit$AuditStrength <- 1
      config[[active]]$ReportOptions$cmbThemeTable <- "Sample"
    } else {
      # spCheck (V7mdlServicePack)
      # There is logic to check if an update is available
      # and inform the user about it.
      # No actual update is performed.
      # I'd rather have that under the Help menu <Check for updates> than have it run every time the app starts.
    }
  
    # Log entry into audit table
    remoteDB <- DBI::dbConnect(duckdb::duckdb(), file.path(config[[active]]$System$Location, "data", "VPro64.db"))
    DBI::dbAppendTable(remoteDB, "USysUserLog", data.frame(
      User = Sys.info()[["user"]],
      InTime = Sys.time(),
      OutTime = NA,
      LocalMachine = Sys.info()[["nodename"]]
    ))
    MultiUsers <- DBI::dbGetQuery(
      remoteDB,
      "SELECT DISTINCT User FROM USysUserLog WHERE User != ? ORDER BY User, InTime;", Sys.info()[["user"]]
    )
    if (nrow(MultiUsers) > 0) {
      warning(
        "-- You may not be alone.\n   The following users are currently connected: ",
        paste0(
          apply(MultiUsers, 1, function(row) sprintf("%s", row["User"])),
          collapse = ", "
        )
      )
    }
    DBI::dbDisconnect(remoteDB, shutdown = TRUE)
    rm(remoteDB)
    
  
  }

}
