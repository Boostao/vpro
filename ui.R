# UI Definition
# Uses bslib for a modern dashboard layout replacing the Access Menu

if (!"bcgov" %in% bslib::bootswatch_themes()) {
  source("theme/add_bcgov_bootswatch_to_bslib.R")
}

npt<-function(i=NULL,l,t,v=t){nav_panel(tooltip(span(if(!is.null(i)){icon(i)},l),t),value=v)}

ui <- page_navbar(
  id = "main_tabs",
  title = div(
    class = "d-flex align-items-center gap-2 vpro-navbar-title",
    icon("seedling"),
    span("VPro", class = "fw-bold")
  ),
  theme = bs_theme(version = 5, bootswatch = "bcgov"),
  header = tagList(
      tags$head(
        tags$style(HTML("\n        .vpro-navbar-title {\n          color: #ffffff;\n          line-height: 1;\n          margin-top: 0;\n          margin-bottom: 0;\n        }\n        .navbar .navbar-brand {\n          display: flex;\n          align-items: center;\n          padding-top: 0;\n          padding-bottom: 0;\n          min-height: 32px;\n        }\n        .vpro-sidebar {\n          padding-top: 0.15rem;\n        }\n        .vpro-nav-context {\n          display: flex;\n          align-items: center;\n          gap: 0.75rem;\n          padding: 0.3rem 0.7rem;\n          border-radius: 999px;\n          background: rgba(255, 255, 255, 0.14);\n          border: 1px solid rgba(255, 255, 255, 0.18);\n          color: #ffffff;\n          font-size: 0.76rem;\n          line-height: 1.05;\n          white-space: nowrap;\n        }\n        .vpro-nav-context-item {\n          display: flex;\n          flex-direction: column;\n          min-width: 0;\n        }\n        .vpro-nav-context-label {\n          color: rgba(255, 255, 255, 0.74);\n          font-size: 0.63rem;\n          letter-spacing: 0.04em;\n          text-transform: uppercase;\n        }\n        .vpro-nav-context-value {\n          max-width: 9rem;\n          overflow: hidden;\n          text-overflow: ellipsis;\n          font-weight: 600;\n        }\n        .vpro-nav-context-sep {\n          width: 1px;\n          align-self: stretch;\n          background: rgba(255, 255, 255, 0.18);\n        }\n        .vpro-sidebar .form-group,\n        .vpro-sidebar .shiny-input-container {\n          margin-bottom: 0.45rem;\n        }\n        .vpro-sidebar .btn {\n          padding-top: 0.22rem;\n          padding-bottom: 0.22rem;\n          font-size: 0.82rem;\n        }\n        .vpro-sidebar .vpro-section-title {\n          margin-top: 0.35rem;\n          margin-bottom: 0.35rem;\n          font-size: 0.82rem;\n          font-weight: 600;\n          color: #355f98;\n        }\n        .vpro-picker-card {\n          border: 1px solid rgba(53, 95, 152, 0.16);\n        }\n        .vpro-picker-card .card-header {\n          background: linear-gradient(135deg, rgba(214, 233, 255, 0.95), rgba(244, 249, 255, 0.96));\n          border-bottom: 1px solid rgba(53, 95, 152, 0.12);\n        }\n        .vpro-picker-table .dataTables_wrapper .dataTables_filter,\n        .vpro-picker-table .dataTables_wrapper .dataTables_info,\n        .vpro-picker-table .dataTables_wrapper .dataTables_length,\n        .vpro-picker-table .dataTables_wrapper .dataTables_paginate {\n          display: none;\n        }\n        .vpro-picker-table table.dataTable {\n          border-collapse: separate !important;\n          border-spacing: 0 0.45rem;\n          background: transparent;\n          margin-top: -0.45rem !important;\n        }\n        .vpro-picker-table table.dataTable thead {\n          display: none;\n        }\n        .vpro-picker-table table.dataTable tbody tr {\n          background: transparent;\n        }\n        .vpro-picker-table table.dataTable tbody td {\n          text-align: center;\n          border: 1px solid rgba(53, 95, 152, 0.14) !important;\n          border-radius: 0.35rem;\n          background: #f7fbff !important;\n          color: #21456d !important;\n          font-weight: 600;\n          letter-spacing: 0.01em;\n          padding: 0.68rem 0.75rem !important;\n          cursor: pointer;\n          transition: transform 0.14s ease, background 0.14s ease, border-color 0.14s ease;\n        }\n        .vpro-picker-table table.dataTable tbody tr:hover td {\n          transform: translateY(-1px);\n          background: #edf5ff !important;\n          border-color: rgba(53, 95, 152, 0.28) !important;\n        }\n        .vpro-picker-table table.dataTable tbody tr.selected td {\n          background: #355f98 !important;\n          border-color: #2b4f7f !important;\n          color: #ffffff !important;\n          transform: translateY(-1px);\n        }\n        .vpro-picker-table .dataTables_scrollBody {\n          background: transparent;\n          border: none !important;\n        }\n        .vpro-picker-table .dataTables_scrollBody::-webkit-scrollbar {\n          width: 8px;\n        }\n        .vpro-picker-table .dataTables_scrollBody::-webkit-scrollbar-thumb {\n          background: rgba(53, 95, 152, 0.22);\n          border-radius: 999px;\n        }\n        .vpro-hierarchy-card .card-body {\n          padding-top: 0.85rem;\n        }\n        .vpro-hierarchy-workbench {\n          display: flex;\n          flex-direction: column;\n          gap: 0.85rem;\n        }\n        .vpro-hierarchy-tree-shell {\n          border: 1px solid rgba(53, 95, 152, 0.12);\n          border-radius: 0.9rem;\n          background: linear-gradient(180deg, rgba(248, 251, 255, 0.98), rgba(240, 247, 255, 0.98));\n          padding: 0.55rem;\n          max-height: 22rem;\n          overflow: auto;\n        }\n        .vpro-hierarchy-tree {\n          display: flex;\n          flex-direction: column;\n          gap: 0.34rem;\n        }\n        .vpro-hierarchy-node {\n          --hierarchy-depth: 0;\n          display: block;\n          border-radius: 0.8rem;\n          padding: 0.5rem 0.7rem 0.5rem calc(0.7rem + (var(--hierarchy-depth) * 0.85rem));\n          color: #35516f;\n          background: rgba(255, 255, 255, 0.58);\n          border: 1px solid transparent;\n          transition: background 0.14s ease, border-color 0.14s ease, transform 0.14s ease, box-shadow 0.14s ease;\n        }\n        .vpro-hierarchy-node.is-site-unit {\n          cursor: pointer;\n          background: rgba(255, 255, 255, 0.9);\n          border-color: rgba(53, 95, 152, 0.1);\n        }\n        .vpro-hierarchy-node.is-site-unit:hover {\n          transform: translateY(-1px);\n          border-color: rgba(53, 95, 152, 0.28);\n          box-shadow: 0 10px 22px rgba(28, 72, 122, 0.08);\n        }\n        .vpro-hierarchy-node.is-active {\n          background: linear-gradient(135deg, #355f98, #4d78b2);\n          border-color: #2b4f7f;\n          color: #ffffff;\n          box-shadow: 0 14px 28px rgba(35, 76, 122, 0.2);\n        }\n        .vpro-hierarchy-node.is-over {\n          border-color: #0f8b6f;\n          background: linear-gradient(135deg, rgba(224, 255, 247, 0.98), rgba(205, 244, 233, 0.98));\n          box-shadow: 0 0 0 2px rgba(15, 139, 111, 0.12);\n        }\n        .vpro-hierarchy-node-main {\n          display: flex;\n          align-items: center;\n          justify-content: space-between;\n          gap: 0.65rem;\n        }\n        .vpro-hierarchy-node-label {\n          min-width: 0;\n          font-size: 0.86rem;\n          line-height: 1.2;\n          font-weight: 600;\n          word-break: break-word;\n        }\n        .vpro-hierarchy-node-count {\n          flex: 0 0 auto;\n          min-width: 1.9rem;\n          padding: 0.18rem 0.52rem;\n          border-radius: 999px;\n          background: rgba(53, 95, 152, 0.12);\n          color: #21456d;\n          font-size: 0.72rem;\n          font-weight: 700;\n          text-align: center;\n        }\n        .vpro-hierarchy-node.is-active .vpro-hierarchy-node-count {\n          background: rgba(255, 255, 255, 0.18);\n          color: #ffffff;\n        }\n        .vpro-hierarchy-plot-panel {\n          border: 1px solid rgba(53, 95, 152, 0.12);\n          border-radius: 0.95rem;\n          background: #ffffff;\n          min-height: 10rem;\n        }\n        .vpro-hierarchy-plot-shell {\n          padding: 0.9rem 0.95rem 0.95rem;\n        }\n        .vpro-hierarchy-plot-header {\n          display: flex;\n          align-items: baseline;\n          justify-content: space-between;\n          gap: 0.6rem;\n          margin-bottom: 0.45rem;\n        }\n        .vpro-hierarchy-plot-title {\n          font-size: 0.92rem;\n          font-weight: 700;\n          color: #21456d;\n        }\n        .vpro-hierarchy-plot-subtitle,\n        .vpro-hierarchy-plot-instruction,\n        .vpro-hierarchy-status {\n          font-size: 0.76rem;\n          color: #5d7591;\n        }\n        .vpro-hierarchy-plot-instruction {\n          margin-bottom: 0.65rem;\n        }\n        .vpro-hierarchy-plot-list {\n          display: flex;\n          flex-wrap: wrap;\n          gap: 0.5rem;\n        }\n        .vpro-hierarchy-plot-chip {\n          display: inline-flex;\n          align-items: center;\n          justify-content: center;\n          min-height: 2rem;\n          padding: 0.45rem 0.72rem;\n          border-radius: 999px;\n          background: linear-gradient(135deg, #edf5ff, #f7fbff);\n          border: 1px solid rgba(53, 95, 152, 0.16);\n          color: #21456d;\n          font-size: 0.79rem;\n          font-weight: 700;\n          letter-spacing: 0.01em;\n          cursor: pointer;\n          user-select: none;\n          transition: transform 0.14s ease, box-shadow 0.14s ease, border-color 0.14s ease;\n        }\n        .vpro-hierarchy-plot-chip:hover {\n          transform: translateY(-1px);\n          border-color: rgba(53, 95, 152, 0.3);\n          box-shadow: 0 10px 18px rgba(33, 69, 109, 0.08);\n        }\n        .vpro-hierarchy-plot-chip.is-current {\n          background: linear-gradient(135deg, #355f98, #4d78b2);\n          border-color: #2b4f7f;\n          color: #ffffff;\n        }\n        .vpro-hierarchy-plot-chip.is-dragging {\n          opacity: 0.45;\n          transform: scale(0.96);\n          box-shadow: none;\n        }\n        .vpro-hierarchy-empty {\n          padding: 0.8rem 0.25rem;\n          color: #6a8099;\n          font-size: 0.8rem;\n        }\n        @media (max-width: 991.98px) {\n          .vpro-nav-context {\n            gap: 0.5rem;\n            padding: 0.22rem 0.5rem;\n            font-size: 0.7rem;\n          }\n          .vpro-nav-context-value {\n            max-width: 5.75rem;\n          }\n          .vpro-picker-table table.dataTable tbody td {\n            padding: 0.62rem 0.55rem !important;\n          }\n          .vpro-hierarchy-tree-shell {\n            max-height: 18rem;\n          }\n          .vpro-hierarchy-node {\n            padding-right: 0.55rem;\n          }\n        }\n      "))
      ),
    shinyjs::useShinyjs(),
    tags$script(HTML("(function(){\n  function shouldIgnoreKey(evt){\n    var tag = (evt.target && evt.target.tagName) ? evt.target.tagName.toLowerCase() : '';\n    return tag === 'input' || tag === 'textarea' || evt.target.isContentEditable;\n  }\n\n  document.addEventListener('keydown', function(e){\n    var key = (e.key || '').toLowerCase();\n    if ((e.ctrlKey || e.metaKey) && key === 's') {\n      e.preventDefault();\n      Shiny.setInputValue('global_save', Date.now());\n      return;\n    }\n    if ((e.ctrlKey || e.metaKey) && key === 'n') {\n      e.preventDefault();\n      Shiny.setInputValue('global_new', Date.now());\n      return;\n    }\n    if (shouldIgnoreKey(e)) return;\n  });\n})();"))
    ,
    tags$script(HTML("(function(){\n  var dragPayload = null;\n  var draggingPlot = false;\n\n  function elementFromEventTarget(target){\n    if (!target) return null;\n    if (target.nodeType === Node.TEXT_NODE) return target.parentElement;\n    return target instanceof Element ? target : null;\n  }\n\n  function closestFromEventTarget(target, selector){\n    var element = elementFromEventTarget(target);\n    return element ? element.closest(selector) : null;\n  }\n\n  function clearDropTargets(){\n    document.querySelectorAll('.vpro-hierarchy-drop-target.is-over').forEach(function(node){\n      node.classList.remove('is-over');\n    });\n  }\n\n  document.addEventListener('dragstart', function(event){\n    var chip = closestFromEventTarget(event.target, '.vpro-hierarchy-plot-chip');\n    if (!chip) return;\n\n    dragPayload = {\n      plot_number: chip.dataset.plotNumber || '',\n      from_site_unit: chip.dataset.siteUnit || ''\n    };\n    draggingPlot = true;\n    chip.classList.add('is-dragging');\n\n    if (event.dataTransfer) {\n      event.dataTransfer.effectAllowed = 'move';\n      event.dataTransfer.setData('text/plain', JSON.stringify(dragPayload));\n    }\n  });\n\n  document.addEventListener('dragend', function(event){\n    var chip = closestFromEventTarget(event.target, '.vpro-hierarchy-plot-chip');\n    if (chip) chip.classList.remove('is-dragging');\n    clearDropTargets();\n    window.setTimeout(function(){\n      draggingPlot = false;\n      dragPayload = null;\n    }, 0);\n  });\n\n  document.addEventListener('dragover', function(event){\n    var target = closestFromEventTarget(event.target, '.vpro-hierarchy-drop-target');\n    if (!target) return;\n    event.preventDefault();\n    clearDropTargets();\n    target.classList.add('is-over');\n    if (event.dataTransfer) {\n      event.dataTransfer.dropEffect = 'move';\n    }\n  });\n\n  document.addEventListener('drop', function(event){\n    var target = closestFromEventTarget(event.target, '.vpro-hierarchy-drop-target');\n    if (!target) return;\n    event.preventDefault();\n\n    var payload = dragPayload;\n    if (!payload && event.dataTransfer) {\n      try {\n        payload = JSON.parse(event.dataTransfer.getData('text/plain') || '{}');\n      } catch (err) {\n        payload = null;\n      }\n    }\n\n    clearDropTargets();\n\n    if (!payload || !payload.plot_number || !target.dataset.siteUnit) return;\n\n    Shiny.setInputValue('hierarchy_sidebar_drop', {\n      plot_number: payload.plot_number,\n      from_site_unit: payload.from_site_unit || '',\n      to_site_unit: target.dataset.siteUnit,\n      nonce: Date.now()\n    }, {priority: 'event'});\n  });\n\n  document.addEventListener('click', function(event){\n    var chip = closestFromEventTarget(event.target, '.vpro-hierarchy-plot-chip');\n    if (chip) {\n      if (draggingPlot) return;\n      Shiny.setInputValue('hierarchy_sidebar_select_plot', {\n        plot_number: chip.dataset.plotNumber || '',\n        site_unit: chip.dataset.siteUnit || '',\n        nonce: Date.now()\n      }, {priority: 'event'});\n      return;\n    }\n\n    var node = closestFromEventTarget(event.target, '.vpro-hierarchy-node.is-site-unit');\n    if (!node) return;\n    Shiny.setInputValue('hierarchy_sidebar_select_site_unit', {\n      site_unit: node.dataset.siteUnit || '',\n      nonce: Date.now()\n    }, {priority: 'event'});\n  });\n\n  document.addEventListener('keydown', function(event){\n    var node = closestFromEventTarget(event.target, '.vpro-hierarchy-node.is-site-unit');\n    if (!node) return;\n    if (event.key !== 'Enter' && event.key !== ' ') return;\n    event.preventDefault();\n    Shiny.setInputValue('hierarchy_sidebar_select_site_unit', {\n      site_unit: node.dataset.siteUnit || '',\n      nonce: Date.now()\n    }, {priority: 'event'});\n  });\n})();"))
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



  # Placeholder for future UI refactoring
  nav_menu("Forms",
    "Data Entry",
    npt("rectangle-list", "FS882 Data Forms", "This is the data form that most closely resembles the FS882 field forms.","fs882"),
    npt("campground", "Enter/Edit SIVI Data", "SIVI and FS882 share a common data structure, but this form most closely resembles FS1333","fs1333"),
    "---",
    "Others",
    npt("table-cells", "Metadata", "Add/edit metadata","metadata"),
    npt("link", "Combine Species", "Here you can manage your combined (lumped) species tables.","combine_species"),
    npt("leaf", "Herbarium", "Have some herbarium data you want to manage?  Click here.","herbarium"),
    npt("palette", "Colour-theme", "In VPro, some of the output is thematic.  Here you can manage your theme colours and relate them to specific species.","colour_theme"),
    npt("user-gear", "User setup", "Revenue Canada on your tail?  Click here to change your name.  (We all know that VPro is the first place they will look for you)","user_setup"),
    npt("clock-rotate-left", "User log", "A record of when you (or someone else) opens and closes VPro.  Nothing spectacular, but useful just the same.","user_log")
  ),
  nav_menu("Data",
    "Project",
    npt("folder-plus", "New Project", "Create a new project.  A project stores your environment, vegetation and soil data.","project_new"),
    npt("floppy-disk", "Save As...", "Save the current project to a new or existing database using a different name.","project_save_as"),
    npt("box-archive", "Backup Current Project", "This tool creates a copy of the current project adding the prefix \"BAK\" to the project name.","project_backup"),
    npt("share-nodes", "Export Splinter Project", "A splinter project is the portion of the current project that has matching plots in the current SU table.","project_export_splinter"),
    npt("diagram-project", "Merge Projects", "Combine the plots of two projects.  Remember to backup your data before performing these types of functions.","project_merge"),
    npt("not-equal", "Compare Two Projects", "This tool compares site, soil, and vegetation data plot-by-plot and field-by-field, then produces an Excel report.","project_compare"),
    npt("table-cells", "Project Metadata", "Add/edit project metadata here.  It is suggested that you maintain project metadata for each of your projects.","project_metadata"),
    npt("file-export", "Export Project Metadata", "Use this tool to export your metadata to a database for distribution.","project_metadata_export"),
    npt("file-import", "Import Project Metadata", "Import project metadata into your current metadata table.  Remember that the Project ID field must be unique.","project_metadata_import"),
    "---",
    "Site Unit",
    npt("table", "New Site Unit Table", "A site unit table is used to assign plots to groups.  It also functions as a filter limiting the number of active project plots.","su_table_new"),
    npt("floppy-disk", "Save As...", "Save the current site unit table to a new or existing database using a different name.","su_table_save_as"),
    npt("box-archive", "Backup The Current Site Unit Table", "Adds the prefix \"BAK\" to the site unit table name and saves it to a new database.","su_table_backup"),
    npt("scissors", "SU Table From Breaks", "Create an SU table from site units found below breakpoints in the current hierarchy.","su_table_from_breaks"),
    npt("filter", "SU Table From Filter Query", "Uses a filter query to select plots from the current project and save them as a site unit table.  Unit assignments from current SU table are optional.","su_table_from_query"),
    npt("sliders", "SU Table From Form Filter", "Using a Microsoft Access form filter, you can generate a SU table based on the selected plots.","su_table_from_form_filter"),
    npt("wand-magic", "Create Site Units From Environment Fields", "Uses concatenation to build unit names from environment field data.  The result is a new SU table.","su_table_from_environment"),
    npt("arrows-left-right", "Compare Plot Assignments", "Compare plot assignments between two site unit tables and generate an Excel report of the comparison.","su_table_compare_assignments"),
    npt("list-ul", "List Site Units With Plots", "Generates a list of current site units, their long names, number of plots, and a list of plot numbers.","su_table_list_units_with_plots"),
    npt("pen-to-square", "Write BEC Master into SU Table", "Copies the currently assigned BEC Master unit into the current Site Unit table replacing current unit assignments except where there does not exist a BEC Master unit assignment.","su_table_write_bec_master"),
    "---",
    "Hierarchy",
    npt("sitemap", "New Hierarchy Table", "A hierarchy table is a hierarchical construct of classification levels.  Use this function to create a new hierarchy table in a new or existing database.","hierarchy_new"),
    npt("floppy-disk", "Save As...", "Save the current hierarchy table to a new or existing database using a different name.","hierarchy_save_as"),
    npt("box-archive", "Backup Current Hierarchy Table", "Adds the prefix \"BAK\" to the current hierarchy table name and saves it to a new database.","hierarchy_backup"),
    npt("code-branch", "Save Hierarchy Under Breaks", "Save the portion(s) of the current hierarchy that fall under breakpoints.","hierarchy_save_under_breaks"),
    npt("diagram-project", "Merge Hierarchies", "Please backup first.  Hierarchies can be complex tables so there's a lot than can go wrong.  That said, use this tool to combine two hierarchies.","hierarchy_merge"),
    npt("diagram-project", "Hierarchy Diagram", "Creates a diagram of the current hierarchy in Excel.  Includes a feature to help isolate orphaned hierarchy members.","hierarchy_diagram"),
    "---",
    "Import",
    npt("database", "VPro 15 Project", "Import a VPro 15 project.","import_vpro_15_project"),
    npt("database", "VPro 13 Project", "Import a VPro 13 project.","import_vpro_13_project"),
    npt("mobile-screen-button", "FileMaker Go", "Import FileMaker Go data.","import_filemaker_go"),
    npt("table", "VPro User Site Units", "Import a VPro user site units table.","import_vpro_user_site_units"),
    npt("seedling", "VPro User Species List", "Import a VPro user species list.","import_vpro_user_species_list"),
    npt("book", "VPro Master Species List", "Import the VPro master species list.","import_vpro_master_species_list"),
    npt("table-list", "VPro Master List Table", "Import the VPro master list table.","import_vpro_master_list_table"),
    npt("globe", "VENUS 4.2", "Import VENUS 4.2 data.","import_venus_4_2"),
    npt("globe", "VENUS 5.0", "Import VENUS 5.0 data.","import_venus_5_0"),
    "---",
    "Export",
    npt("database", "VPro 15 Project", "Export the current project as a VPro 15 project.","export_vpro_15_project"),
    npt("database", "VPro 13 Project", "Export the current project as a VPro 13 project.","export_vpro_13_project"),
    npt("table-columns", "PC-ORD Compact Veg Form", "Export the PC-ORD compact vegetation form.","export_pc_ord_compact_veg_form"),
    npt("table-cells-large", "PC-ORD Environment Matrix", "Export the PC-ORD environment matrix.","export_pc_ord_environment_matrix"),
    npt("file-code", "Export to R", "Export the current dataset for use in R.","export_to_r"),
    npt("seedling", "User Species List", "Export the current user species list.","export_user_species_list"),
    npt("table", "User Site Units", "Export the current user site units.","export_user_site_units"),
    npt("file-csv", "Export Level Units CSV", "Export level units to CSV.","export_level_units_csv"),
    "---",
    "Validate",
    npt("clipboard-check", "Validate Data", "Here's an assortment of tools to validate and fix some common problems","validate_data")
  ),
  nav_menu("Reports",
    "Vegetation",
    npt("table-list", "Long Vegetation", "Creates an Excel report where, optionally, unit groups of plots are placed on individual sheets.","report_long_vegetation"),
    npt("chart-column", "Summary Vegetation", "Creates an Excel report where, optionally, unit groups of plots are placed on individual sheets.","report_summary_vegetation"),
    npt("leaf", "Species Attributes Report", "Summarizes species attributes by site unit or hierarchy breakpoint.","report_species_attributes"),
    "---",
    "Environment",
    npt("table-list", "Long Environment", "Creates an Excel report where site unit groups of plots are placed on individual sheets.","report_long_environment"),
    npt("chart-column", "Summary Environment", "A summary of plots in each site unit is generated for the project.  Frequency for the qualitative values and mean or median values of the quantitative values are displayed.","report_summary_environment"),
    npt("table-columns", "Combination Vegtation/Environment", "A user configurable combination of environment and vegetation data is reported for each plot.","report_combination_vegetation_environment"),
    "---",
    "Others",
    npt("triangle-exclamation", "PC-ORD Break Report", "A list of break codes generated by the last export of PC-ORD data.","report_pc_ord_breaks"),
    npt("table-cells-large", "Subzone Matrix of Units", "A matrix is generated based on the current site unit table and the master site unit list.","report_subzone_matrix_of_units"),
    npt("diagram-project", "Hierarchy Diagram", "Creates a diagram of the current hierarchy in Excel.  Includes a feature to help isolate orphaned hierarchy members.","report_hierarchy_diagram"),
    npt("tag", "Print a Plot Label", "Print a physical label to affix to your plot card.","report_print_plot_label"),
    npt("file-lines", "Create Plot Locations File", "Prints a plot list that includes zone, subzone, site series, longitude, latitude and elevation.","report_create_plot_locations_file"),
    npt("earth-americas", "Show Plot Locations in Google Earth", "Locate your plots using Google Earth (requires Google Earth installation)","report_show_plot_locations_google_earth")
  ),
  nav_menu("References",
    "Library Tables",
    npt("list-check", "Site and Environment Codes", "This tool allows the user to modify the drop-down lists in the data forms.  Please do not make any changes to these lists if you are working with BEC data!","reference_site_environment_codes"),
    npt("book-open", "Species Name and Codes Table", "Forms, reports, and import/export tools use this table to standardize data input and translate codes into scientific and common names.","reference_species_name_codes"),
    "---",
    "User Setup",
    npt("link", "Attach species table", "You can attach a different USysAllSpecs table if you wish.  We will assume you understand the implications involved.  When in doubt ask Will MacKenzie!","reference_attach_species_table"),
    npt("paperclip", "Attach code list table", "VPro uses codes to store many of the data items.  These codes and their descriptions are stored in an attached table named USysTableOfLists.  Click to start the procedure to attach a different table.","reference_attach_code_list_table"),
    npt("palette", "Colour-theme", "In VPro, some of the output is thematic.  Here you can manage your theme colours and relate them to specific species.","reference_colour_theme"),
    npt("user-gear", "User setup", "Revenue Canada on your tail?  Click here to change your name.  (We all know that VPro is the first place they will look for you)","reference_user_setup"),
    npt("folder-tree", "Directories", "Setup directory locations for files related to Google Earth, R, and plot photos.","reference_directories")
  ),
  nav_menu("Help",
    "Help",
    npt("circle-question", "VPro Help", "Documents and Web links.","help_vpro_help"),
    npt("boxes-stacked", "VPro Service Packs", "Information on the VPro service packs installed on this machine.","help_service_packs"),
    npt("rotate-left", "Set all to Sample", "Problems with the menu?  Can't change projects?  Getting an error message?  Try this.","help_set_all_to_sample"),
    npt("rectangle-xmark", "Close all forms", "Suspect you may have a hidden form that is causing you problems?  Click this and your worries are over.","help_close_all_forms"),
    npt("newspaper", "What's New", "See a list of the latest changes to VPro.","help_whats_new"),
    npt("circle-info", "About VPro", "Some basic information about your copy of VPro.","help_about_vpro")
  ),
  
  nav_menu(tagList(icon("cubes"), "Modules"),
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
    )
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
