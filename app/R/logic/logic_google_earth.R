# Google Earth KML generation
# Port of Access V7mdlGoogleEarth.SinglePlotPlotInGE

#' Generate a KML string for a single plot
#' @param con DuckDB connection
#' @param plot_number Character plot ID
#' @param desc_field Character column name for description (default "plotnumber")
#' @return Character KML string, or NULL if coords missing
generate_single_plot_kml <- function(con, plot_number, desc_field = "plotnumber") {
  tbl <- as.character(db_tb(con, "Env", config("Current", "CurrProject"), prj = TRUE))
  row <- tryCatch(
    db_query(con, paste(
      "SELECT plotnumber, longitude, latitude FROM", tbl,
      "WHERE plotnumber = ? AND longitude IS NOT NULL AND latitude IS NOT NULL"
    ), params = list(plot_number)),
    error = function(e) data.frame()
  )
  if (!nrow(row)) return(NULL)

  lon <- suppressWarnings(as.numeric(row$longitude[1]))
  lat <- suppressWarnings(as.numeric(row$latitude[1]))
  if (is.na(lon) || is.na(lat)) return(NULL)

  # Ensure longitude is negative (western hemisphere)
  if (lon > 0) lon <- -lon

  project <- config("Current", "CurrProject") %||% "VPro"
  place_name <- as.character(row$plotnumber[1])

  paste0(
    '<?xml version="1.0" encoding="UTF-8"?>\n',
    '<kml xmlns="http://earth.google.com/kml/2.1">\n',
    '<Document>\n',
    '  <name>', project, ' - ', place_name, '</name>\n',
    '  <Style id="a"><IconStyle><Icon>',
    '<href>http://maps.google.com/mapfiles/ms/icons/red-dot.png</href>',
    '</Icon></IconStyle></Style>\n',
    '  <Placemark>\n',
    '    <name>', place_name, '</name>\n',
    '    <styleUrl>#a</styleUrl>\n',
    '    <Point>\n',
    '      <coordinates>', lon, ',', lat, ',0</coordinates>\n',
    '    </Point>\n',
    '    <description><![CDATA[Plot: ', place_name, ']]></description>\n',
    '  </Placemark>\n',
    '</Document>\n',
    '</kml>'
  )
}
