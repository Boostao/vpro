# Coordinate conversion ----------------------------------------------------

vpro_coordinate_vector <- function(value, argument) {
  if (!is.numeric(value) || length(value) == 0L) {
    stop("`", argument, "` must be a nonempty numeric vector.", call. = FALSE)
  }
  if (any(!is.finite(value) & !is.na(value))) {
    stop("`", argument, "` must contain only finite values or NA.", call. = FALSE)
  }
  as.numeric(value)
}

vpro_coordinate_recycle <- function(values) {
  sizes <- vapply(values, length, integer(1))
  size <- max(sizes)
  incompatible <- sizes != 1L & sizes != size
  if (any(incompatible)) {
    stop(
      "Coordinate components must have a common length or length one.",
      call. = FALSE
    )
  }
  lapply(values, rep_len, length.out = size)
}

#' Compose decimal degrees from coordinate components
#'
#' Reproduces `V7mdlCoordTools.ConvertLongLatToDeg`. Missing minute and second
#' components are treated as zero. The sign is applied only to `degrees`, as
#' in the Access calculation; callers with signed DMS coordinates should
#' therefore apply their intended hemisphere convention before calling.
#'
#' @param degrees Numeric degrees. `NA` produces an `NA` result.
#' @param minutes Numeric minutes. `NA` is treated as zero.
#' @param seconds Numeric seconds. `NA` is treated as zero.
#'
#' @return A numeric vector of decimal-degree values.
#' @export
vpro_coordinate_decimal <- function(degrees, minutes = 0, seconds = 0) {
  values <- vpro_coordinate_recycle(list(
    degrees = vpro_coordinate_vector(degrees, "degrees"),
    minutes = vpro_coordinate_vector(minutes, "minutes"),
    seconds = vpro_coordinate_vector(seconds, "seconds")
  ))
  values$minutes[is.na(values$minutes)] <- 0
  values$seconds[is.na(values$seconds)] <- 0
  values$degrees + (values$minutes + values$seconds / 60) / 60
}

#' Decompose decimal degrees into degrees, minutes, and seconds
#'
#' Reproduces the common behavior of `V7mdlCoordTools.GetLongDMS` and
#' `GetLatDMS`. Access removes the input sign before decomposition, so all
#' returned components are nonnegative. R doubles are retained rather than
#' narrowing intermediate values to VBA `Single` precision.
#'
#' @param value A numeric vector of decimal-degree values. `NA` values produce
#'   rows of missing components.
#'
#' @return A data frame with numeric `degrees`, `minutes`, and `seconds`
#'   columns.
#' @export
vpro_coordinate_dms <- function(value) {
  value <- abs(vpro_coordinate_vector(value, "value"))
  degrees <- trunc(value)
  decimal_minutes <- (value - degrees) * 60
  minutes <- trunc(decimal_minutes)
  seconds <- (decimal_minutes - minutes) * 60
  data.frame(degrees, minutes, seconds)
}

#' Decompose decimal degrees into degrees and decimal minutes
#'
#' Reproduces the common behavior of `V7mdlCoordTools.GetLongDM` and
#' `GetLatDM`. Access removes the input sign before decomposition, so both
#' returned components are nonnegative. R doubles are retained rather than
#' narrowing intermediate values to VBA `Single` precision.
#'
#' @inheritParams vpro_coordinate_dms
#'
#' @return A data frame with numeric `degrees` and `minutes` columns.
#' @export
vpro_coordinate_dm <- function(value) {
  value <- abs(vpro_coordinate_vector(value, "value"))
  degrees <- trunc(value)
  minutes <- (value - degrees) * 60
  data.frame(degrees, minutes)
}
