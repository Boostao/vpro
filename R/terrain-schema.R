# Terrain schema inspection --------------------------------------------------

#' Inspect terrain field declarations without modifying a project
#'
#' Compares eight Env terrain fields with the field widths targeted by
#' `V7mdlTerrain.SetTerrainFieldSize`: 3 characters except 6 for surficial
#' material. Unlike `TestTerrainFieldSize`, checks every field, including
#' `Sample`, and reports missing tables and fields. SQLite declarations without
#' a numeric size are reported as `unknown`, not treated as compliant: the
#' canonical VP08 SQLite translation uses unbounded `VARCHAR` and loses Access
#' field-size metadata. SQLite type lengths are declarations, not enforced limits.
#'
#' @param path Existing SQLite database path.
#' @param project Project prefix containing the Env table.
#' @return A data frame with `field`, `expected_size`, `declared_type`,
#'   `actual_size`, and `status` (`match`, `undersized`, `oversized`,
#'   `unknown`, `non_text`, `missing_field`, or `missing_table`).
#' @export
vpro_terrain_inspect_schema <- function(path, project) {
  project <- vpro_project_name(project)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path) || dir.exists(path)) {
    stop("VPRO project database does not exist: ", path, call. = FALSE)
  }
  fields <- c(
    "TerrainTextureSurf",
    "SurficialMaterialSurf",
    "SurfaceExpSurf",
    "GeoMorProSurf",
    "TerrainTextureSubSurf",
    "SurficialMaterialSubSurf",
    "SurfaceExpSubSurf",
    "GeoMorProSubSurf"
  )
  expected_size <- ifelse(grepl("^SurficialMaterial", fields), 6L, 3L)
  con <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  table <- vpro_project_table(project, "Env")
  result <- data.frame(
    field = fields,
    expected_size = expected_size,
    declared_type = rep(NA_character_, length(fields)),
    actual_size = rep(NA_integer_, length(fields)),
    status = rep("missing_table", length(fields)),
    stringsAsFactors = FALSE
  )
  if (!DBI::dbExistsTable(con, table)) {
    return(result)
  }
  result$status[] <- "missing_field"
  info <- vpro_schema_table(con, table)
  index <- match(tolower(fields), info$key)
  present <- which(!is.na(index))
  if (!length(present)) {
    return(result)
  }
  result$declared_type[present] <- info$type[index[present]]
  result$actual_size[present] <- info$size[index[present]]
  text_type <- result$declared_type[present] %in% c("TEXT", "VARCHAR", "CLOB")
  result$status[present[!text_type]] <- "non_text"
  text_rows <- present[text_type]
  result$status[text_rows] <- "unknown"
  sized <- text_rows[!is.na(result$actual_size[text_rows])]
  result$status[sized] <- ifelse(
    result$actual_size[sized] < result$expected_size[sized],
    "undersized",
    ifelse(result$actual_size[sized] > result$expected_size[sized], "oversized", "match")
  )
  result
}
