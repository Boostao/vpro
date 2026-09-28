# Startup reference views ----------------------------------------------------

vpro_startup_reference_relation <- function(con, database, table) {
  paste(
    DBI::dbQuoteIdentifier(con, database),
    DBI::dbQuoteIdentifier(con, table),
    sep = "."
  )
}

vpro_startup_reference_view <- function(con, name, sql) {
  DBI::dbExecute(
    con,
    paste("CREATE OR REPLACE TEMP VIEW", DBI::dbQuoteIdentifier(con, name), "AS", sql)
  )
}

#' Create connection-local startup reference views
#'
#' Creates the temporary equivalents of the support-table links made by
#' `V7mdlSplash.AttachSupportTables`, plus the two saved union queries
#' `MasterSiteUnitList` and `MasterUnitList_Hierarchy`.  The views belong only
#' to `context$con`; no SQLite reference database is modified.
#'
#' The canonical `USysAllSpecs` has both `EnglishName` and
#' `CombinedEnglishName`.  If an older schema instead has `JustEnglishName`, a
#' read-only diagnostic is returned; if either canonical field is missing,
#' startup stops with a repair instruction. This function never performs the
#' legacy rename-recovery mutation.
#'
#' @param context A VPRO project context whose coordinator has `VLists` and
#'   `VUser` attached.
#'
#' @return A data frame of schema diagnostics with `Code` and `Message`.
#' @export
vpro_startup_reference_views <- function(context) {
  vpro_project_assert_context(context)
  con <- context$con
  attached <- vpro_db_list(con)
  required <- c("VLists", "VUser")
  missing <- setdiff(required, attached)
  if (length(missing) > 0L) {
    stop("Startup reference databases are not attached: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  fields <- DBI::dbListFields(con, DBI::Id(schema = "VLists", table = "USysAllSpecs"))
  if (!all(c("EnglishName", "CombinedEnglishName") %in% fields)) {
    stop("VLists.USysAllSpecs must use the canonical EnglishName and CombinedEnglishName fields; ", "repair a legacy renamed copy explicitly before launch.", call. = FALSE)
  }
  diagnostics <- if ("JustEnglishName" %in% fields) {
    data.frame(
      Code = "legacy_just_english_name",
      Message = "VLists.USysAllSpecs contains JustEnglishName; startup left the reference schema unchanged.",
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(Code = character(), Message = character(), stringsAsFactors = FALSE)
  }

  master <- vpro_startup_reference_relation(con, "VLists", "MasterSiteUnitList")
  user <- vpro_startup_reference_relation(con, "VUser", "UserSiteUnitList")
  vpro_startup_reference_view(con, "USysMasterSiteUnitList", paste("SELECT * FROM", master))
  vpro_startup_reference_view(con, "USysUserSiteUnitList", paste("SELECT * FROM", user))
  union_sql <- paste("SELECT * FROM USysMasterSiteUnitList UNION DISTINCT SELECT * FROM USysUserSiteUnitList")
  vpro_startup_reference_view(con, "MasterSiteUnitList", union_sql)
  vpro_startup_reference_view(con, "MasterUnitList_Hierarchy", union_sql)
  diagnostics
}

#' Read VPRO reference-list descriptions
#'
#' Reads the canonical SQLite translation of Access table `Description`
#' properties for `USysAllSpecs` and `USysTableOfLists`.  Missing or empty
#' descriptions are reported as `"Unknown"`; this read-only operation does not
#' use table hashes.
#'
#' @param context A VPRO project context whose coordinator has `VLists`
#'   attached.
#'
#' @return A data frame with `Table` and `Description`.
#' @export
vpro_reference_descriptions <- function(context) {
  vpro_project_assert_context(context)
  if (!("VLists" %in% vpro_db_list(context$con))) {
    stop("Startup reference database is not attached: VLists", call. = FALSE)
  }
  metadata <- vpro_startup_reference_relation(context$con, "VLists", "_table_metadata")
  tables <- c("USysAllSpecs", "USysTableOfLists")
  result <- DBI::dbGetQuery(
    context$con,
    paste("SELECT table_name, description FROM", metadata, "WHERE table_name IN (?, ?)"),
    params = as.list(tables)
  )
  description <- result$description[match(tables, result$table_name)]
  description[is.na(description) | !nzchar(description)] <- "Unknown"
  data.frame(Table = tables, Description = unname(description), stringsAsFactors = FALSE)
}
