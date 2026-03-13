# UI Definition
# Uses bslib for a modern dashboard layout replacing the Access Menu

if (!"bcgov" %in% bslib::bootswatch_themes()) {
  source("theme/add_bcgov_bootswatch_to_bslib.R")
}

ui <- page_navbar(
  id = "main_tabs",
  title = div(
    class = "d-flex align-items-center gap-2 vpro-navbar-title",
    icon("table-cells-large"),
    span("VPro 64", class = "fw-bold"),
    tags$small("Data", class = "vpro-navbar-subtitle")
  ),
  theme = bs_theme(version = 5, bootswatch = "bcgov"),
  header = tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "vpro-ui.css"),
      tags$script(src = "vpro-ui.js")
    ),
    shinyjs::useShinyjs(),
    tags$div(
      class = "d-md-none px-2 pb-2",
      actionButton(
        "btn_toggle_context",
        "Context",
        class = "btn btn-outline-secondary btn-sm w-100"
      )
    )
  ),
  
  # Sidebar (VPro-style navigation)
  sidebar = sidebar(
    width = 360,
    title = NULL,
    id = "context_sidebar",
    open = "desktop",
    div(
      class = "vpro-sidebar",
      div(class = "d-none", textInput("sel_su", NULL, value = "")),
      uiOutput("context_sidebar_content")
    )
  ),

  # Main Tabs
  nav_panel(tagList(icon("leaf"), "Vegetation"), value = "Vegetation",
    mod_veg_sample_ui("veg")
  ),
  nav_panel(tagList(icon("mountain"), "FS882-6x4XL"), value = "FS882-6x4XL",
    mod_fs882_6x4xl_ui("fs882_6x4xl")
  ),
  nav_panel(tagList(icon("file-export"), "Export"), value = "Export",
    mod_export_ui("export")
  ),
  nav_panel(tagList(icon("file-import"), "Import"), value = "Import",
    mod_import_ui("import")
  ),
  nav_panel(tagList(icon("map-location-dot"), "Images & Maps"), value = "Images & Maps",
    mod_images_ui("imgs")
  ),
  nav_panel(tagList(icon("file-lines"), "Reports"), value = "Reports",
    mod_reporting_ui("report")
  ),
  nav_panel(tagList(icon("table"), "SU Table"), value = "SU Table",
    mod_su_table_ui("su_table")
  ),
  nav_panel(tagList(icon("sitemap"), "Hierarchy"), value = "Hierarchy",
    mod_hierarchy_ui("hier")
  ),
  nav_panel(tagList(icon("earth-americas"), "BEC Map Explorer"), value = "BEC Map Explorer",
    mod_becweb_map_ui("becmap")
  ),
  nav_spacer(),
  #nav_panel(tagList(icon("cloud-arrow-up"), "Upload"), value = "Upload",
  #  mod_upload_ui("upload")
  #),
  nav_panel(tagList(icon("arrows-rotate"), "Sync"), value = "Sync",
    mod_sync_ui("sync")
  ),
  nav_panel(tagList(icon("user-shield"), "Auth"), value = "Auth",
    mod_auth_ui("auth")
  ),
  nav_item(uiOutput("nav_plot_context")),
  nav_item(mod_auth_status_ui("auth_status")),
  nav_panel(tagList(icon("gear"), "Administration"), value = "Administration",
    mod_admin_ui("admin")
  )
)
