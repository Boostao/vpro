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

signif_class <- function(signif) {
  if (is.na(signif)) return(NA_character_)
  if (signif > -1 && signif <= 0.3) return("+")
  if (signif > 0.3 && signif <= 1) return("1")
  if (signif > 1 && signif <= 2.2) return("2")
  if (signif > 2.2 && signif <= 5) return("3")
  if (signif > 5 && signif <= 10) return("4")
  if (signif > 10 && signif <= 20) return("5")
  if (signif > 20 && signif <= 33) return("6")
  if (signif > 33 && signif <= 50) return("7")
  if (signif > 50 && signif <= 75) return("8")
  if (signif > 75) return("9")
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

build_diagnostic_matrix <- function(con, su_table = "Sample_SU", project_id = NULL, average_type = c("plots", "covers")) {
  average_type <- match.arg(average_type)
  if (!DBI::dbExistsTable(con, su_table) || !DBI::dbExistsTable(con, "vw_USysAllVeg")) {
    return(list(matrix = data.frame(), diagnostics = data.frame()))
  }

  su_fields <- DBI::dbListFields(con, su_table)
  plot_col <- if ("PlotNumber" %in% su_fields) "PlotNumber" else if ("plotnumber" %in% su_fields) "plotnumber" else NULL
  unit_col <- if ("SiteUnit" %in% su_fields) "SiteUnit" else if ("siteunit" %in% su_fields) "siteunit" else NULL
  if (is.null(plot_col) || is.null(unit_col)) {
    return(list(matrix = data.frame(), diagnostics = data.frame()))
  }

  veg_fields <- DBI::dbListFields(con, "vw_USysAllVeg")
  veg_plot_col <- if ("plotnumber" %in% veg_fields) "plotnumber" else if ("PlotNumber" %in% veg_fields) "PlotNumber" else NULL
  veg_species_col <- if ("species_code" %in% veg_fields) "species_code" else if ("species" %in% veg_fields) "species" else NULL
  veg_cover_col <- if ("cover_value" %in% veg_fields) "cover_value" else if ("cover" %in% veg_fields) "cover" else if ("Cover" %in% veg_fields) "Cover" else NULL
  veg_project_col <- if ("projectid" %in% veg_fields) "projectid" else if ("ProjectID" %in% veg_fields) "ProjectID" else NULL
  if (is.null(veg_plot_col) || is.null(veg_species_col) || is.null(veg_cover_col)) {
    return(list(matrix = data.frame(), diagnostics = data.frame()))
  }

  su_sql <- sprintf("SELECT %s AS plotnumber, %s AS siteunit FROM %s", plot_col, unit_col, su_table)
  su_df <- DBI::dbGetQuery(con, su_sql)
  if (nrow(su_df) == 0) return(list(matrix = data.frame(), diagnostics = data.frame()))

  veg_sql <- sprintf("SELECT %s AS plotnumber, %s AS species, %s AS cover_value%s FROM vw_USysAllVeg",
                     veg_plot_col,
                     veg_species_col,
                     veg_cover_col,
                     if (!is.null(veg_project_col)) paste0(", ", veg_project_col, " AS projectid") else "")
  veg_df <- DBI::dbGetQuery(con, veg_sql)
  if (nrow(veg_df) == 0) return(list(matrix = data.frame(), diagnostics = data.frame()))

  if (!is.null(project_id) && !is.null(veg_project_col) && "projectid" %in% names(veg_df)) {
    veg_df <- veg_df[veg_df$projectid == project_id, , drop = FALSE]
  }
  if (nrow(veg_df) == 0) return(list(matrix = data.frame(), diagnostics = data.frame()))

  merged <- merge(su_df, veg_df, by = "plotnumber", all = FALSE)
  if (nrow(merged) == 0) return(list(matrix = data.frame(), diagnostics = data.frame()))

  merged$cover_value <- trimws(as.character(merged$cover_value))
  merged$cover_num <- suppressWarnings(as.numeric(merged$cover_value))
  merged$cover_num[is.na(merged$cover_num)] <- 0

  plot_counts <- aggregate(plotnumber ~ siteunit, data = merged, FUN = function(x) length(unique(x)))
  names(plot_counts)[2] <- "n_plots"

  ncover_df <- aggregate(merged$cover_value ~ siteunit + species, data = merged, FUN = length)
  names(ncover_df)[names(ncover_df) == "merged$cover_value"] <- "ncover"
  total_df <- aggregate(merged$cover_num ~ siteunit + species, data = merged, FUN = sum)
  names(total_df)[names(total_df) == "merged$cover_num"] <- "totalcover"
  grouped <- merge(ncover_df, total_df, by = c("siteunit", "species"))

  grouped <- merge(grouped, plot_counts, by = "siteunit", all.x = TRUE)
  grouped$presence <- grouped$ncover / grouped$n_plots
  grouped$presence_class <- vapply(grouped$presence, diagnostic_presence_class, character(1))

  signif_val <- if (average_type == "plots") {
    grouped$totalcover / grouped$n_plots
  } else {
    grouped$totalcover / grouped$ncover
  }
  grouped$signif_class <- vapply(signif_val, signif_class, character(1))
  grouped$code <- ifelse(
    is.na(grouped$presence_class) | is.na(grouped$signif_class),
    NA_character_,
    paste(grouped$presence_class, grouped$signif_class, sep = " - ")
  )

  species_vals <- unique(grouped$species)
  unit_vals <- unique(grouped$siteunit)
  matrix_df <- data.frame(Species = species_vals, stringsAsFactors = FALSE)
  for (unit in unit_vals) {
    unit_rows <- grouped[grouped$siteunit == unit, , drop = FALSE]
    code_map <- setNames(unit_rows$code, unit_rows$species)
    matrix_df[[unit]] <- unname(code_map[species_vals])
  }

  diagnostics <- diagnostic_from_matrix(matrix_df, species_col = "Species")
  list(matrix = matrix_df, diagnostics = diagnostics)
}
