# UI Definition
# Uses bslib for a modern dashboard layout replacing the Access Menu
npt <- function(icon = NULL, label, tip, value, mod = NULL) {
  nav_panel(
    title = tooltip(
      span(
        if (!is.null(icon)) {
          shiny::icon(icon)
        },
        label
      ),
      tip
    ),
    value = value,
    mod
  )
}

nlt <- function(icon = NULL, label, tip, value) {
  nav_item(
    tags$a(
      href = "#",
      role = "button",
      class = "dropdown-item",
      title = tip,
      onclick = sprintf(
        "Shiny.setInputValue('%s', Date.now(), {priority: 'event'}); return false;",
        value
      ),
      tooltip(
        span(
          if (!is.null(icon)) {
            shiny::icon(icon)
          },
          label
        ),
        tip
      )
    )
  )
}

ui <- tagList(
  # tags$head(
  #   tags$script(src = "vpro-early.js")
  # ),
  page_navbar(
    id = "main_tabs",
    title = div(
      role = "button",
      tabindex = "0",
      class = "d-flex align-items-center gap-2 vpro-navbar-title vpro-home-brand",
      onclick = "Shiny.setInputValue('vpro_go_home', Date.now(), {priority: 'event'}); return false;",
      onkeydown = "if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); Shiny.setInputValue('vpro_go_home', Date.now(), {priority: 'event'}); }",
      icon("seedling"),
      span("VPro", class = "fw-bold")
    ),
    theme = bs_theme(version = 5, bootswatch = "bcgov"),
    header = tagList(
      tags$head(
        tags$link(rel = "stylesheet", type = "text/css", href = "vpro-ui.css") #,
        # tags$script(src = "vpro-ui.js")
      ),
      shinyjs::useShinyjs() #,
      # div(class = "d-none", textInput("sel_su", NULL, value = "")),
      # uiOutput("floating_context_shell"),
    ),
    # Sidebar (VPro-style navigation)
    sidebar = sidebar(
      width = 300,
      title = NULL,
      id = "context_sidebar",
      open = "desktop",
      mod_sidebar_ui("sidebar")
    ),

    # Home ----
    npt(
      icon = "house",
      label = "Home",
      tip = "Welcome to VPro!  Click here to return to the home page.",
      value = "Home",
      mod = mod_home_ui("home")
    ),

    # Forms ----
    nav_menu(
      "Forms",
      "Data Entry",
      npt(
        icon = "rectangle-list",
        label = "FS882 Data Forms (6x4)",
        tip = "This is the data form that most closely resembles the FS882 field forms.",
        value = "fs882_6x4",
        mod = mod_fs882_6x4_ui("fs882_6x4")
      ),
      npt(
        icon = "mountain",
        label = "FS882 Data Forms (8x6)",
        tip = "8-column variant of the FS882 field form.",
        value = "fs882_8x6xl",
        mod = mod_fs882_8x6xl_ui("fs882_8x6xl")
      ),
      npt(
        icon = "campground",
        label = "Enter/Edit SIVI Data",
        tip = "SIVI and FS882 share a common data structure, but this form most closely resembles FS1333",
        value = "fs1333",
        mod = mod_fs1333_ui("fs1333")
      ),
      "---",
      "Others",
      npt(
        icon = "table-cells",
        label = "Metadata",
        tip = "Add/edit metadata",
        value = "metadata",
        mod = mod_project_metadata_ui("project_metadata")
      ),
      npt(
        icon = "link",
        label = "Combine Species",
        tip = "Here you can manage your combined (lumped) species tables.",
        value = "combine_species",
        mod = mod_combine_species_ui("combine_species")
      ),
      npt(
        icon = "leaf",
        label = "Herbarium",
        tip = "Have some herbarium data you want to manage?  Click here.",
        value = "herbarium",
        mod = mod_herbarium_ui("herbarium")
      ),
      npt(
        icon = "palette",
        label = "Colour-theme",
        tip = "In VPro, some of the output is thematic.  Here you can manage your theme colours and relate them to specific species.",
        value = "colour_theme",
        mod = mod_colour_theme_ui("colour_theme")
      ),
      npt(
        icon = "user-gear",
        label = "User setup",
        tip = "Revenue Canada on your tail?  Click here to change your name.  (We all know that VPro is the first place they will look for you)",
        value = "user_setup",
        mod = mod_user_setup_ui("user_setup")
      ),
      npt(
        icon = "clock-rotate-left",
        label = "User log",
        tip = "A record of when you (or someone else) opens and closes VPro.  Nothing spectacular, but useful just the same.",
        value = "user_log",
        mod = mod_user_log_ui("user_log")
      )
    ),
    # # Data ----
    #   nav_menu("Data",
    #     "Project",
    #     npt(
    #       icon = "folder-plus",
    #       label = "New Project",
    #       tip = "Create a new project.  A project stores your environment, vegetation and soil data.",
    #       value = "project_new",
    #       mod = mod_nav_launcher_ui("launch_project_new", "New Project", "Create a new project using the existing project controls in the sidebar.")
    #     ),
    #     npt(
    #       icon = "floppy-disk",
    #       label = "Save As...",
    #       tip = "Save the current project to a new or existing database using a different name.",
    #       value = "project_save_as",
    #       mod = mod_nav_launcher_ui("launch_project_save_as", "Save Project As", "Save the active project into a new database path.")
    #     ),
    #     npt(
    #       icon = "share-nodes",
    #       label = "Export Splinter Project",
    #       tip = "A splinter project is the portion of the current project that has matching plots in the current SU table.",
    #       value = "project_export_splinter",
    #       mod = mod_nav_launcher_ui("launch_project_export_splinter", "Export Splinter Project", "Open export tools and run project-level exports.")
    #     ),
    #     npt(
    #       icon = "diagram-project",
    #       label = "Merge Projects",
    #       tip = "Combine the plots of two projects.  Remember to backup your data before performing these types of functions.",
    #       value = "project_merge",
    #       mod = mod_nav_launcher_ui("launch_project_merge", "Merge Projects", "Open project merge/review workflows.")
    #     ),
    #     npt(
    #       icon = "not-equal",
    #       label = "Compare Two Projects",
    #       tip = "This tool compares site, soil, and vegetation data plot-by-plot and field-by-field, then produces an Excel report.",
    #       value = "project_compare",
    #       mod = mod_nav_launcher_ui("launch_project_compare", "Compare Two Projects", "Open reporting tools for cross-project checks.")
    #     ),
    #     npt(
    #       icon = "table-cells",
    #       label = "Project Metadata",
    #       tip = "Add/edit project metadata here.  It is suggested that you maintain project metadata for each of your projects.",
    #       value = "project_metadata",
    #       mod = mod_project_metadata_ui("project_metadata_data")
    #     ),
    #     npt(
    #       icon = "file-export",
    #       label = "Export Project Metadata",
    #       tip = "Use this tool to export your metadata to a database for distribution.",
    #       value = "project_metadata_export",
    #       mod = mod_nav_launcher_ui("launch_project_metadata_export", "Export Project Metadata", "Open export/reporting tools for metadata distribution.")
    #     ),
    #     npt(
    #       icon = "file-import",
    #       label = "Import Project Metadata",
    #       tip = "Import project metadata into your current metadata table.  Remember that the Project ID field must be unique.",
    #       value = "project_metadata_import",
    #       mod = mod_nav_launcher_ui("launch_project_metadata_import", "Import Project Metadata", "Open import tools for metadata tables.")
    #     ),
    #     "---",
    #     "Site Unit",
    #     npt(
    #       icon = "table",
    #       label = "New Site Unit Table",
    #       tip = "A site unit table is used to assign plots to groups.  It also functions as a filter limiting the number of active project plots.",
    #       value = "su_table_new",
    #       mod = mod_nav_launcher_ui("launch_su_table_new", "New Site Unit Table", "Open the Site Unit table tools.")
    #     ),
    #     npt(
    #       icon = "floppy-disk",
    #       label = "Save As...",
    #       tip = "Save the current site unit table to a new or existing database using a different name.",
    #       value = "su_table_save_as",
    #       mod = mod_nav_launcher_ui("launch_su_table_save_as", "Save Site Unit Table", "Open the Site Unit table tools and save/export workflows.")
    #     ),
    #     npt(
    #       icon = "filter",
    #       label = "SU Table From Filter Query",
    #       tip = "Uses a filter query to select plots from the current project and save them as a site unit table.  Unit assignments from current SU table are optional.",
    #       value = "su_table_from_query",
    #       mod = mod_nav_launcher_ui("launch_su_table_from_query", "SU Table From Filter Query", "Open SU tools and filter-driven assignment workflows.")
    #     ),
    #     npt(
    #       icon = "sliders",
    #       label = "SU Table From Form Filter",
    #       tip = "Using a Microsoft Access form filter, you can generate a SU table based on the selected plots.",
    #       value = "su_table_from_form_filter",
    #       mod = mod_nav_launcher_ui("launch_su_table_from_form_filter", "SU Table From Form Filter", "Open SU tools and form-filter workflows.")
    #     ),
    #     npt(
    #       icon = "wand-magic",
    #       label = "Create Site Units From Environment Fields",
    #       tip = "Uses concatenation to build unit names from environment field data.  The result is a new SU table.",
    #       value = "su_table_from_environment",
    #       mod = mod_nav_launcher_ui("launch_su_table_from_environment", "Create Site Units From Environment Fields", "Open SU tools and environment-driven unit creation workflows.")
    #     ),
    #     npt(
    #       icon = "arrows-left-right",
    #       label = "Compare Plot Assignments",
    #       tip = "Compare plot assignments between two site unit tables and generate an Excel report of the comparison.",
    #       value = "su_table_compare_assignments",
    #       mod = mod_nav_launcher_ui("launch_su_table_compare_assignments", "Compare Plot Assignments", "Open SU table comparison tools.")
    #     ),
    #     npt(
    #       icon = "list-ul",
    #       label = "List Site Units With Plots",
    #       tip = "Generates a list of current site units, their long names, number of plots, and a list of plot numbers.",
    #       value = "su_table_list_units_with_plots",
    #       mod = mod_nav_launcher_ui("launch_su_table_list_units_with_plots", "List Site Units With Plots", "Open SU tools and listing reports.")
    #     ),
    #     npt(
    #       icon = "pen-to-square",
    #       label = "Write BEC Master into SU Table",
    #       tip = "Copies the currently assigned BEC Master unit into the current Site Unit table replacing current unit assignments except where there does not exist a BEC Master unit assignment.",
    #       value = "su_table_write_bec_master",
    #       mod = mod_nav_launcher_ui("launch_su_table_write_bec_master", "Write BEC Master into SU Table", "Open SU tools and BEC writeback workflows.")
    #     ),
    #     "---",
    #     "Hierarchy",
    #     npt(
    #       icon = "sitemap",
    #       label = "New Hierarchy Table",
    #       tip = "A hierarchy table is a hierarchical construct of classification levels.  Use this function to create a new hierarchy table in a new or existing database.",
    #       value = "hierarchy_new",
    #       mod = mod_nav_launcher_ui("launch_hierarchy_new", "New Hierarchy Table", "Open hierarchy management tools.")
    #     ),
    #     npt(
    #       icon = "floppy-disk",
    #       label = "Save As...",
    #       tip = "Save the current hierarchy table to a new or existing database using a different name.",
    #       value = "hierarchy_save_as",
    #       mod = mod_nav_launcher_ui("launch_hierarchy_save_as", "Save Hierarchy Table", "Open hierarchy tools and save/export workflows.")
    #     ),
    #     npt(
    #       icon = "diagram-project",
    #       label = "Merge Hierarchies",
    #       tip = "Please backup first.  Hierarchies can be complex tables so there's a lot than can go wrong.  That said, use this tool to combine two hierarchies.",
    #       value = "hierarchy_merge",
    #       mod = mod_nav_launcher_ui("launch_hierarchy_merge", "Merge Hierarchies", "Open hierarchy merge and review workflows.")
    #     ),
    #     npt(
    #       icon = "diagram-project",
    #       label = "Hierarchy Diagram",
    #       tip = "Creates a diagram of the current hierarchy in Excel.  Includes a feature to help isolate orphaned hierarchy members.",
    #       value = "hierarchy_diagram",
    #       mod = mod_nav_launcher_ui("launch_hierarchy_diagram", "Hierarchy Diagram", "Open hierarchy diagram/report workflows.")
    #     ),
    #     "---",
    #     "Import",
    #     npt(
    #       icon = "database",
    #       label = "VPro 64 Project",
    #       tip = "Import a VPro 64 project.",
    #       value = "import_vpro_64_project",
    #       mod = mod_nav_launcher_ui("launch_import_vpro_64_project", "Import VPro 64 Project", "Open import module for VPro64 data migration.")
    #     ),
    #     npt(
    #       icon = "globe",
    #       label = "VENUS 5.0",
    #       tip = "Import VENUS 5.0 data.",
    #       value = "import_venus_5_0",
    #       mod = mod_nav_launcher_ui("launch_import_venus_5_0", "Import VENUS 5.0", "Open import module for VENUS data.")
    #     ),
    #     npt(
    #       icon = "file-code",
    #       label = "TurboVeg",
    #       tip = "Import TurboVeg data.",
    #       value = "data_turboveg",
    #       mod = mod_nav_launcher_ui("launch_data_turboveg", "Import TurboVeg", "Open import module for TurboVeg data.")
    #     ),
    #     "---",
    #     "Export",
    #     npt(
    #       icon = "file-code",
    #       label = "R (rds)",
    #       tip = "Export the current dataset for use in R.",
    #       value = "export_to_r",
    #       mod = mod_nav_launcher_ui("launch_export_to_r", "Export to R", "Open export module for R-ready data exports.")
    #     ),
    #     npt(
    #       icon = "file-code",
    #       label = "TurboVeg",
    #       tip = "Export the current dataset for use in TurboVeg.",
    #       value = "export_to_turboveg",
    #       mod = mod_nav_launcher_ui("launch_export_to_turboveg", "Export to TurboVeg", "Open export module for TurboVeg exports.")
    #     ),
    #     npt(
    #       icon = "seedling",
    #       label = "User Species List",
    #       tip = "Export the current user species list.",
    #       value = "export_user_species_list",
    #       mod = mod_nav_launcher_ui("launch_export_user_species_list", "Export User Species List", "Open export module for species list outputs.")
    #     ),
    #     "---",
    #     "Validate",
    #     npt(
    #       icon = "clipboard-check",
    #       label = "Validate Data",
    #       tip = "Here's an assortment of tools to validate and fix some common problems",
    #       value = "validate_data",
    #       mod = mod_nav_launcher_ui("launch_validate_data", "Validate Data", "Open reporting diagnostics and validation tools.")
    #     )
    #   ),
    # # Reports ----
    nav_menu(
      "Reports",
      "Vegetation",
      npt(
        icon = "table-list",
        label = "Long Vegetation",
        tip = "Creates an Excel report where, optionally, unit groups of plots are placed on individual sheets.",
        value = "report_long_vegetation",
        mod = mod_nav_launcher_ui("launch_report_long_vegetation", "Long Vegetation Report", "Open reporting module and run long vegetation outputs.")
      ),
      npt(
        icon = "chart-column",
        label = "Summary Vegetation",
        tip = "Creates an Excel report where, optionally, unit groups of plots are placed on individual sheets.",
        value = "report_summary_vegetation",
        mod = mod_nav_launcher_ui("launch_report_summary_vegetation", "Summary Vegetation Report", "Open reporting module and run summary vegetation outputs.")
      ),
      "---",
      "Environment",
      npt(
        icon = "table-list",
        label = "Long Environment",
        tip = "Creates an Excel report where site unit groups of plots are placed on individual sheets.",
        value = "report_long_environment",
        mod = mod_nav_launcher_ui("launch_report_long_environment", "Long Environment Report", "Open reporting module and run long environment outputs.")
      ),
      npt(
        icon = "chart-column",
        label = "Summary Environment",
        tip = "A summary of plots in each site unit is generated for the project.  Frequency for the qualitative values and mean or median values of the quantitative values are displayed.",
        value = "report_summary_environment",
        mod = mod_nav_launcher_ui("launch_report_summary_environment", "Summary Environment Report", "Open reporting module and run summary environment outputs.")
      ),
      "---",
      "Others",
      npt(
        icon = "table-cells-large",
        label = "Subzone Matrix of Units",
        tip = "A matrix is generated based on the current site unit table and the master site unit list.",
        value = "report_subzone_matrix_of_units",
        mod = mod_nav_launcher_ui("launch_report_subzone_matrix_of_units", "Subzone Matrix of Units", "Open reporting module and run subzone matrix reports.")
      ),
      npt(
        icon = "diagram-project",
        label = "Hierarchy Diagram",
        tip = "Creates a diagram of the current hierarchy in Excel.  Includes a feature to help isolate orphaned hierarchy members.",
        value = "report_hierarchy_diagram",
        mod = mod_nav_launcher_ui("launch_report_hierarchy_diagram", "Hierarchy Diagram Report", "Open hierarchy/reporting workflows for hierarchy diagrams.")
      ),
      npt(
        icon = "tag",
        label = "Print a Plot Label",
        tip = "Print a physical label to affix to your plot card.",
        value = "report_print_plot_label",
        mod = mod_nav_launcher_ui("launch_report_print_plot_label", "Print a Plot Label", "Open reporting module and run plot-label outputs.")
      ),
      npt(
        icon = "file-lines",
        label = "Create Plot Locations File",
        tip = "Prints a plot list that includes zone, subzone, site series, longitude, latitude and elevation.",
        value = "report_create_plot_locations_file",
        mod = mod_nav_launcher_ui("launch_report_create_plot_locations_file", "Create Plot Locations File", "Open reporting module and run location file outputs.")
      ),
      npt(
        icon = "earth-americas",
        label = "Show Plot Locations in Google Earth",
        tip = "Locate your plots using Google Earth (requires Google Earth installation)",
        value = "report_show_plot_locations_google_earth",
        mod = mod_nav_launcher_ui("launch_report_show_plot_locations_google_earth", "Show Plot Locations in Google Earth", "Open map/reporting workflows for Google Earth output.")
      )
    ),
    # # References ----
    #   nav_menu("References",
    #     "Library Tables",
    #     npt(
    #       icon = "list-check",
    #       label = "Site and Environment Codes",
    #       tip = "This tool allows the user to modify the drop-down lists in the data forms.  Please do not make any changes to these lists if you are working with BEC data!",
    #       value = "reference_site_environment_codes",
    #       mod = mod_nav_launcher_ui("launch_reference_site_environment_codes", "Site and Environment Codes", "Open the Site & Environment module for code-driven data context.")
    #     ),
    #     npt(
    #       icon = "book-open",
    #       label = "Species Name and Codes Table",
    #       tip = "Forms, reports, and import/export tools use this table to standardize data input and translate codes into scientific and common names.",
    #       value = "reference_species_name_codes",
    #       mod = mod_nav_launcher_ui("launch_reference_species_name_codes", "Species Name and Codes Table", "Open species/code references used by forms and reports.")
    #     ),
    #     "---",
    #     "User Setup",
    #     npt(
    #       icon = "link",
    #       label = "Attach species table",
    #       tip = "You can attach a different USysAllSpecs table if you wish.  We will assume you understand the implications involved.  When in doubt ask Will MacKenzie!",
    #       value = "reference_attach_species_table",
    #       mod = mod_nav_launcher_ui("launch_reference_attach_species_table", "Attach Species Table", "Open reference setup for species table attachment workflows.")
    #     ),
    #     npt(
    #       icon = "paperclip",
    #       label = "Attach code list table",
    #       tip = "VPro uses codes to store many of the data items.  These codes and their descriptions are stored in an attached table named USysTableOfLists.  Click to start the procedure to attach a different table.",
    #       value = "reference_attach_code_list_table",
    #       mod = mod_nav_launcher_ui("launch_reference_attach_code_list_table", "Attach Code List Table", "Open reference setup for list-table attachment workflows.")
    #     ),
    #     npt(
    #       icon = "palette",
    #       label = "Colour-theme",
    #       tip = "In VPro, some of the output is thematic.  Here you can manage your theme colours and relate them to specific species.",
    #       value = "reference_colour_theme",
    #       mod = mod_nav_launcher_ui("launch_reference_colour_theme", "Reference Colour-theme", "Open reference colour-theme setup.")
    #     ),
    #     npt(
    #       icon = "user-gear",
    #       label = "User setup",
    #       tip = "Revenue Canada on your tail?  Click here to change your name.  (We all know that VPro is the first place they will look for you)",
    #       value = "reference_user_setup",
    #       mod = mod_nav_launcher_ui("launch_reference_user_setup", "Reference User setup", "Open user setup and reference preferences.")
    #     ),
    #     npt(
    #       icon = "folder-tree",
    #       label = "Directories",
    #       tip = "Setup directory locations for files related to Google Earth, R, and plot photos.",
    #       value = "reference_directories",
    #       mod = mod_nav_launcher_ui("launch_reference_directories", "Directories", "Open directory and integration path setup.")
    #     )
    #   ),
    # Help ----
    nav_menu(
      "Help",
      "Help",
      # npt(
      #   icon = "circle-question",
      #   label = "VPro Help",
      #   tip = "Documents and Web links.",
      #   value = "help_vpro_help",
      #   mod = mod_nav_launcher_ui("launch_help_vpro_help", "VPro Help", "Open help resources and documentation links.")
      # ),
      # npt(
      #   icon = "boxes-stacked",
      #   label = "VPro Service Packs",
      #   tip = "Information on the VPro service packs installed on this machine.",
      #   value = "help_service_packs",
      #   mod = mod_nav_launcher_ui("launch_help_service_packs", "VPro Service Packs", "Open service pack and version information.")
      # ),
      # npt(
      #   icon = "rotate-left",
      #   label = "Set all to Sample",
      #   tip = "Problems with the menu?  Can't change projects?  Getting an error message?  Try this.",
      #   value = "help_set_all_to_sample",
      #   mod = mod_nav_launcher_ui("launch_help_set_all_to_sample", "Set all to Sample", "Run reset-style helper actions for local troubleshooting.")
      # ),
      nlt(
        icon = "newspaper",
        label = "What's New",
        tip = "See a list of the latest changes to VPro.",
        value = "btn_whatsnew"
      ) #,
      # npt(
      #   icon = "circle-info",
      #   label = "About VPro",
      #   tip = "Some basic information about your copy of VPro.",
      #   value = "help_about_vpro",
      #   mod = mod_nav_launcher_ui("launch_help_about_vpro", "About VPro", "Open application version and environment information.")
      # )
    ),

    # Hidden Reports destination panel (report launchers nav_select to "Reports")
    # nav_panel_hidden("Reports", mod_reporting_ui("report"))

    # STOP processing here

    # nav_menu(tagList(icon("cubes"), "Modules"),
    #   nav_panel(tagList(icon("leaf"), "Vegetation"), value = "Vegetation",
    #     mod_veg_sample_ui("veg")
    #   ),
    #   nav_panel(tagList(icon("mountain"), "FS882-8x6XL"), value = "FS882-8x6XL",
    #     mod_fs882_8x6xl_ui("fs882_8x6xl")
    #   ),
    #   nav_panel(tagList(icon("file-export"), "Export"), value = "Export",
    #     mod_export_ui("export")
    #   ),
    #   nav_panel(tagList(icon("file-import"), "Import"), value = "Import",
    #     mod_import_ui("import")
    #   ),
    #   nav_panel(tagList(icon("map-location-dot"), "Images & Maps"), value = "Images & Maps",
    #     mod_images_ui("imgs")
    #   ),
    #   nav_panel(tagList(icon("file-lines"), "Reports"), value = "Reports",
    #     mod_reporting_ui("report")
    #   ),
    #   nav_panel(tagList(icon("table"), "SU Table"), value = "SU Table",
    #     mod_su_table_ui("su_table")
    #   ),
    #   nav_panel(tagList(icon("sitemap"), "Hierarchy"), value = "Hierarchy",
    #     mod_hierarchy_ui("hier")
    #   ),
    #   nav_panel(tagList(icon("earth-americas"), "BEC Map Explorer"), value = "BEC Map Explorer",
    #     mod_becweb_map_ui("becmap")
    #   )
    # ),
    # nav_spacer(),
    # #nav_panel(tagList(icon("cloud-arrow-up"), "Upload"), value = "Upload",
    # #  mod_upload_ui("upload")
    # #),
    # nav_panel(uiOutput("nav_sync_label"), value = "Sync",
    #   mod_sync_ui("sync")
    # ),
    # nav_item(uiOutput("nav_plot_context")),
    # nav_item(mod_auth_status_ui("auth_status")),
    # nav_panel(tagList(icon("gear"), "Administration"), value = "Administration",
    #   mod_admin_ui("admin")
    # )
  )
)
