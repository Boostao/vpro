
# Module: Images & Maps
# Displays associated images and allows KML generation

mod_images_ui <- function(id) {
  ns <- NS(id)
  tagList(
    layout_columns(
      col_widths = c(8, 4),
      
      # Column 1: Image Gallery
      card(
        card_header("Site Images"),
        card_body(
            uiOutput(ns("gallery_ui"))
        )
      ),
      
      # Column 2: Maps & KML
      card(
        card_header("Location & Export"),
        card_body(
          h5("Google Earth"),
          p("Generate a KML file for all plots in the current project."),
          downloadButton(ns("dl_kml"), "Download Project KML", class = "btn-success w-100"),
          hr(),
          verbatimTextOutput(ns("loc_debug"))
        )
      )
    )
  )
}

mod_images_server <- function(id, sys_state, con) {
  moduleServer(id, function(input, output, session) {
    
    # 1. Image Gallery
    output$gallery_ui <- renderUI({
      req(sys_state$CurrSU)
      
      # Query Images
      # Assuming 'blob' contains Base64 encoded image or raw binary
      # We cast to string just in case
      imgs <- dbGetQuery(con, "SELECT filename, caption, blob FROM USysPictureBlob WHERE plotorunit = ?", list(sys_state$CurrSU))
      
      if (nrow(imgs) == 0) {
        return(div(class="text-muted p-3", "No images found for this plot."))
      }
      
      # Generate Cards for each image
      image_cards <- lapply(1:nrow(imgs), function(i) {
        row <- imgs[i, ]
        
        # Check if blob is valid (simple check)
        # If it's a very short string, it might be a path or an error.
        src_str <- ""
        if (!is.na(row$blob) && nchar(row$blob) > 100) {
            # Assume Base64 JPEG
            # In VPro, typically these are JPEGs.
            src_str <- paste0("data:image/jpeg;base64,", row$blob)
        } else {
            # Placeholder
            src_str <- "" 
        }
        
        div(class = "card mb-3",
            if(src_str != "") img(src = src_str, class = "card-img-top", style="max-height: 400px; object-fit: contain;") else div("Invalid Image Data"),
            div(class = "card-body",
                h6(class = "card-title", row$filename),
                p(class = "card-text", row$caption)
            )
        )
      })
      
      do.call(tagList, image_cards)
    })
    
    # 2. Location Debug
    output$loc_debug <- renderText({
      req(sys_state$CurrSU)
      loc <- dbGetQuery(con, "SELECT latitude, longitude, utmzone, utmeasting, utmnorthing FROM Sample_Env WHERE plotnumber = ?", list(sys_state$CurrSU))
      if (nrow(loc) > 0) {
        paste("Current Plot Location:\n",
              "Lat:", loc$latitude, "Long:", loc$longitude, "\n",
              "UTM:", loc$utmzone, loc$utmeasting, "E", loc$utmnorthing, "N")
      } else {
        "No location data."
      }
    })
    
    # 3. KML Export
    output$dl_kml <- downloadHandler(
      filename = function() {
        paste0("Project_", sys_state$CurrProject, "_Locations.kml")
      },
      content = function(file) {
        req(sys_state$CurrProject)
        
        # 1. Fetch Data
        sql <- "SELECT plotnumber, latitude, longitude, _location FROM Sample_Env WHERE projectid = ? AND latitude IS NOT NULL AND longitude IS NOT NULL"
        pts <- dbGetQuery(con, sql, list(sys_state$CurrProject))
        
        if (nrow(pts) == 0) {
          showNotification("No valid coordinates found in this project.", type = "error")
          return(NULL)
        }
        
        # 2. Generate KML Content
        # Header
        kml <- c(
          '<?xml version="1.0" encoding="UTF-8"?>',
          '<kml xmlns="http://www.opengis.net/kml/2.2">',
          '<Document>',
          paste0('<name>Project ', sys_state$CurrProject, '</name>')
        )
        
        # Placemarks
        for (i in 1:nrow(pts)) {
          pname <- pts$plotnumber[i]
          pdesc <- pts[["_location"]][i]
          lat   <- pts$latitude[i]
          lon   <- pts$longitude[i]
          
          pm <- c(
            '<Placemark>',
            paste0('  <name>', pname, '</name>'),
            paste0('  <description>', pdesc, '</description>'),
            '  <Point>',
            paste0('    <coordinates>', lon, ',', lat, ',0</coordinates>'),
            '  </Point>',
            '</Placemark>'
          )
          kml <- c(kml, pm)
        }
        
        # Footer
        kml <- c(kml, '</Document>', '</kml>')
        
        # 3. Write File
        writeLines(kml, file)
      }
    )
    
  })
}
