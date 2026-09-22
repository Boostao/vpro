# Value classification and rounding ----------------------------------------

vpro_value_vector <- function(value, argument) {
  if (!is.numeric(value) || length(value) == 0L) {
    stop("`", argument, "` must be a nonempty numeric vector.", call. = FALSE)
  }
  if (any(!is.finite(value) & !is.na(value))) {
    stop("`", argument, "` must contain only finite values or NA.", call. = FALSE)
  }
  as.numeric(value)
}

vpro_value_recycle <- function(values) {
  sizes <- vapply(values, length, integer(1))
  size <- max(sizes)
  incompatible <- sizes != 1L & sizes != size
  if (any(incompatible)) {
    stop("Inputs must have a common length or length one.", call. = FALSE)
  }
  lapply(values, rep_len, length.out = size)
}

vpro_value_flag <- function(value, argument) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    stop("`", argument, "` must be TRUE or FALSE.", call. = FALSE)
  }
  value
}

#' Convert vegetation presence to a Roman-numeral class
#'
#' Reproduces `V7mdlValueConversions.Presence2Class`. Values outside the
#' Access-supported interval from zero through one return `NA` rather than an
#' unset VBA `Variant`.
#'
#' @param presence Numeric vegetation presence expressed as a proportion.
#'
#' @return A character vector containing classes `"I"` through `"V"` or `NA`.
#' @export
vpro_presence_class <- function(presence) {
  presence <- vpro_value_vector(presence, "presence")
  result <- rep(NA_character_, length(presence))
  valid <- !is.na(presence) & presence >= 0 & presence <= 1
  result[valid] <- c("I", "II", "III", "IV", "V")[
    findInterval(presence[valid], c(0.2, 0.4, 0.6, 0.8), left.open = TRUE) + 1L
  ]
  result
}

#' Convert vegetation presence to a numeric-label class
#'
#' Reproduces `V7mdlValueConversions.Presence2ClassNval`. The labels remain
#' character values, matching Access. Unlike `vpro_presence_class()`, the final
#' class has no upper bound.
#'
#' @inheritParams vpro_presence_class
#'
#' @return A character vector containing labels `"1"` through `"5"` or `NA`.
#' @export
vpro_presence_class_numeric <- function(presence) {
  presence <- vpro_value_vector(presence, "presence")
  result <- rep(NA_character_, length(presence))
  valid <- !is.na(presence) & presence >= 0
  result[valid] <- as.character(
    findInterval(presence[valid], c(0.2, 0.4, 0.6, 0.8), left.open = TRUE) + 1L
  )
  result
}

vpro_score_result <- function(score, breaks, classes, return_score) {
  if (return_score) {
    return(score)
  }
  result <- rep(NA_integer_, length(score))
  valid <- !is.na(score) & score >= 0
  result[valid] <- classes[
    findInterval(score[valid], breaks, left.open = TRUE) + 1L
  ]
  result
}

#' Calculate prominence classes or scores
#'
#' Reproduces `V7mdlValueConversions.ProminenceClass`. Its call to the legacy
#' `vpRoundUp` routine is treated as an identity because the routine overwrites
#' both of its attempted rounding results. The package uses double precision
#' rather than a VBA `Single` temporary.
#'
#' @param mean_cover Numeric mean vegetation cover.
#' @param presence Numeric vegetation presence expressed as a proportion.
#' @param return_score If `TRUE`, return the calculated score corresponding to
#'   Access report option `SVShowClass = 20`; otherwise return classes.
#'
#' @return A numeric score vector when `return_score` is `TRUE`; otherwise an
#'   integer class vector from 1 through 5. Invalid negative inputs return `NA`.
#' @export
vpro_prominence_class <- function(mean_cover, presence, return_score = FALSE) {
  values <- vpro_value_recycle(list(
    mean_cover = vpro_value_vector(mean_cover, "mean_cover"),
    presence = vpro_value_vector(presence, "presence")
  ))
  return_score <- vpro_value_flag(return_score, "return_score")
  score <- rep(NA_real_, length(values$mean_cover))
  valid <- !is.na(values$mean_cover) &
    !is.na(values$presence) &
    values$presence >= 0
  score[valid] <- values$mean_cover[valid] * 10 * sqrt(values$presence[valid])
  vpro_score_result(score, c(15, 50, 100, 200), 1:5, return_score)
}

