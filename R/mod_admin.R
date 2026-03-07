# =============================================================================
# mod_admin.R -- Thin wrapper: delegates to 6 focused sub-modules.
# Sub-modules: mod_admin_projects, mod_admin_codes, mod_admin_master,
#              mod_admin_audit, mod_admin_merge, mod_admin_publishing
# =============================================================================

mod_admin_ui <- function(id) {
  ns <- NS(id)
  page_fillable(
    card(
      full_screen = TRUE,
      navset_card_tab(
        nav_panel("Project Management", mod_admin_projects_ui(ns("projects"))),
        nav_panel("Code Maintenance",   mod_admin_codes_ui(ns("codes"))),
        nav_panel("Master Site Units",  mod_admin_master_ui(ns("master"))),
        nav_panel("Audit Log",          mod_admin_audit_ui(ns("audit"))),
        nav_panel("Merge Review",       mod_admin_merge_ui(ns("merge"))),
        nav_panel("Publishing",         mod_admin_publishing_ui(ns("publishing")))
      )
    )
  )
}

mod_admin_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    mod_admin_projects_server("projects", state, con)
    mod_admin_codes_server("codes",       state, con)
    mod_admin_master_server("master",     state, con)
    mod_admin_audit_server("audit",       state, con)
    mod_admin_merge_server("merge",       state, con)
    mod_admin_publishing_server("publishing", state, con)
  })
}
