# Diagnostic helpers for vegetation/site unit diagnostics

diagnostic_presence_class <- function(presence) {
  if (is.na(presence)) return(NA_character_)
  if (presence >= 0 && presence <= 0.2) return("1")
  if (presence > 0.2 && presence <= 0.4) return("2")
  if (presence > 0.4 && presence <= 0.6) return("3")
  if (presence > 0.6 && presence <= 0.8) return("4")
  if (presence > 0.8 && presence <= 1) return("5")
  NA_character_
}

parse_presence_significance <- function(code) {
  if (is.null(code)) return(list(presence = NA_integer_, significance = NA_integer_))
  code_chr <- trimws(as.character(code))
  if (!nzchar(code_chr)) return(list(presence = NA_integer_, significance = NA_integer_))

  presence <- suppressWarnings(as.integer(substr(code_chr, 1, 1)))
  significance <- suppressWarnings(as.integer(substr(code_chr, nchar(code_chr), nchar(code_chr))))

  list(presence = presence, significance = significance)
}

compute_diagnostic_flags <- function(codes) {
  if (length(codes) == 0) return(list(diagnosis = "", unit = NA_character_, flags = character(0)))

  codes_vec <- codes
  names_all <- names(codes_vec)
  codes_chr <- as.character(codes_vec)
  valid <- nzchar(trimws(codes_chr)) & !is.na(codes_chr)
  if (!any(valid)) return(list(diagnosis = "", unit = NA_character_, flags = character(0)))

  codes_chr <- codes_chr[valid]
  names_chr <- if (!is.null(names_all)) names_all[valid] else NULL
  parsed <- lapply(codes_chr, parse_presence_significance)
  presence_vals <- vapply(parsed, function(x) x$presence, integer(1))
  signif_vals <- vapply(parsed, function(x) x$significance, integer(1))

  if (length(presence_vals) == 0 || all(is.na(presence_vals))) {
    return(list(diagnosis = "", unit = NA_character_, flags = character(0)))
  }

  max_idx <- which.max(replace(presence_vals, is.na(presence_vals), -Inf))
  max_presence <- presence_vals[max_idx]
  max_significance <- signif_vals[max_idx]
  avg_significance <- max_significance
  max_field <- if (!is.null(names_chr) && length(names_chr) > 0) names_chr[max_idx] else NA_character_

  count_presence <- sum(presence_vals > (max_presence - 2), na.rm = TRUE)
  count_presence_v <- sum(presence_vals == 5, na.rm = TRUE)
  count_significance <- sum(signif_vals > (max_significance - 2), na.rm = TRUE)

  differential <- count_presence == 1 && max_presence >= 3
  dominant_differential <- count_significance == 1 && !differential && avg_significance >= 5
  constant_dominant <- max_presence == 5 && count_presence == 1 && max_significance >= 5
  constant <- max_presence == 5 && count_presence_v == 1 && max_significance < 5
  important_companion <- !differential && !dominant_differential && !constant_dominant && !constant && max_presence >= 2 && count_presence == 1

  flags <- character(0)
  if (differential) flags <- c(flags, "d")
  if (dominant_differential) flags <- c(flags, "dd")
  if (constant_dominant) flags <- c(flags, "cd")
  if (constant) flags <- c(flags, "c")
  if (important_companion) flags <- c(flags, "ic")

  list(diagnosis = paste(flags, collapse = ", "), unit = max_field, flags = flags)
}

compute_diagnostic_row <- function(row, species_col = "Species") {
  if (is.null(row)) return(NULL)
  row_list <- if (is.data.frame(row)) as.list(row[1, , drop = FALSE]) else as.list(row)

  species <- if (species_col %in% names(row_list)) row_list[[species_col]] else NA
  row_list[[species_col]] <- NULL
  if (length(row_list) == 0) return(NULL)

  result <- compute_diagnostic_flags(unlist(row_list, use.names = TRUE))
  if (!nzchar(result$diagnosis)) return(NULL)

  list(species = species, unit = result$unit, diagnosis = result$diagnosis)
}

diagnostic_from_matrix <- function(df, species_col = "Species") {
  if (is.null(df) || nrow(df) == 0) return(data.frame())
  if (!(species_col %in% names(df))) return(data.frame())

  results <- lapply(seq_len(nrow(df)), function(idx) {
    compute_diagnostic_row(df[idx, , drop = FALSE], species_col = species_col)
  })
  results <- Filter(Negate(is.null), results)
  if (length(results) == 0) return(data.frame())

  data.frame(
    Species = vapply(results, function(x) x$species, character(1)),
    Unit = vapply(results, function(x) x$unit, character(1)),
    Diagnosis = vapply(results, function(x) x$diagnosis, character(1)),
    stringsAsFactors = FALSE
  )
}
