#' Mark missing R-export codes with periods
#'
#' Translates `V7mdlExportToR2.NullToPeriod`, used by `RunR` for Zone,
#' SubZone, and MoistureRegime in the six-column export. Access returns the
#' original non-Null Variant. This API returns character codes and replaces
#' only missing values; empty and whitespace-only codes are not changed.
#' It does not serialize rows or launch R.
#'
#' @param code A nonempty character vector of export codes, possibly missing.
#'
#' @return A character vector with missing codes replaced by `"."`.
#' @export
vpro_export_code <- function(code) {
  if (!is.character(code) || length(code) == 0L) {
    stop("`code` must be a nonempty character vector.", call. = FALSE)
  }
  code[is.na(code)] <- "."
  code
}
