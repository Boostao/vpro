#' Classify a species across ordered site-unit codes
#'
#' Translates only the per-species calculation in
#' `V7mdlDiagnostic.Diagnostic`. `V7mdlReportsShortVeg.CreateDiagnostic` builds
#' the `MyRS5` crosstab: each unit's code joins
#' `V7mdlDiagnostic.DiagnosticPresenceClass` (1–5) and
#' `V7mdlValueConversions.SignifClass` (`+` or 1–9) with `" - "`.
#' The first unit attaining the highest presence is selected. Access uses
#' `Val()` on the first and last characters, so `+` counts as zero. With
#' valid presence classes 1–5, the `ic` branch cannot be reached because its
#' other conditions require a unique near-maximum presence of 2. Unlike
#' Access, malformed codes and missing unit names fail explicitly. The
#' function does not build `MyRS5`, filter site units, or write reports.
#'
#' @param unit_codes A named character vector in crosstab field order. Each
#'   nonmissing element must have the form `"1 - +"` through `"5 - 9"`;
#'   `NA` denotes a missing unit cell. Names must be distinct, nonempty unit
#'   identifiers.
#'
#' @return A list with `unit` and `diagnosis` (comma-separated codes in Access
#'   order `d`, `dd`, `cd`, `c`, `ic`). Both are `NA_character_` if no diagnosis
#'   would be written.
#' @export
vpro_diagnostic_classify <- function(unit_codes) {
  units <- names(unit_codes)
  if (!is.character(unit_codes) || length(unit_codes) == 0L || is.null(units) || anyNA(units) || any(!nzchar(units)) || anyDuplicated(units)) {
    stop("`unit_codes` must be a nonempty named character vector with distinct, nonempty unit names.", call. = FALSE)
  }
  present <- !is.na(unit_codes)
  if (any(!grepl("^[1-5] - (\\+|[1-9])$", unit_codes[present]))) {
    stop("Nonmissing `unit_codes` must have the form '1 - +' through '5 - 9'.", call. = FALSE)
  }
  if (!any(present)) {
    return(list(unit = NA_character_, diagnosis = NA_character_))
  }

  presence <- as.integer(substr(unit_codes[present], 1L, 1L))
  significance_code <- substring(unit_codes[present], 5L)
  significance <- integer(length(significance_code))
  numeric_significance <- significance_code != "+"
  significance[numeric_significance] <- as.integer(significance_code[numeric_significance])
  maximum <- max(presence)
  selected <- which(presence == maximum)[1L]
  selected_significance <- significance[selected]
  count_presence <- sum(presence > maximum - 2L)
  count_five <- sum(presence == 5L)
  count_significance <- sum(significance > selected_significance - 2L)

  differential <- count_presence == 1L && maximum >= 3L
  dominant_differential <- count_significance == 1L &&
    !differential &&
    selected_significance >= 5L
  constant_dominant <- maximum == 5L && count_presence == 1L && selected_significance >= 5L
  constant <- maximum == 5L && count_five == 1L && selected_significance < 5L
  important_companion <- !differential && !dominant_differential && !constant_dominant && !constant && maximum >= 2L && count_presence == 1L

  codes <- c("d", "dd", "cd", "c", "ic")
  chosen <- c(
    differential,
    dominant_differential,
    constant_dominant,
    constant,
    important_companion
  )
  if (!any(chosen)) {
    return(list(unit = NA_character_, diagnosis = NA_character_))
  }
  list(unit = units[present][selected], diagnosis = paste(codes[chosen], collapse = ", "))
}
