# Terrain-code transformations -----------------------------------------------

#' Combine terrain-code components
#'
#' Translates `V7mdlTerrain.CombineTerrain`: joins three components without a
#' separator, ignoring missing components. An empty result is missing, including
#' when all three components are missing. The unused Access `NullSwitch` has no
#' effect. Unlike the VBA error handler, unsupported inputs fail explicitly.
#'
#' @param field1,field2,field3 Character vectors of terrain-code components.
#'   Each must have length one or the common output length; three empty vectors
#'   produce an empty result.
#' @return A character vector of combined codes, with `NA` for empty results.
#' @export
vpro_terrain_combine <- function(field1, field2, field3) {
  parts <- list(field1, field2, field3)
  if (any(!vapply(parts, is.character, logical(1)))) {
    stop("Terrain components must be character vectors.", call. = FALSE)
  }
  sizes <- lengths(parts)
  if (all(sizes == 0L)) {
    return(character())
  }
  size <- max(sizes)
  if (any(!sizes %in% c(1L, size))) {
    stop("Terrain components must have length one or a common length.", call. = FALSE)
  }
  parts <- lapply(parts, function(x) rep_len(replace(x, is.na(x), ""), size))
  result <- paste0(parts[[1L]], parts[[2L]], parts[[3L]])
  result[result == ""] <- NA_character_
  result
}

#' Extract a terrain-code component
#'
#' Translates `V7mdlTerrain.SplitTerrain` (used by `V7mdlExportVenus`).
#' All terrain fields return a one-character component, except the two
#' surficial-material fields: the first occurrence of `FG` is treated as one
#' component, so subsequent positions skip its second character. Positions
#' past the end return `""`, as with Access `Mid`. Missing values also return
#' `""`. Field names and positions are validated explicitly rather than
#' relying on the VBA error handler.
#'
#' @param value Character vector of combined terrain codes.
#' @param field One of `TerrainTextureSurf`, `TerrainTextureSubSurf`,
#'   `SurficialMaterialSurf`, `SurficialMaterialSubSurf`, `SurfaceExpSurf`,
#'   `SurfaceExpSubSurf`, `GeoMorProSurf`, or `GeoMorProSubSurf`.
#' @param position One-based component position (a positive whole number).
#' @return A character vector with one component per input value.
#' @export
vpro_terrain_split <- function(value, field, position) {
  fields <- c(
    "TerrainTextureSurf",
    "TerrainTextureSubSurf",
    "SurficialMaterialSurf",
    "SurficialMaterialSubSurf",
    "SurfaceExpSurf",
    "SurfaceExpSubSurf",
    "GeoMorProSurf",
    "GeoMorProSubSurf"
  )
  if (!is.character(value)) {
    stop("`value` must be a character vector.", call. = FALSE)
  }
  if (!is.character(field) || length(field) != 1L || is.na(field) || !field %in% fields) {
    stop("`field` must name a supported terrain field.", call. = FALSE)
  }
  if (!is.numeric(position) || length(position) != 1L || is.na(position) || !is.finite(position) || position < 1 || position > 32767 || position != trunc(position)) {
    stop("`position` must be a positive whole number within the Access Integer range.", call. = FALSE)
  }
  result <- rep("", length(value))
  present <- which(!is.na(value))
  if (!length(present)) {
    return(result)
  }
  index <- rep(as.integer(position), length(present))
  width <- rep(1L, length(present))
  if (field %in% c("SurficialMaterialSurf", "SurficialMaterialSubSurf")) {
    fg <- as.integer(regexpr("FG", value[present], fixed = TRUE))
    width[fg == position] <- 2L
    index[fg > 0L & fg < position] <- index[fg > 0L & fg < position] + 1L
  }
  result[present] <- substring(value[present], index, index + width - 1L)
  result
}
