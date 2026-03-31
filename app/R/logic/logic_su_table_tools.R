# SU Table Tools
# Port of Access V7mdlSUTableTools1: InsertEnvSuIntoSu, InsertSuIntoEnv, GetFilteredFormRecords

#' Copy UserSiteUnit from Env into SU table (Access: InsertEnvSuIntoSu)
#' @param con DuckDB connection
#' @return list(ok, message, new_units) — new_units is data.frame of units not in master list
su_env_into_su <- function(con) {
  project <- config("Current", "CurrProject")
  plotlist <- config("Current", "CurrPlotlist")
  if (is.null(plotlist) || plotlist == "None") {
    return(list(ok = FALSE, message = "You must have a current site unit table."))
  }

  env_tbl <- as.character(db_tb(con, "Env", project, prj = TRUE))
  su_tbl <- as.character(db_tb(con, "SU", plotlist, prj = TRUE))

  # Step 1: UPDATE SU.SiteUnit = Env.UserSiteUnit for matching plots
  sql <- paste0(
    "UPDATE ", su_tbl, " SET SiteUnit = e.UserSiteUnit ",
    "FROM ", env_tbl, " e ",
    "WHERE ", su_tbl, ".PlotNumber = e.PlotNumber ",
    "AND e.UserSiteUnit IS NOT NULL"
  )
  tryCatch(db_run(con, sql), error = function(e) {
    return(list(ok = FALSE, message = paste("Update failed:", conditionMessage(e))))
  })

  # Step 2: Find units in Env not in MasterSiteUnitList
  new_units <- tryCatch(
    db_query(con, paste0(
      "SELECT DISTINCT e.UserSiteUnit, e.SiteUnitLongName ",
      "FROM ", env_tbl, " e ",
      "LEFT JOIN VLists.MasterSiteUnitList m ON e.UserSiteUnit = m.SiteSeries ",
      "WHERE e.UserSiteUnit IS NOT NULL AND m.SiteSeries IS NULL"
    )),
    error = function(e) data.frame()
  )

  n_updated <- tryCatch(
    nrow(db_query(con, paste0(
      "SELECT s.PlotNumber FROM ", su_tbl, " s ",
      "INNER JOIN ", env_tbl, " e ON s.PlotNumber = e.PlotNumber ",
      "WHERE e.UserSiteUnit IS NOT NULL"
    ))),
    error = function(e) 0
  )

  list(ok = TRUE,
    message = paste0(n_updated, " SU records updated from Env."),
    new_units = new_units
  )
}

#' Add missing units to USysUserSiteUnitList
#' @param con DuckDB connection
#' @param units data.frame with UserSiteUnit and SiteUnitLongName columns
su_add_user_units <- function(con, units) {
  if (!nrow(units)) return(invisible(NULL))
  for (i in seq_len(nrow(units))) {
    tryCatch(
      db_run(con, paste0(
        "INSERT INTO VUser.USysUserSiteUnitList (SiteSeries, SiteSeriesLongName) ",
        "SELECT ?, ? WHERE NOT EXISTS (",
        "  SELECT 1 FROM VUser.USysUserSiteUnitList WHERE SiteSeries = ?",
        ")"
      ), params = list(units$UserSiteUnit[i], units$SiteUnitLongName[i], units$UserSiteUnit[i])),
      error = function(e) NULL
    )
  }
}

#' Copy SiteUnit from SU table into Env UserSiteUnit (Access: InsertSuIntoEnv)
#' @param con DuckDB connection
#' @return list(ok, message)
su_su_into_env <- function(con) {
  project <- config("Current", "CurrProject")
  plotlist <- config("Current", "CurrPlotlist")
  if (is.null(plotlist) || plotlist == "None") {
    return(list(ok = FALSE, message = "You must have a current site unit table."))
  }

  env_tbl <- as.character(db_tb(con, "Env", project, prj = TRUE))
  su_tbl <- as.character(db_tb(con, "SU", plotlist, prj = TRUE))

  # Step 1: Copy SiteUnit from SU to Env.UserSiteUnit
  sql1 <- paste0(
    "UPDATE ", env_tbl, " SET UserSiteUnit = s.SiteUnit ",
    "FROM ", su_tbl, " s ",
    "WHERE ", env_tbl, ".PlotNumber = s.PlotNumber"
  )
  tryCatch(db_run(con, sql1), error = function(e) {
    return(list(ok = FALSE, message = paste("Step 1 failed:", conditionMessage(e))))
  })

  # Step 2: Enrich with Master SiteUnit metadata
  sql2 <- paste0(
    "UPDATE ", env_tbl, " SET ",
    "SiteUnitShortName = m.SiteSeries, ",
    "SiteUnitLongName = m.SiteSeriesLongName ",
    "FROM VLists.MasterSiteUnitList m ",
    "WHERE ", env_tbl, ".UserSiteUnit = m.SiteSeries"
  )
  tryCatch(db_run(con, sql2), error = function(e) NULL)

  # Step 3: Enrich with User SiteUnit metadata (fallback)
  sql3 <- paste0(
    "UPDATE ", env_tbl, " SET ",
    "SiteUnitShortName = u.SiteSeries, ",
    "SiteUnitLongName = u.SiteSeriesLongName ",
    "FROM VUser.USysUserSiteUnitList u ",
    "WHERE ", env_tbl, ".UserSiteUnit = u.SiteSeries ",
    "AND (", env_tbl, ".SiteUnitShortName IS NULL ",
    " OR ", env_tbl, ".SiteUnitShortName = '')"
  )
  tryCatch(db_run(con, sql3), error = function(e) NULL)

  list(ok = TRUE, message = "SU assignments copied into Env. Done.")
}

