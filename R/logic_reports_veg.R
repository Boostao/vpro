# Shared helpers for vegetation reporting.

parse_plot_numbers <- function(plot_number, plot_numbers) {
  plots <- character()
  if (!is.null(plot_numbers) && nzchar(trimws(plot_numbers))) {
    plots <- unlist(strsplit(plot_numbers, "[,;\n\t ]+"))
  } else if (!is.null(plot_number) && nzchar(trimws(plot_number))) {
    plots <- c(plot_number)
  }
  plots <- trimws(plots)
  plots[nzchar(plots)]
}

normalize_veg_cols <- function(df) {
  if (nrow(df) == 0) return(df)
  cols <- names(df)
  pick_col <- function(candidates) {
    idx <- which(tolower(cols) %in% tolower(candidates))
    if (length(idx) > 0) cols[[idx[1]]] else NA_character_
  }
  plot_col <- pick_col(c("plotnumber", "PlotNumber"))
  layer_col <- pick_col(c("mylayer", "layer", "MyLayer"))
  species_col <- pick_col(c("species", "species_code", "Species"))
  cover_col <- pick_col(c("cover", "covervalue", "cover_value", "Cover", "CoverValue"))
  if (!is.na(plot_col)) df$plotnumber <- as.character(df[[plot_col]])
  if (!is.na(layer_col)) df$mylayer <- as.character(df[[layer_col]])
  if (!is.na(species_col)) df$species <- as.character(df[[species_col]])
  if (!is.na(cover_col)) df$cover <- as.character(df[[cover_col]])
  df
}

load_veg_report_data <- function(con,
                                 plot_numbers = character(),
                                 site_unit = "",
                                 project_id = "",
                                 apply_lumping = FALSE) {
  plots <- plot_numbers

  if (length(plots) == 0 && nzchar(site_unit) && DBI::dbExistsTable(con, "Sample_SU")) {
    su_df <- DBI::dbGetQuery(
      con,
      "SELECT PlotNumber FROM Sample_SU WHERE SiteUnit = ?",
      list(site_unit)
    )
    plots <- unique(as.character(su_df$PlotNumber))
  }

  if (length(plots) == 0 && nzchar(project_id) && DBI::dbExistsTable(con, "Sample_Env")) {
    env_df <- DBI::dbGetQuery(
      con,
      "SELECT PlotNumber FROM Sample_Env WHERE ProjectID = ?",
      list(project_id)
    )
    plots <- unique(as.character(env_df$PlotNumber))
  }

  plots <- plots[nzchar(plots)]
  if (length(plots) == 0) return(data.frame())

  plot_sql <- paste(DBI::dbQuoteString(con, plots), collapse = ", ")
  sql <- sprintf(
    "SELECT PlotNumber, MyLayer, Species, Cover FROM vw_USysAllVeg WHERE PlotNumber IN (%s)",
    plot_sql
  )
  veg <- DBI::dbGetQuery(con, sql)
  veg <- normalize_veg_cols(veg)
  if (nrow(veg) == 0) return(veg)

  veg$cover_num <- suppressWarnings(as.numeric(veg$cover))
  veg$present_num <- ifelse(is.na(veg$cover) | !nzchar(trimws(veg$cover)), 0L, 1L)
  veg$present <- veg$present_num > 0

  if (isTRUE(apply_lumping) && exists("apply_lumping")) {
    veg <- apply_lumping(con, veg, group_cols = c("plotnumber", "mylayer"), measure_cols = c("cover_num", "present_num"))
    veg$present <- veg$present_num > 0
    veg$cover <- as.character(veg$cover_num)
  }

  if (DBI::dbExistsTable(con, "LayerCode")) {
    layer_map <- DBI::dbGetQuery(
      con,
      "SELECT Layer1234567, Layer, LayerText, Strata, Lifeform FROM LayerCode"
    )
    names(layer_map) <- tolower(names(layer_map))
    names(layer_map)[names(layer_map) == "layer1234567"] <- "mylayer"
    names(layer_map)[names(layer_map) == "lifeform"] <- "layer_lifeform"
    veg <- dplyr::left_join(veg, layer_map, by = "mylayer")
  }

  meta_table <- NULL
  if (DBI::dbExistsTable(con, "lists.USysAllSpecs")) {
    meta_table <- "lists.USysAllSpecs"
  } else if (DBI::dbExistsTable(con, "USysAllSpecs")) {
    meta_table <- "USysAllSpecs"
  }

  if (!is.null(meta_table)) {
    meta <- DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT Code, ScientificName, EnglishName, ShortenedGuideName, CombinedEnglishName, common_name_pb, Lifeform FROM %s",
        meta_table
      )
    )
    names(meta) <- tolower(names(meta))
    names(meta)[names(meta) == "code"] <- "species"
    names(meta)[names(meta) == "lifeform"] <- "species_lifeform"
    veg <- dplyr::left_join(veg, meta, by = "species")
  }

  veg
}

