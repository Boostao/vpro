# UI Definition
# Uses bslib for a modern dashboard layout replacing the Access Menu

if (!"bcgov" %in% bslib::bootswatch_themes()) {
  source("theme/add_bcgov_bootswatch_to_bslib.R")
}

npt<-function(i=NULL,l,t,v=t){
  nav_panel(tooltip(span(if(!is.null(i)){icon(i)},l),t),value=v)
}

nlt <- function(i=NULL,l,t,v=t) {
  nav_item(
    tags$a(
      href = "#",
      role = "button",
      class = "dropdown-item",
      title = t,
      onclick = sprintf(
        "Shiny.setInputValue('%s', Date.now(), {priority: 'event'}); return false;",
        v
      ),
      tooltip(span(if(!is.null(i)){icon(i)},l),t)
    )
  )
}

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

# Forms ----
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
# Data ----
  nav_menu("Data",
    "Project",
    npt("folder-plus", "New Project", "Create a new project.  A project stores your environment, vegetation and soil data.","project_new"),
    npt("floppy-disk", "Save As...", "Save the current project to a new or existing database using a different name.","project_save_as"),
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
    npt("diagram-project", "Merge Hierarchies", "Please backup first.  Hierarchies can be complex tables so there's a lot than can go wrong.  That said, use this tool to combine two hierarchies.","hierarchy_merge"),
    npt("diagram-project", "Hierarchy Diagram", "Creates a diagram of the current hierarchy in Excel.  Includes a feature to help isolate orphaned hierarchy members.","hierarchy_diagram"),
    "---",
    "Import",
    npt("database", "VPro 64 Project", "Import a VPro 64 project.","import_vpro_64_project"),
    npt("globe", "VENUS 5.0", "Import VENUS 5.0 data.","import_venus_5_0"),
    npt("file-code", "TurboVeg", "Import TurboVeg data.","data_turboveg"),
    "---",
    "Export",
    npt("file-code", "R (rds)", "Export the current dataset for use in R.","export_to_r"),
    npt("file-code", "TurboVeg", "Export the current dataset for use in TurboVeg.","export_to_turboveg"),
    npt("seedling", "User Species List", "Export the current user species list.","export_user_species_list"),
    "---",
    "Validate",
    npt("clipboard-check", "Validate Data", "Here's an assortment of tools to validate and fix some common problems","validate_data")
  ),
# Reports ----
  nav_menu("Reports",
    "Vegetation",
    npt("table-list", "Long Vegetation", "Creates an Excel report where, optionally, unit groups of plots are placed on individual sheets.","report_long_vegetation"),
    npt("chart-column", "Summary Vegetation", "Creates an Excel report where, optionally, unit groups of plots are placed on individual sheets.","report_summary_vegetation"),
    "---",
    "Environment",
    npt("table-list", "Long Environment", "Creates an Excel report where site unit groups of plots are placed on individual sheets.","report_long_environment"),
    npt("chart-column", "Summary Environment", "A summary of plots in each site unit is generated for the project.  Frequency for the qualitative values and mean or median values of the quantitative values are displayed.","report_summary_environment"),
    "---",
    "Others",
    npt("table-cells-large", "Subzone Matrix of Units", "A matrix is generated based on the current site unit table and the master site unit list.","report_subzone_matrix_of_units"),
    npt("diagram-project", "Hierarchy Diagram", "Creates a diagram of the current hierarchy in Excel.  Includes a feature to help isolate orphaned hierarchy members.","report_hierarchy_diagram"),
    npt("tag", "Print a Plot Label", "Print a physical label to affix to your plot card.","report_print_plot_label"),
    npt("file-lines", "Create Plot Locations File", "Prints a plot list that includes zone, subzone, site series, longitude, latitude and elevation.","report_create_plot_locations_file"),
    npt("earth-americas", "Show Plot Locations in Google Earth", "Locate your plots using Google Earth (requires Google Earth installation)","report_show_plot_locations_google_earth")
  ),
# References ----
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
# Help ----
  nav_menu("Help",
    "Help",
    npt("circle-question", "VPro Help", "Documents and Web links.","help_vpro_help"),
    npt("boxes-stacked", "VPro Service Packs", "Information on the VPro service packs installed on this machine.","help_service_packs"),
    npt("rotate-left", "Set all to Sample", "Problems with the menu?  Can't change projects?  Getting an error message?  Try this.","help_set_all_to_sample"),
    nlt("newspaper", "What's New", "See a list of the latest changes to VPro.","btn_whatsnew"),
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
  nav_panel(uiOutput("nav_sync_label"), value = "Sync",
    mod_sync_ui("sync")
  ),
  nav_panel(span(class = "vpro-auth-tab-label", tagList(icon("user-shield"), "Auth")), value = "Auth",
    mod_auth_ui("auth")
  ),
  nav_item(uiOutput("nav_plot_context")),
  nav_item(mod_auth_status_ui("auth_status")),
  nav_panel(tagList(icon("gear"), "Administration"), value = "Administration",
    mod_admin_ui("admin")
  )
)
