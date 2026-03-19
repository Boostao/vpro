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

# No table description concept in duckdb, so we hash the entire table to detect changes.
table_hash <- function(con, table_name) {
  table_name <- DBI::Id(strsplit(table_name, "\\.")[[1]])
  query <- sprintf(
    "SELECT bit_xor(hash(*columns(*)))::VARCHAR AS table_hash FROM %s;",
    DBI::dbQuoteIdentifier(con, table_name)
  )
  result <- DBI::dbGetQuery(con, query)
  result$table_hash
}

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
    remoteDB <- DBI::dbConnect(duckdb::duckdb(), file.path(config()$System$Location, "data", "VLists.db"))
    USysAllSpecsVer <- table_hash(remoteDB, "USysAllSpecs")
    USysTableOfListsVer <- table_hash(remoteDB, "USysTableOfLists")
    DBI::dbDisconnect(remoteDB, shutdown = TRUE)
    rm(remoteDB)
  
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
    currentDB <- DBI::dbConnect(duckdb::duckdb(), file.path(config()$System$Location, "data", "VPro64.db"))
    DBI::dbAppendTable(currentDB, "USysUserLog", data.frame(
      User = Sys.info()[["user"]],
      InTime = Sys.time(),
      OutTime = NA,
      LocalMachine = Sys.info()[["nodename"]]
    ))

    # Check for other users in audit table
    MultiUsers <- DBI::dbGetQuery(
      currentDB,
      "SELECT DISTINCT User FROM USysUserLog WHERE OutTime IS NULL AND User != ? ORDER BY User, InTime;", Sys.info()[["user"]]
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

    # CompareRegToCurrent can be skipped entirely since the project ATTACH is done on the fly
    # Toolbars can be ignored
    # Attach all relevant dbs
    to_attach <- c(
      file.path(
        config()$System$Location,
        "data",
        "projects",
        paste0(
          c(
            config()$Current$CurrProject, # Env, Humus, Audit, Mineral, Veg, Other, Metadata, Admin
            config()$Current$CurrHerbarium, # Herbarium
            config()$Current$CurrHierarchy, # Hierarchy
            config()$Current$CurrLump, # Lump
            config()$Current$CurrPlotList, # SU
            config()$Current$CurrPlotListBak, # SU (backup)
            config()$Current$CurrVegProfile, # Profile
            config()$Current$cmbThemeTable # Theme
          ),
          ".db"
        ) |> unique()
      ),
      file.path(
        config()$System$Location,
        "data",
        c(
          "VUser.db",
          "VLists.db",
          "VMetaData.db",
          "VMessageBoard.db",
          file.path("pics", "VPics.db")
        )
      )
    )

    # Check if to_attach files exist before trying to attach them, error handling if they don't exist
    existing_dbs <- to_attach[file.exists(to_attach)]
    missing_dbs <- setdiff(to_attach, existing_dbs)
    if (length(missing_dbs) > 0) {
      stop("-- Missing databases detected.\n   The following databases were expected but not found: ",
        paste0(
          missing_dbs,
          collapse = ", "
        ),
        "\n   Please check that the expected databases are in place and try again."
      )
    }

    # Attach existing databases
    for (db_path in existing_dbs) {
      DBI::dbExecute(currentDB, sprintf("ATTACH %s (TYPE sqlite);",
        DBI::dbQuoteLiteral(
          currentDB,
          db_path
        )
      ))
    }

    # Message Board (Deprecate?)
    # DBI::dbExecute(currentDB, "
    #  INSERT INTO VPro64.tblMessageList ( MessageID )
    #    (
    #      SELECT mb.ID
    #      FROM VMessageBoard.tblMessageBoard mb
    #      LEFT JOIN VPro64.tblMessageList ml
    #        ON mb.ID = ml.MessageID
    #      WHERE ml.MessageID IS NULL
    #    )"
    # )

    # IsNewMessage <- DBI::dbGetQuery(currentDB, "
    #   SELECT COUNT(1) AS IsNewMessage
    #   FROM VMessageBoard.tblMessageBoard mb
    #   INNER JOIN VPro64.tblMessageList ml
    #     ON mb.ID = ml.MessageID
    #   WHERE NOT ml.Read"
    # )

    # if (IsNewMessage[[1]]) {
    #   # Open message board modal (Deprecate?)
    #   # Reimplement if needed
    # }

    # Rename fields, probably need it's own function
    if ("JustEnglishName" %in% DBI::dbListFields(currentDB, DBI::Id("VLists", "USysAllSpecs"))) {
      DBI::dbExecute(currentDB, "
        ALTER TABLE VLists.USysAllSpecs
        RENAME COLUMN EnglishName TO CombinedEnglishName
      ")
      DBI::dbExecute(currentDB, "
        ALTER TABLE VLists.USysAllSpecs
        RENAME COLUMN JustEnglishName TO EnglishName
      ")
    }

    # Insert Audit trace in project
    DBI::dbAppendTable(currentDB, DBI::Id(config()$Current$CurrProject, paste0(config()$Current$CurrProject, "_Audit")), data.frame(
      Project = config()$Current$CurrProject,
      User = config()$Current$User,
      Table = "On",
      EditWhen = Sys.time()
    ))

    WasUnread <- DBI::dbGetQuery(currentDB, "
      SELECT COUNT(1) AS WasUnread
      FROM VPro64.tblWhatsNew wn
      WHERE NOT wn.Viewed
    ")

    if (config()$Message$ShowWhatsNew && WasUnread[[1]] > 0) {
      # Open What's new modal
    }

    return(currentDB)
  
  })

}