#' Calculate Goldstream classes or scores
#'
#' Reproduces `V7mdlValueConversions.GoldstreamClass`. Its call to the legacy
#' `vpRoundUp` routine is treated as an identity because the routine overwrites
#' both of its attempted rounding results. The package uses double precision
#' rather than a VBA `Single` temporary.
#'
#' @inheritParams vpro_prominence_class
#'
#' @return A numeric score vector when `return_score` is `TRUE`; otherwise an
#'   integer class vector from 0 through 6. Invalid negative inputs return `NA`.
#' @export
vpro_goldstream_class <- function(mean_cover, presence, return_score = FALSE) {
  values <- vpro_value_recycle(list(
    mean_cover = vpro_value_vector(mean_cover, "mean_cover"),
    presence = vpro_value_vector(presence, "presence")
  ))
  return_score <- vpro_value_flag(return_score, "return_score")
  score <- rep(NA_real_, length(values$mean_cover))
  valid <- !is.na(values$mean_cover) &
    !is.na(values$presence) &
    values$mean_cover >= 0
  score[valid] <- values$presence[valid] * 100 * sqrt(values$mean_cover[valid])
  vpro_score_result(score, c(5, 25, 75, 150, 300, 500), 0:6, return_score)
}

#' Convert significance values to report classes
#'
#' Reproduces `V7mdlValueConversions.SignifClass`. Results are consistently
#' returned as text because the Access function mixes the `"+"` label with
#' numeric class values. Values at or below -1 return `NA` rather than an unset
#' VBA `Variant`.
#'
#' @param significance Numeric significance values.
#'
#' @return A character vector containing `"+"`, `"1"` through `"9"`, or `NA`.
#' @export
vpro_significance_class <- function(significance) {
  significance <- vpro_value_vector(significance, "significance")
  result <- rep(NA_character_, length(significance))
  valid <- !is.na(significance) & significance > -1
  result[valid] <- c("+", as.character(1:9))[
    findInterval(
      significance[valid],
      c(0.3, 1, 2.2, 5, 10, 20, 33, 50, 75),
      left.open = TRUE
    ) +
      1L
  ]
  result
}

#' Round values while enforcing a positive minimum
#'
#' Provides stable numeric behavior for the intended operation behind Access
#' `vpRoundUp` and `vpRoundUp2`. The legacy `vpRoundUp` is actually an identity,
#' while `vpRoundUp2` returns locale-formatted text for ordinary values and a
#' number below its threshold. This API intentionally returns numeric data.
#'
#' @param value A numeric vector.
#' @param digits A single nonnegative integer number of decimal places.
#' @param minimum A single finite numeric lower bound applied to nonmissing
#'   values after rounding.
#'
#' @return A numeric vector with missing values preserved.
#' @export
vpro_round_minimum <- function(value, digits = 2L, minimum = 10^-digits) {
  value <- vpro_value_vector(value, "value")
  if (!is.numeric(digits) || length(digits) != 1L || is.na(digits) || !is.finite(digits) || digits < 0 || digits != trunc(digits)) {
    stop("`digits` must be one nonnegative integer.", call. = FALSE)
  }
  if (!is.numeric(minimum) || length(minimum) != 1L || is.na(minimum) || !is.finite(minimum)) {
    stop("`minimum` must be one finite numeric value.", call. = FALSE)
  }
  result <- round(value, digits = as.integer(digits))
  result[!is.na(result)] <- pmax(result[!is.na(result)], minimum)
  result
}

#' Cap percentage-like values at 100
#'
#' Reproduces `V7mdlValueConversions.vpRoundDown1`, which caps values above 100
#' but does not otherwise round or constrain them.
#'
#' @param value A numeric vector.
#'
#' @return A numeric vector capped above at 100.
#' @export
vpro_cap_percent <- function(value) {
  value <- vpro_value_vector(value, "value")
  pmin(value, 100)
}
