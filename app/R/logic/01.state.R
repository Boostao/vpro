# Note : Tested caching the config but platform so fast and yaml so tiny that reading
# it every time is not a problem.
config <- function(section = NULL, key = NULL, setting = NULL, conf = "config.yml") {
  config <- yaml::read_yaml(conf, readLines.warn = FALSE)
  if (length(c(section, key, setting)) >= 3) {
    config[[section]][[key]] <- setting
    yaml::write_yaml(config, conf)
  }
  return(invisible(config))
}

# Initialize state config and return db connection
init_state <- function() {
  
  local({
  
    config("Program", "Name", file.path(getwd(), "app.R"))
  
    if (is.null(config()$System$Location)) {
      config("System", "Location", getwd())
    }
  
    IveBeenMoved <- {config()$System$Location != getwd()}
    if (IveBeenMoved) {
      warning("-- VPro here.\n   Looks like I've been moved.\n   I used to live at {'%s'}.\n   It's a little dark in here, but now it looks like I'm at {'%s'}.\n   I'm going to assume that you moved all my sub-directories when you moved me,\n   but just to be sure, please double-check by looking at Directories in User-setup.\n   Thanks, and have a nice day." |> sprintf(config()$System$Location, getwd()))
    }
  
    if (is.null(config()$System$RLocation) || IveBeenMoved) {
      config("System", "RLocation", file.path(config()$System$Location , "R"))
    }
  
    if (is.null(config()$System$GELocation) || IveBeenMoved) {
      config("System", "GELocation", file.path(config()$System$Location , "GoogleEarth"))
    }
  
    if (is.null(config()$System$PictureDir) || IveBeenMoved) {
      config("System", "PictureDir", file.path(config()$System$Location , "pics"))
    }
  
    if (is.null(config()$System$MetadataLocation) || IveBeenMoved) {
      config("System", "MetadataLocation", file.path(config()$System$Location, "data", "VMetaData.db"))
    }
  
    # Ribbon icon block non applicable

    # Check table hash for changes
    remoteDB <- db_con(file.path(config()$System$Location, "data", "VLists.db"))
    USysAllSpecsVer <- db_hash(remoteDB, "USysAllSpecs")
    USysTableOfListsVer <- db_hash(remoteDB, "USysTableOfLists")
    db_close(remoteDB)
  
    if (!USysAllSpecsVer %in% config()$Current$USysAllSpecsVer) {
      config("Current", "USysAllSpecsVer", USysAllSpecsVer)
    }
    if (!USysTableOfListsVer %in% config()$Current$USysTableOfListsVer) {
      config("Current", "USysTableOfListsVer", USysTableOfListsVer)
    }
  
    if (config()$System$RunOnce == TRUE) {
      config("Current", "User", Sys.info()[["user"]])
      config("System", "Installed", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      config("System", "RunOnce", FALSE)
    } else {
      # spCheck (V7mdlServicePack)
      # There is logic to check if an update is available
      # and inform the user about it.
      # No actual update is performed.
      # I'd rather have that under the Help menu <Check for updates> than have it run every time the app starts.
    }
  
    # Log entry into audit table
    currentDB <- db_con(file.path(config()$System$Location, "data", "VPro64.db"))

    # CompareRegToCurrent can be skipped entirely since the project ATTACH is done on the fly
    # Toolbars can be ignored
    # Attach all relevant dbs
    to_attach <- c(db_path(config()$System$Location, "projects", db = c(
      config()$Current$CurrProject, # Env, Humus, Audit, Mineral, Veg, Other, Metadata, Admin
      config()$Current$CurrHerbarium, # Herbarium
      config()$Current$CurrHierarchy, # Hierarchy
      config()$Current$CurrLump, # Lump
      config()$Current$CurrPlotList, # SU
      config()$Current$CurrPlotListBak, # SU (backup)
      config()$Current$CurrVegProfile, # Profile
      config()$Current$cmbThemeTable # Theme
    )),
    db_path(config()$System$Location, db = c("VUser", "VLists", "VMetaData", "VMessageBoard", file.path("pics", "VPics" ))))

    db_attach(currentDB, to_attach)

    # Rename fields fix
    db_rename_fix01(currentDB)

    # Check for other users in audit table
    MultiUsers <- db_query(currentDB, "
      SELECT DISTINCT User
      FROM USysUserLog
      WHERE OutTime IS NULL AND User != ?
      ORDER BY User, InTime;
    ", Sys.info()[["user"]])
    if (nrow(MultiUsers) > 0) {
      warning(
        "You may not be alone.\nThe following users are currently connected: [",
        paste0(
          apply(MultiUsers, 1, function(row) sprintf("%s", row["User"])),
          collapse = ", "
        ),
        "]"
      )
    }

    # Log entry into user log table
    db_insert(currentDB, "USysUserLog", User = Sys.info()[["user"]], InTime = Sys.time(), OutTime = NA, LocalMachine = Sys.info()[["nodename"]])

    # Insert Audit trace in project
    db_insert(currentDB, "Audit", db = config()$Current$CurrProject, prj = TRUE,
      Project = config()$Current$CurrProject,
      User = config()$Current$User,
      Table = "On",
      EditWhen = Sys.time()
    )

    return(currentDB)
  
  })

}

    # # Message Board (Deprecate?)
    # # db_run(currentDB, "
    # #  INSERT INTO VPro64.tblMessageList ( MessageID )
    # #    (
    # #      SELECT mb.ID
    # #      FROM VMessageBoard.tblMessageBoard mb
    # #      LEFT JOIN VPro64.tblMessageList ml
    # #        ON mb.ID = ml.MessageID
    # #      WHERE ml.MessageID IS NULL
    # #    )"
    # # )

    # # IsNewMessage <- db_query(currentDB, "
    # #   SELECT COUNT(1) AS IsNewMessage
    # #   FROM VMessageBoard.tblMessageBoard mb
    # #   INNER JOIN VPro64.tblMessageList ml
    # #     ON mb.ID = ml.MessageID
    # #   WHERE NOT ml.Read"
    # # )

    # # if (IsNewMessage[[1]]) {
    # #   # Open message board modal (Deprecate?)
    # #   # Reimplement if needed
    # # }

    # WasUnread <- db_query(currentDB, "
    #   SELECT COUNT(1) AS WasUnread
    #   FROM VPro64.tblWhatsNew wn
    #   WHERE NOT wn.Viewed
    # ")

    # if (config()$Message$ShowWhatsNew && WasUnread[[1]] > 0) {
    #   # Open What's new modal
    # }
