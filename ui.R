# UI Definition
# Uses bslib for a modern dashboard layout replacing the Access Menu

ui <- page_navbar(
  title = "VPro Shiny",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  
  # Sidebar (Global Context)
  sidebar = sidebar(
    width = 300,
    title = "Context",
    selectInput("sel_project", "Project", choices = NULL),
    selectInput("sel_su", "Site Unit / Plot", choices = NULL),
    hr(),
    verbatimTextOutput("ctx_summary")
  ),

  # Main Tabs
  nav_panel("Vegetation", 
    mod_veg_sample_ui("veg")
  ),
  nav_panel("Site & Env", 
    mod_site_env_ui("env")
  ),
  nav_panel("Export",
    mod_export_ui("export")
  ),
  nav_panel("Images & Maps",
    mod_images_ui("imgs")
  ),
  nav_panel("Reports",
    mod_reporting_ui("report")
  ),
  nav_panel("Administration", 
    mod_admin_ui("admin")
  )
)
