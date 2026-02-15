# UI Definition
# Uses bslib for a modern dashboard layout replacing the Access Menu

ui <- page_navbar(
  id = "main_tabs",
  title = div(
    class = "d-flex align-items-center gap-2 vpro-navbar-title",
    icon("table-cells-large"),
    span("VPro 64", class = "fw-bold"),
    tags$small("Data", class = "vpro-navbar-subtitle")
  ),
  theme = bs_theme(version = 5),
  header = tagList(
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "bcgov-static/font.css"),
      tags$link(rel = "stylesheet", type = "text/css", href = "bcgov/bcgov.css"),
      tags$style(HTML("\n        .vpro-navbar-title {\n          color: #ffffff;\n          line-height: 1;\n          margin-top: 0;\n          margin-bottom: 0;\n        }\n        .vpro-navbar-subtitle {\n          color: #d9ecff;\n          font-size: 0.78rem;\n          margin-left: 2px;\n        }\n        .navbar .navbar-brand {\n          display: flex;\n          align-items: center;\n          padding-top: 0;\n          padding-bottom: 0;\n          min-height: 32px;\n        }\n        .vpro-sidebar .form-group,\n        .vpro-sidebar .shiny-input-container {\n          margin-bottom: 0.45rem;\n        }\n        .vpro-sidebar .btn {\n          padding-top: 0.22rem;\n          padding-bottom: 0.22rem;\n          font-size: 0.82rem;\n        }\n        .vpro-sidebar .vpro-section-title {\n          margin-top: 0.35rem;\n          margin-bottom: 0.35rem;\n          font-size: 0.82rem;\n          font-weight: 600;\n          color: #355f98;\n        }\n      "))
    ),
    shinyjs::useShinyjs(),
    tags$script(HTML("(function(){\n  function shouldIgnoreKey(evt){\n    var tag = (evt.target && evt.target.tagName) ? evt.target.tagName.toLowerCase() : '';\n    return tag === 'input' || tag === 'textarea' || evt.target.isContentEditable;\n  }\n\n  document.addEventListener('keydown', function(e){\n    var key = (e.key || '').toLowerCase();\n    if ((e.ctrlKey || e.metaKey) && key === 's') {\n      e.preventDefault();\n      Shiny.setInputValue('global_save', Date.now());\n      return;\n    }\n    if ((e.ctrlKey || e.metaKey) && key === 'n') {\n      e.preventDefault();\n      Shiny.setInputValue('global_new', Date.now());\n      return;\n    }\n    if (shouldIgnoreKey(e)) return;\n  });\n})();"))
    ,
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
    width = 300,
    title = NULL,
    id = "context_sidebar",
    open = "desktop",
    div(
      class = "vpro-sidebar",
      div(
        class = "bg-primary-subtle border border-primary-subtle rounded-2 p-2 mb-2",
        div(class = "h4 mb-0 text-primary fw-bold", "VPro 64"),
        div(class = "text-primary", "Data")
      ),
      selectInput("sel_project", "Project:", choices = NULL),
      selectInput("sel_su", "Site Unit:", choices = NULL),
      selectInput(
        "sel_hierarchy",
        "Hierarchy:",
        choices = NULL
      ),
      div(class = "vpro-section-title", "Data Forms"),
      actionButton("btn_nav_data_entry", "Data Entry Forms", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_two_page", "2-Page Forms", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_single_page", "Single-Page Form", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_sivi", "SIVI Form", class = "btn btn-light border w-100 mb-2"),
      div(class = "vpro-section-title", "Classification"),
      actionButton("btn_nav_su_tree", "Site Unit Tree View", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_su_table", "Site Unit Table", class = "btn btn-light border w-100 mb-1"),
      actionButton("btn_nav_hierarchy_tree", "Hierarchy Tree View", class = "btn btn-light border w-100 mb-2"),
      hr(class = "my-2"),
      actionButton("btn_whatsnew", "What's New", class = "btn btn-outline-primary w-100 mb-2")
    )
  ),

  # Main Tabs
  nav_panel(tagList(icon("leaf"), "Vegetation"), value = "Vegetation",
    mod_veg_sample_ui("veg")
  ),
  nav_panel(tagList(icon("mountain"), "Site & Env"), value = "Site & Env",
    mod_site_env_ui("env")
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
  nav_panel(tagList(icon("sitemap"), "Hierarchy"), value = "Hierarchy",
    mod_hierarchy_ui("hier")
  ),
  nav_panel(tagList(icon("earth-americas"), "BEC Map Explorer"), value = "BEC Map Explorer",
    mod_becweb_map_ui("becmap")
  ),
  nav_spacer(),
  nav_panel(tagList(icon("cloud-arrow-up"), "Upload"), value = "Upload",
    mod_upload_ui("upload")
  ),
  nav_panel(tagList(icon("code-merge"), "Merge"), value = "Merge",
    mod_merge_ui("merge")
  ),
  nav_panel(tagList(icon("user-shield"), "Auth"), value = "Auth",
    mod_auth_ui("auth")
  ),
  nav_panel(tagList(icon("gear"), "Administration"), value = "Administration",
    mod_admin_ui("admin")
  )
)