#' Create or modify SU table from a set of filtered plot numbers
#' @param con DuckDB connection
#' @param plot_numbers Character vector of plot IDs
#' @param action Character: "create", "modify", or "append"
#' @param new_name Character: name for new SU table (only for action "create")
#' @return list(ok, message)
su_create_from_filter <- function(con, plot_numbers, action = "create", new_name = NULL) {
  project <- config("Current", "CurrProject")
  plotlist <- config("Current", "CurrPlotlist")

  if (action == "create") {
    if (is.null(new_name) || !nzchar(trimws(new_name))) {
      return(list(ok = FALSE, message = "SU table name is required for create."))
    }
    su_tbl <- as.character(db_tb(con, "SU", new_name, prj = TRUE))
    # Create the SU table if it doesn't exist
    tryCatch(
      db_run(con, paste0(
        "CREATE TABLE IF NOT EXISTS ", su_tbl,
        " (PlotNumber TEXT PRIMARY KEY, SiteUnit TEXT, SiteUnitLongName TEXT)"
      )),
      error = function(e) {
        return(list(ok = FALSE, message = paste("Create table failed:", conditionMessage(e))))
      }
    )
    # Insert filtered plots
    n <- 0
    for (pn in plot_numbers) {
      tryCatch({
        db_run(con, paste0(
          "INSERT INTO ", su_tbl, " (PlotNumber) VALUES (?) ",
          "ON CONFLICT (PlotNumber) DO NOTHING"
        ), params = list(pn))
        n <- n + 1
      }, error = function(e) NULL)
    }
    return(list(ok = TRUE, message = paste0(n, " records added to new SU table '", new_name, "'.")))
  }

  if (action == "modify") {
    if (is.null(plotlist) || plotlist == "None") {
      return(list(ok = FALSE, message = "You must have a current SU table to modify it."))
    }
    su_tbl <- as.character(db_tb(con, "SU", plotlist, prj = TRUE))

    # Remove plots not in filtered set
    existing <- tryCatch(
      db_query(con, paste0("SELECT PlotNumber FROM ", su_tbl)),
      error = function(e) data.frame(PlotNumber = character(0))
    )
    to_remove <- setdiff(existing$PlotNumber, plot_numbers)
    for (pn in to_remove) {
      tryCatch(db_run(con, paste0("DELETE FROM ", su_tbl, " WHERE PlotNumber = ?"),
        params = list(pn)), error = function(e) NULL)
    }

    # Add plots not already in SU table
    to_add <- setdiff(plot_numbers, existing$PlotNumber)
    for (pn in to_add) {
      tryCatch(db_run(con, paste0("INSERT INTO ", su_tbl, " (PlotNumber) VALUES (?)"),
        params = list(pn)), error = function(e) NULL)
    }

    return(list(ok = TRUE,
      message = paste0("SU table modified: ", length(to_add), " added, ",
                       length(to_remove), " removed.")))
  }

  if (action == "append") {
    if (is.null(plotlist) || plotlist == "None") {
      return(list(ok = FALSE, message = "You must have a current SU table to append to it."))
    }
    su_tbl <- as.character(db_tb(con, "SU", plotlist, prj = TRUE))
    n <- 0
    for (pn in plot_numbers) {
      tryCatch({
        db_run(con, paste0(
          "INSERT INTO ", su_tbl, " (PlotNumber) VALUES (?) ",
          "ON CONFLICT (PlotNumber) DO NOTHING"
        ), params = list(pn))
        n <- n + 1
      }, error = function(e) NULL)
    }
    return(list(ok = TRUE, message = paste0(n, " records appended to SU table.")))
  }

  list(ok = FALSE, message = paste("Unknown action:", action))
}
