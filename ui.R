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
        tags$style(HTML("\n        .vpro-navbar-title {\n          color: #ffffff;\n          line-height: 1;\n          margin-top: 0;\n          margin-bottom: 0;\n        }\n        .vpro-navbar-subtitle {\n          color: #d9ecff;\n          font-size: 0.78rem;\n          margin-left: 2px;\n        }\n        .navbar .navbar-brand {\n          display: flex;\n          align-items: center;\n          padding-top: 0;\n          padding-bottom: 0;\n          min-height: 32px;\n        }\n        .vpro-sidebar {\n          padding-top: 0.15rem;\n        }\n        .vpro-nav-context {\n          display: flex;\n          align-items: center;\n          gap: 0.75rem;\n          padding: 0.3rem 0.7rem;\n          border-radius: 999px;\n          background: rgba(255, 255, 255, 0.14);\n          border: 1px solid rgba(255, 255, 255, 0.18);\n          color: #ffffff;\n          font-size: 0.76rem;\n          line-height: 1.05;\n          white-space: nowrap;\n        }\n        .vpro-nav-context-item {\n          display: flex;\n          flex-direction: column;\n          min-width: 0;\n        }\n        .vpro-nav-context-label {\n          color: rgba(255, 255, 255, 0.74);\n          font-size: 0.63rem;\n          letter-spacing: 0.04em;\n          text-transform: uppercase;\n        }\n        .vpro-nav-context-value {\n          max-width: 9rem;\n          overflow: hidden;\n          text-overflow: ellipsis;\n          font-weight: 600;\n        }\n        .vpro-nav-context-sep {\n          width: 1px;\n          align-self: stretch;\n          background: rgba(255, 255, 255, 0.18);\n        }\n        .vpro-sidebar .form-group,\n        .vpro-sidebar .shiny-input-container {\n          margin-bottom: 0.45rem;\n        }\n        .vpro-sidebar .btn {\n          padding-top: 0.22rem;\n          padding-bottom: 0.22rem;\n          font-size: 0.82rem;\n        }\n        .vpro-sidebar .vpro-section-title {\n          margin-top: 0.35rem;\n          margin-bottom: 0.35rem;\n          font-size: 0.82rem;\n          font-weight: 600;\n          color: #355f98;\n        }\n        .vpro-picker-card {\n          border: 1px solid rgba(53, 95, 152, 0.16);\n        }\n        .vpro-picker-card .card-header {\n          background: linear-gradient(135deg, rgba(214, 233, 255, 0.95), rgba(244, 249, 255, 0.96));\n          border-bottom: 1px solid rgba(53, 95, 152, 0.12);\n        }\n        .vpro-picker-table .dataTables_wrapper .dataTables_filter,\n        .vpro-picker-table .dataTables_wrapper .dataTables_info,\n        .vpro-picker-table .dataTables_wrapper .dataTables_length,\n        .vpro-picker-table .dataTables_wrapper .dataTables_paginate {\n          display: none;\n        }\n        .vpro-picker-table table.dataTable {\n          border-collapse: separate !important;\n          border-spacing: 0 0.45rem;\n          background: transparent;\n          margin-top: -0.45rem !important;\n        }\n        .vpro-picker-table table.dataTable thead {\n          display: none;\n        }\n        .vpro-picker-table table.dataTable tbody tr {\n          background: transparent;\n        }\n        .vpro-picker-table table.dataTable tbody td {\n          text-align: center;\n          border: 1px solid rgba(53, 95, 152, 0.14) !important;\n          border-radius: 0.9rem;\n          background: linear-gradient(180deg, #f7fbff 0%, #edf5ff 100%) !important;\n          color: #21456d !important;\n          font-weight: 600;\n          letter-spacing: 0.01em;\n          padding: 0.68rem 0.75rem !important;\n          cursor: pointer;\n          transition: transform 0.14s ease, background 0.14s ease, border-color 0.14s ease;\n        }\n        .vpro-picker-table table.dataTable tbody tr:hover td {\n          transform: translateY(-1px);\n          background: linear-gradient(180deg, #f0f7ff 0%, #ddeeff 100%) !important;\n          border-color: rgba(53, 95, 152, 0.28) !important;\n        }\n        .vpro-picker-table table.dataTable tbody tr.selected td {\n          background: linear-gradient(180deg, #355f98 0%, #2b4f7f 100%) !important;\n          border-color: #2b4f7f !important;\n          color: #ffffff !important;\n          transform: translateY(-1px);\n        }\n        .vpro-picker-table .dataTables_scrollBody {\n          background: transparent;\n          border: none !important;\n        }\n        .vpro-picker-table .dataTables_scrollBody::-webkit-scrollbar {\n          width: 8px;\n        }\n        .vpro-picker-table .dataTables_scrollBody::-webkit-scrollbar-thumb {\n          background: rgba(53, 95, 152, 0.22);\n          border-radius: 999px;\n        }\n        @media (max-width: 991.98px) {\n          .vpro-nav-context {\n            gap: 0.5rem;\n            padding: 0.22rem 0.5rem;\n            font-size: 0.7rem;\n          }\n          .vpro-nav-context-value {\n            max-width: 5.75rem;\n          }\n          .vpro-picker-table table.dataTable tbody td {\n            padding: 0.62rem 0.55rem !important;\n          }\n        }\n      "))
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