summarize_veg_report <- function(df,
                                 group_by = "layer",
                                 order_by = "species",
                                 presence_min = 0,
                                 cover_min = 0,
                                 avg_type = "mean",
                                 show_common = "none") {
  if (nrow(df) == 0) return(df)

  group_label <- switch(
    tolower(group_by),
    "strata" = if (!is.null(df$strata)) df$strata else df$mylayer,
    "lifeform" = if (!is.null(df$species_lifeform)) df$species_lifeform else if (!is.null(df$layer_lifeform)) df$layer_lifeform else df$mylayer,
    "none" = rep("All", nrow(df)),
    if (!is.null(df$layer)) df$layer else df$mylayer
  )

  species_label <- if (!is.null(df$scientificname)) {
    ifelse(!is.na(df$scientificname) & nzchar(df$scientificname), df$scientificname, df$species)
  } else {
    df$species
  }

  common_label <- NULL
  common_field <- tolower(show_common)
  if (common_field == "english" && !is.null(df$englishname)) common_label <- df$englishname
  if (common_field == "short" && !is.null(df$shortenedguidename)) common_label <- df$shortenedguidename
  if (common_field == "combined" && !is.null(df$combinedenglishname)) common_label <- df$combinedenglishname
  if (common_field == "code") common_label <- df$species

  summary <- dplyr::tibble(
    group_label = as.character(group_label),
    species_label = as.character(species_label),
    common_label = if (is.null(common_label)) NA_character_ else as.character(common_label),
    plotnumber = as.character(df$plotnumber),
    present = as.logical(df$present),
    cover_num = as.numeric(df$cover_num)
  )

  summary <- summary %>%
    dplyr::group_by(group_label, species_label, common_label) %>%
    dplyr::summarise(
      plots_total = dplyr::n_distinct(plotnumber),
      plots_present = dplyr::n_distinct(plotnumber[present]),
      mean_cover = if (tolower(avg_type) == "sum_per_plot") {
        ifelse(plots_total > 0, sum(cover_num, na.rm = TRUE) / plots_total, NA_real_)
      } else {
        ifelse(sum(present, na.rm = TRUE) > 0, mean(cover_num[present], na.rm = TRUE), NA_real_)
      },
      .groups = "drop"
    )

  summary$presence_pct <- ifelse(summary$plots_total > 0,
    100 * summary$plots_present / summary$plots_total,
    NA_real_
  )

  presence_val <- ifelse(is.na(summary$presence_pct), 0, summary$presence_pct)
  cover_val <- ifelse(is.na(summary$mean_cover), 0, summary$mean_cover)
  summary <- summary[presence_val >= presence_min & cover_val >= cover_min, , drop = FALSE]

  if (tolower(order_by) == "value") {
    summary <- summary[order(-summary$mean_cover, summary$species_label), , drop = FALSE]
  } else if (tolower(order_by) == "presence") {
    summary <- summary[order(-summary$presence_pct, summary$species_label), , drop = FALSE]
  } else {
    summary <- summary[order(summary$species_label), , drop = FALSE]
  }

  summary
}
