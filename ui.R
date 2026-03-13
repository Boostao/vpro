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
        tags$style(HTML("\n        .vpro-navbar-title {\n          color: #ffffff;\n          line-height: 1;\n          margin-top: 0;\n          margin-bottom: 0;\n        }\n        .vpro-navbar-subtitle {\n          color: #d9ecff;\n          font-size: 0.78rem;\n          margin-left: 2px;\n        }\n        .navbar .navbar-brand {\n          display: flex;\n          align-items: center;\n          padding-top: 0;\n          padding-bottom: 0;\n          min-height: 32px;\n        }\n        .vpro-sidebar {\n          padding-top: 0.15rem;\n        }\n        .vpro-nav-context {\n          display: flex;\n          align-items: center;\n          gap: 0.75rem;\n          padding: 0.3rem 0.7rem;\n          border-radius: 999px;\n          background: rgba(255, 255, 255, 0.14);\n          border: 1px solid rgba(255, 255, 255, 0.18);\n          color: #ffffff;\n          font-size: 0.76rem;\n          line-height: 1.05;\n          white-space: nowrap;\n        }\n        .vpro-nav-context-item {\n          display: flex;\n          flex-direction: column;\n          min-width: 0;\n        }\n        .vpro-nav-context-label {\n          color: rgba(255, 255, 255, 0.74);\n          font-size: 0.63rem;\n          letter-spacing: 0.04em;\n          text-transform: uppercase;\n        }\n        .vpro-nav-context-value {\n          max-width: 9rem;\n          overflow: hidden;\n          text-overflow: ellipsis;\n          font-weight: 600;\n        }\n        .vpro-nav-context-sep {\n          width: 1px;\n          align-self: stretch;\n          background: rgba(255, 255, 255, 0.18);\n        }\n        .vpro-sidebar .form-group,\n        .vpro-sidebar .shiny-input-container {\n          margin-bottom: 0.45rem;\n        }\n        .vpro-sidebar .btn {\n          padding-top: 0.22rem;\n          padding-bottom: 0.22rem;\n          font-size: 0.82rem;\n        }\n        .vpro-sidebar .vpro-section-title {\n          margin-top: 0.35rem;\n          margin-bottom: 0.35rem;\n          font-size: 0.82rem;\n          font-weight: 600;\n          color: #355f98;\n        }\n        .vpro-picker-card {\n          border: 1px solid rgba(53, 95, 152, 0.16);\n        }\n        .vpro-picker-card .card-header {\n          background: linear-gradient(135deg, rgba(214, 233, 255, 0.95), rgba(244, 249, 255, 0.96));\n          border-bottom: 1px solid rgba(53, 95, 152, 0.12);\n        }\n        .vpro-picker-table .dataTables_wrapper .dataTables_filter,\n        .vpro-picker-table .dataTables_wrapper .dataTables_info,\n        .vpro-picker-table .dataTables_wrapper .dataTables_length,\n        .vpro-picker-table .dataTables_wrapper .dataTables_paginate {\n          display: none;\n        }\n        .vpro-picker-table table.dataTable {\n          border-collapse: separate !important;\n          border-spacing: 0 0.45rem;\n          background: transparent;\n          margin-top: -0.45rem !important;\n        }\n        .vpro-picker-table table.dataTable thead {\n          display: none;\n        }\n        .vpro-picker-table table.dataTable tbody tr {\n          background: transparent;\n        }\n        .vpro-picker-table table.dataTable tbody td {\n          text-align: center;\n          border: 1px solid rgba(53, 95, 152, 0.14) !important;\n          border-radius: 0.35rem;\n          background: #f7fbff !important;\n          color: #21456d !important;\n          font-weight: 600;\n          letter-spacing: 0.01em;\n          padding: 0.68rem 0.75rem !important;\n          cursor: pointer;\n          transition: transform 0.14s ease, background 0.14s ease, border-color 0.14s ease;\n        }\n        .vpro-picker-table table.dataTable tbody tr:hover td {\n          transform: translateY(-1px);\n          background: #edf5ff !important;\n          border-color: rgba(53, 95, 152, 0.28) !important;\n        }\n        .vpro-picker-table table.dataTable tbody tr.selected td {\n          background: #355f98 !important;\n          border-color: #2b4f7f !important;\n          color: #ffffff !important;\n          transform: translateY(-1px);\n        }\n        .vpro-picker-table .dataTables_scrollBody {\n          background: transparent;\n          border: none !important;\n        }\n        .vpro-picker-table .dataTables_scrollBody::-webkit-scrollbar {\n          width: 8px;\n        }\n        .vpro-picker-table .dataTables_scrollBody::-webkit-scrollbar-thumb {\n          background: rgba(53, 95, 152, 0.22);\n          border-radius: 999px;\n        }\n        .vpro-hierarchy-card .card-body {\n          padding-top: 0.85rem;\n        }\n        .vpro-hierarchy-workbench {\n          display: flex;\n          flex-direction: column;\n          gap: 0.85rem;\n        }\n        .vpro-hierarchy-tree-shell {\n          border: 1px solid rgba(53, 95, 152, 0.12);\n          border-radius: 0.9rem;\n          background: linear-gradient(180deg, rgba(248, 251, 255, 0.98), rgba(240, 247, 255, 0.98));\n          padding: 0.55rem;\n          max-height: 22rem;\n          overflow: auto;\n        }\n        .vpro-hierarchy-tree {\n          display: flex;\n          flex-direction: column;\n          gap: 0.34rem;\n        }\n        .vpro-hierarchy-node {\n          --hierarchy-depth: 0;\n          display: block;\n          border-radius: 0.8rem;\n          padding: 0.5rem 0.7rem 0.5rem calc(0.7rem + (var(--hierarchy-depth) * 0.85rem));\n          color: #35516f;\n          background: rgba(255, 255, 255, 0.58);\n          border: 1px solid transparent;\n          transition: background 0.14s ease, border-color 0.14s ease, transform 0.14s ease, box-shadow 0.14s ease;\n        }\n        .vpro-hierarchy-node.is-site-unit {\n          cursor: pointer;\n          background: rgba(255, 255, 255, 0.9);\n          border-color: rgba(53, 95, 152, 0.1);\n        }\n        .vpro-hierarchy-node.is-site-unit:hover {\n          transform: translateY(-1px);\n          border-color: rgba(53, 95, 152, 0.28);\n          box-shadow: 0 10px 22px rgba(28, 72, 122, 0.08);\n        }\n        .vpro-hierarchy-node.is-active {\n          background: linear-gradient(135deg, #355f98, #4d78b2);\n          border-color: #2b4f7f;\n          color: #ffffff;\n          box-shadow: 0 14px 28px rgba(35, 76, 122, 0.2);\n        }\n        .vpro-hierarchy-node.is-over {\n          border-color: #0f8b6f;\n          background: linear-gradient(135deg, rgba(224, 255, 247, 0.98), rgba(205, 244, 233, 0.98));\n          box-shadow: 0 0 0 2px rgba(15, 139, 111, 0.12);\n        }\n        .vpro-hierarchy-node-main {\n          display: flex;\n          align-items: center;\n          justify-content: space-between;\n          gap: 0.65rem;\n        }\n        .vpro-hierarchy-node-label {\n          min-width: 0;\n          font-size: 0.86rem;\n          line-height: 1.2;\n          font-weight: 600;\n          word-break: break-word;\n        }\n        .vpro-hierarchy-node-count {\n          flex: 0 0 auto;\n          min-width: 1.9rem;\n          padding: 0.18rem 0.52rem;\n          border-radius: 999px;\n          background: rgba(53, 95, 152, 0.12);\n          color: #21456d;\n          font-size: 0.72rem;\n          font-weight: 700;\n          text-align: center;\n        }\n        .vpro-hierarchy-node.is-active .vpro-hierarchy-node-count {\n          background: rgba(255, 255, 255, 0.18);\n          color: #ffffff;\n        }\n        .vpro-hierarchy-plot-panel {\n          border: 1px solid rgba(53, 95, 152, 0.12);\n          border-radius: 0.95rem;\n          background: #ffffff;\n          min-height: 10rem;\n        }\n        .vpro-hierarchy-plot-shell {\n          padding: 0.9rem 0.95rem 0.95rem;\n        }\n        .vpro-hierarchy-plot-header {\n          display: flex;\n          align-items: baseline;\n          justify-content: space-between;\n          gap: 0.6rem;\n          margin-bottom: 0.45rem;\n        }\n        .vpro-hierarchy-plot-title {\n          font-size: 0.92rem;\n          font-weight: 700;\n          color: #21456d;\n        }\n        .vpro-hierarchy-plot-subtitle,\n        .vpro-hierarchy-plot-instruction,\n        .vpro-hierarchy-status {\n          font-size: 0.76rem;\n          color: #5d7591;\n        }\n        .vpro-hierarchy-plot-instruction {\n          margin-bottom: 0.65rem;\n        }\n        .vpro-hierarchy-plot-list {\n          display: flex;\n          flex-wrap: wrap;\n          gap: 0.5rem;\n        }\n        .vpro-hierarchy-plot-chip {\n          display: inline-flex;\n          align-items: center;\n          justify-content: center;\n          min-height: 2rem;\n          padding: 0.45rem 0.72rem;\n          border-radius: 999px;\n          background: linear-gradient(135deg, #edf5ff, #f7fbff);\n          border: 1px solid rgba(53, 95, 152, 0.16);\n          color: #21456d;\n          font-size: 0.79rem;\n          font-weight: 700;\n          letter-spacing: 0.01em;\n          cursor: pointer;\n          user-select: none;\n          transition: transform 0.14s ease, box-shadow 0.14s ease, border-color 0.14s ease;\n        }\n        .vpro-hierarchy-plot-chip:hover {\n          transform: translateY(-1px);\n          border-color: rgba(53, 95, 152, 0.3);\n          box-shadow: 0 10px 18px rgba(33, 69, 109, 0.08);\n        }\n        .vpro-hierarchy-plot-chip.is-current {\n          background: linear-gradient(135deg, #355f98, #4d78b2);\n          border-color: #2b4f7f;\n          color: #ffffff;\n        }\n        .vpro-hierarchy-plot-chip.is-dragging {\n          opacity: 0.45;\n          transform: scale(0.96);\n          box-shadow: none;\n        }\n        .vpro-hierarchy-empty {\n          padding: 0.8rem 0.25rem;\n          color: #6a8099;\n          font-size: 0.8rem;\n        }\n        @media (max-width: 991.98px) {\n          .vpro-nav-context {\n            gap: 0.5rem;\n            padding: 0.22rem 0.5rem;\n            font-size: 0.7rem;\n          }\n          .vpro-nav-context-value {\n            max-width: 5.75rem;\n          }\n          .vpro-picker-table table.dataTable tbody td {\n            padding: 0.62rem 0.55rem !important;\n          }\n          .vpro-hierarchy-tree-shell {\n            max-height: 18rem;\n          }\n          .vpro-hierarchy-node {\n            padding-right: 0.55rem;\n          }\n        }\n      "))
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
