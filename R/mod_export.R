
mod_export_ui <- function(id) {
  ns <- NS(id)
  tagList(
    card(
      card_header("Export R Dataset"),
      card_body(
        p("Generate a standard 'Wide' vegetation matrix compatible with R packages like 'vegan'."),
        layout_columns(
            selectInput(ns("export_proj"), "Filter by Project (Optional)", choices = NULL, multiple = TRUE),
            div(
                checkboxGroupInput(ns("export_layers"), "Layers", 
                                   choices = c("1 (Tree A1)"="1", "2 (Tree A2)"="2", "3 (Tree A3)"="3",
                                               "4 (Shrub B1)"="4", "5 (Shrub B2)"="5", 
                                               "6 (Herb C)"="6", "7 (Moss D)"="7"),
                                   selected = c("1","2","3","4","5","6","7"),
                                   inline = TRUE),
                checkboxInput(ns("export_lump"), "Apply Species Lumping", value = FALSE)
            ),
            col_widths = c(4, 8)
        ),
        div(class="d-flex gap-2",
            downloadButton(ns("dl_r_csv"), "Download CSV", class="btn-primary"),
            downloadButton(ns("dl_r_rds"), "Download RDS", class="btn-secondary")
        )
      )
    ),
    
    card(
      card_header("Export VENUS (XML)"),
      card_body(
        p("Export data in the VENUS XML format for submission."),
        downloadButton(ns("dl_venus"), "Download VENUS XML", class="btn-info disabled") # Disabled for now
      )
    )
  )
}

mod_export_server <- function(id, sys_state, con) {
  moduleServer(id, function(input, output, session) {
    
    # -- Initialize Choices --
    observe({
        # Load projects
        projs <- dbGetQuery(con, "SELECT projectid, projecttitle FROM Sample_Metadata ORDER BY projectid")
        if (nrow(projs) > 0) {
            updateSelectInput(session, "export_proj", choices = setNames(projs$projectid, paste(projs$projectid, "-", projs$projecttitle)))
        }
    })
    
    # -- Data Generation Helper --
    get_export_data <- function() {
        req(input$export_layers)
        
        # 1. Base Query
        # Using vw_USysAllVeg which is (PlotNumber, MyLayer, Species, Cover)
        
        # Filter layers
        layers_sql <- paste(paste0("'", input$export_layers, "'"), collapse=", ")
        query_veg <- sprintf("SELECT PlotNumber, MyLayer, Species, Cover FROM vw_USysAllVeg WHERE MyLayer IN (%s)", layers_sql)
        
        # Filter Project
        if (!is.null(input$export_proj) && length(input$export_proj) > 0) {
            # Filter by project requires joining Sample_Env/Admin to find which project a plot belongs to?
            # Or Sample_Metadata?
            # Sample_Env contains 'projectid'
            projs_sql <- paste(paste0("'", input$export_proj, "'"), collapse=", ")
            query_veg <- sprintf("SELECT v.* FROM vw_USysAllVeg v 
                                  JOIN Sample_Env e ON v.PlotNumber = e.plotnumber 
                                  WHERE v.MyLayer IN (%s) AND e.projectid IN (%s)", 
                                  layers_sql, projs_sql)
        }
        
        df_veg <- dbGetQuery(con, query_veg)
        
        if (nrow(df_veg) == 0) return(NULL)
        
        # 1.5. Convert Cover to Numeric BEFORE Lumping
        # We need sum cover during lumping, so we must convert first.
        # + -> 0.1, r -> 0.01 (Simplified)
        df_veg$CoverNum <- suppressWarnings(as.numeric(df_veg$Cover))
        # Handle NA produced by coercion if original wasn't NA
        df_veg$CoverNum[is.na(df_veg$CoverNum) & !is.na(df_veg$Cover)] <- 0.1 
        
        # 1.6. Apply Lumping (If selected)
        if (input$export_lump) {
            # Logic: We consolidate Species rows for the same Plot + Layer
            # This handles both 'Synonym Replacement' and 'Merging'
            df_veg <- apply_lumping(con, df_veg, 
                                    group_cols = c("PlotNumber", "MyLayer"), 
                                    measure_cols = c("CoverNum"))
        }

        # 2. Pivot to Wide
        df_veg$ColName <- paste0(df_veg$species, "_", df_veg$MyLayer)
        
        # Pivot
        library(tidyr)
        df_wide <- df_veg %>%
            select(PlotNumber, ColName, CoverNum) %>%
            pivot_wider(names_from = ColName, values_from = CoverNum, values_fill = 0)
            
        # 3. Get Env Data
        query_env <- "SELECT plotnumber, projectid, _location, date, latitude, longitude, elevation, slopegradient, aspect, sitenotes FROM Sample_Env"
        if (!is.null(input$export_proj) && length(input$export_proj) > 0) {
             projs_sql <- paste(paste0("'", input$export_proj, "'"), collapse=", ")
             query_env <- sprintf("%s WHERE projectid IN (%s)", query_env, projs_sql)
        }
        
        df_env <- dbGetQuery(con, query_env)
        
        # Join
        df_final <- right_join(df_env, df_wide, by = c("plotnumber" = "PlotNumber"))
        
        return(df_final)
    }
    
    # -- Download Handlers --
    output$dl_r_csv <- downloadHandler(
        filename = function() { paste0("vpro_export_", Sys.Date(), ".csv") },
        content = function(file) {
            d <- get_export_data()
            if(is.null(d)) { write.csv(data.frame(Message="No Data Found"), file); return() }
            write.csv(d, file, row.names=FALSE)
        }
    )
    
    output$dl_r_rds <- downloadHandler(
        filename = function() { paste0("vpro_export_", Sys.Date(), ".rds") },
        content = function(file) {
            d <- get_export_data()
            if(is.null(d)) { saveRDS(data.frame(Message="No Data Found"), file); return() }
            saveRDS(d, file)
        }
    )
    
  })
}
