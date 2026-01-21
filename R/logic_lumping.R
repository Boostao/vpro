
#' Apply Species Lumping to Vegetation Data
#'
#' Consolidates species codes based on the 'Sample_Lump' table.
#' Rows with synonymous species codes are merged, and their cover values are summed.
#'
#' @param con Database connection to read 'Sample_Lump'
#' @param df Dataframe containing at least 'species' column and numeric measure columns (e.g. 'cover_num')
#' @param group_cols detailed vector of columns to group by (e.g. c("plotnumber", "mylayer"))
#' @param measure_cols vector of numeric columns to sum (e.g. c("cover_num"))
#'
#' @return Dataframe with consolidated species and summed measures
apply_lumping <- function(con, df, group_cols, measure_cols) {
  
  # Load lumping map
  # Check if table exists first - precautionary
  if (!dbExistsTable(con, "Sample_Lump")) {
      warning("Sample_Lump table not found. Skipping lumping.")
      return(df)
  }
  
  lump_map <- dbGetQuery(con, "SELECT sppcode, lumpcode FROM Sample_Lump WHERE _use = 1")
  
  if (nrow(lump_map) == 0) return(df)
  
  # Normalize Strings
  df$spp_lookup <- toupper(trimws(df$species))
  lump_map$sppcode <- toupper(trimws(lump_map$sppcode))
  lump_map$lumpcode <- toupper(trimws(lump_map$lumpcode))
  
  # Perform Replacement
  # Left join to find replacements
  # If match found, use lumpcode. If not, keep original species.
  joined <- df %>%
    left_join(lump_map, by = c("spp_lookup" = "sppcode")) %>%
    mutate(
        final_species = ifelse(!is.na(lumpcode), lumpcode, species)
    )
  
  # Aggregation
  # Group by (AnalysisUnit + FinalSpecies) and Sum Measures
  result <- joined %>%
    group_by(pick(all_of(c(group_cols, "final_species")))) %>%
    summarise(across(all_of(measure_cols), \(x) sum(x, na.rm = TRUE)), .groups = "drop") %>%
    rename(species = final_species)
    
  return(result)
}
