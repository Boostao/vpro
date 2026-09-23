#' Maximum positive vegetation cover across ten layers
#'
#' Translates the numeric comparison in `V7mdlPlotProfiling.MadMax`, used by
#' `ProfileVeg` for the "Any" layer filter. The Access routine starts at zero
#' and returns a `Single`. This API uses R doubles and explicitly ignores
#' missing covers; the effect of VBA Null operands in the Access SQL call has
#' not been verified. It does not apply plot-profile criteria or modify plots.
#'
#' @param cover1,cover2,cover3,cover4,cover5,cover5a,cover5b,cover5c,cover6,cover7
#'   Numeric cover vectors in the order used by Access. Length-one inputs are
#'   recycled to the common length; missing values are ignored.
#'
#' @return A numeric vector with zero as the lower bound, including when all
#'   covers are missing.
#' @export
vpro_profile_max_cover <- function(
  cover1,
  cover2,
  cover3,
  cover4,
  cover5,
  cover5a,
  cover5b,
  cover5c,
  cover6,
  cover7
) {
  covers <- list(
    cover1 = cover1,
    cover2 = cover2,
    cover3 = cover3,
    cover4 = cover4,
    cover5 = cover5,
    cover5a = cover5a,
    cover5b = cover5b,
    cover5c = cover5c,
    cover6 = cover6,
    cover7 = cover7
  )
  covers <- Map(
    function(value, name) {
      if (is.logical(value) && length(value) > 0L && all(is.na(value))) {
        value <- as.numeric(value)
      }
      vpro_value_vector(value, name)
    },
    covers,
    names(covers)
  )
  covers <- vpro_value_recycle(covers)
  do.call(pmax, c(list(0), covers, list(na.rm = TRUE)))
}
