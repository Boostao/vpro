# Business Logic for Vegetation Data Layer

#' Get Vegetation Data for a specific Site Unit
#'
#' @param con Database connection
#' @param site_unit_id The Site Unit ID (string) to filter by
#' @param project_id (Optional) Project ID
#'
#' @return A dataframe with vegetation data (scientific name, layer, cover)
get_vegetation_data <- function(con, site_unit_id, project_id = NULL) {
  
  if (is.null(site_unit_id) || site_unit_id == "") {
    return(data.frame())
  }
  
  # Tables
  veg <- tbl(con, "vw_Sample_Veg_Long")
  su <- tbl(con, "Sample_SU")
  spp <- tbl(con, "SppList")
  layers <- tbl(con, "LayerCode")
  
  # Filter Plots by Site Unit
  target_plots <- su %>%
    filter(siteunit == site_unit_id) %>%
    select(plotnumber)
  
  # Join Veg Data
  data <- veg %>%
    inner_join(target_plots, by = "plotnumber") %>%
    left_join(spp, by = c("species_code" = "code")) %>%
    left_join(layers, by = c("layer" = "layer1234567")) %>%
    mutate(
      scientific_name = coalesce(scientificname, species_code)
    ) %>%
    select(
      plotnumber,
      species_code,
      scientific_name,
      layer_code = layer,
      layer_desc = layertext, 
      cover = cover_value
    ) %>%
    arrange(plotnumber, layer_code, scientific_name)
  
  collect(data)
}
