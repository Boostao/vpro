# =============================================================================
# mod_sync.R
# Field-user push-only sync module: view local changes (9 tables), push to
# staging, view own merge requests. No pull functionality.
# =============================================================================

# ── UI ────────────────────────────────────────────────────────────────────────

mod_sync_ui <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "sync-updates-shell mt-1",
      div(
        class = "sync-updates-hero mb-3",
        div(
          class = "sync-updates-hero-copy",
          div(
            class = "sync-updates-hero-top",
            div(
              class = "sync-updates-copy-block",
              div(class = "sync-updates-eyebrow", "Sync workspace"),
              h3(class = "sync-updates-title", "Updates"),
              p(
                class = "sync-updates-lede",
                "Review local changes, authenticate when needed, and send one clean merge request from the same workspace."
              )
            ),
            div(
              class = "sync-updates-actions",
              div(
                class = "sync-updates-project",
                uiOutput(ns("project_badge"))
              ),
              div(
                class = "sync-updates-primary",
                actionButton(
                  ns("sync_push"),
                  label = tagList(icon("cloud-arrow-up"), "Push changes"),
                  class = "btn btn-primary sync-push-button"
                )
              ),
              div(
                class = "sync-updates-secondary",
                actionButton(
                  ns("sync_revert_all"),
                  label = tagList(icon("rotate-left"), "Revert all"),
                  class = "btn sync-updates-action sync-updates-action-danger"
                ),
                actionButton(
                  ns("sync_refresh"),
                  label = tagList(icon("rotate"), "Refresh"),
                  class = "btn sync-updates-action sync-updates-action-neutral"
                )
              )
            )
          ),
          div(
            id = ns("sync_auth_card_anchor"),
            class = "sync-auth-shell",
            tabindex = "-1",
            mod_auth_ui(ns("auth_embedded"))
          )
        ),
        div(
          class = "sync-updates-side",
          uiOutput(ns("changes_snapshot")),
          uiOutput(ns("comparison_overview")),
          uiOutput(ns("merge_request_overview"))
        )
      )
    ),

    tags$style(HTML("
      .sync-updates-shell { display: flex; flex-direction: column; gap: 14px; }
      .sync-updates-hero { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(340px, 0.95fr); gap: 16px; align-items: stretch; }
      .sync-updates-hero-copy { border: 1px solid #d8e2eb; border-radius: 20px; padding: 22px 24px; background: #ffffff; box-shadow: 0 16px 36px rgba(24, 53, 77, 0.08); display: flex; flex-direction: column; gap: 18px; min-height: 100%; min-width: 0; }
      .sync-updates-hero-top { display: grid; grid-template-columns: minmax(0, 1fr) minmax(240px, 18.5rem); gap: 18px; align-items: start; min-width: 0; }
      .sync-updates-copy-block { display: grid; gap: 10px; min-width: 0; }
      .sync-updates-eyebrow { font-size: 0.78rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: #6b7785; margin-bottom: 6px; }
      .sync-updates-title { margin: 0; font-size: 1.85rem; font-weight: 700; color: #15324b; }
      .sync-updates-lede { margin: 0; color: #587083; font-size: 0.96rem; line-height: 1.45; max-width: 34rem; }
      .sync-updates-actions { display: grid; gap: 12px; margin-top: 0; min-width: 0; align-content: start; }
      .sync-updates-project { display: flex; align-items: center; min-width: 0; }
      .sync-updates-project > * { min-width: 0; width: 100%; }
      .sync-updates-primary { display: flex; }
      .sync-updates-secondary { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
      .sync-updates-secondary .btn { width: 100%; }
      .sync-push-button { width: 100%; min-height: 52px; font-weight: 700; font-size: 1.05rem; border-radius: 14px; }
      .sync-updates-action { min-height: 44px; border-radius: 14px; display: inline-flex; align-items: center; justify-content: center; gap: 8px; font-weight: 700; border-width: 1px; box-shadow: 0 10px 22px rgba(20, 39, 57, 0.06); transition: transform 120ms ease, box-shadow 120ms ease, border-color 120ms ease, background 120ms ease, color 120ms ease; white-space: normal; text-align: center; line-height: 1.2; }
      .sync-updates-action:hover, .sync-updates-action:focus { transform: translateY(-1px); box-shadow: 0 14px 28px rgba(24, 53, 77, 0.1); }
      .sync-updates-action .fa, .sync-updates-action .fas, .sync-updates-action .far, .sync-updates-action .fab { font-size: 0.9rem; }
      .sync-updates-action-neutral { background: rgba(255,255,255,0.95); color: #17344a; border-color: #d4e0ea; }
      .sync-updates-action-neutral:hover, .sync-updates-action-neutral:focus { background: #f7fbff; color: #16344b; border-color: #aac3d8; }
      .sync-updates-action-danger { background: linear-gradient(180deg, #fff7f5 0%, #fdeeea 100%); color: #a44942; border-color: #efc8c2; }
      .sync-updates-action-danger:hover, .sync-updates-action-danger:focus { background: linear-gradient(180deg, #fff1ee 0%, #fce5df 100%); color: #923f39; border-color: #e6b1aa; }
      .sync-updates-action[disabled], .sync-updates-action.disabled { transform: none; box-shadow: none; opacity: 0.65; }
      .sync-updates-action-neutral[disabled], .sync-updates-action-neutral.disabled { background: #f4f7fa; border-color: #dbe3ea; color: #8a99a6; }
      .sync-updates-action-danger[disabled], .sync-updates-action-danger.disabled { background: #fff8f7; border-color: #efd9d4; color: #c08d87; }
      .sync-updates-side { display: grid; grid-template-columns: 1fr; gap: 12px; align-items: stretch; }
      .sync-auth-shell { border-top: 1px solid rgba(21, 50, 75, 0.09); padding-top: 32px; margin-top: 10px; outline: none; }
      .sync-auth-shell.is-focused { box-shadow: 0 0 0 3px rgba(0, 100, 180, 0.15); border-radius: 18px; }
      .sync-auth-panel { border: 1px solid #d7e3ea; border-radius: 18px; background: rgba(255,255,255,0.84); padding: 18px; box-shadow: inset 0 1px 0 rgba(255,255,255,0.7); display: grid; gap: 14px; }
      .sync-auth-panel-ready { background: #ffffff; }
      .sync-auth-header { display: flex; justify-content: space-between; align-items: start; gap: 12px; }
      .sync-auth-header-copy { display: grid; gap: 6px; }
      .sync-auth-header-badge { display: flex; align-items: start; }
      .sync-auth-kicker { font-size: 0.72rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: #6b7785; }
      .sync-auth-title { margin: 0; font-size: 1.12rem; font-weight: 700; color: #18354d; }
      .sync-auth-note { margin: 0; color: #5f7283; font-size: 0.9rem; line-height: 1.45; }
      .sync-auth-logout-chip { display: inline-flex; align-items: center; justify-content: center; width: 2.3rem; height: 2.3rem; border-radius: 999px; background: #fdecea; color: #c45a53; border: 1px solid #f0c7c2; text-decoration: none; }
      .sync-auth-logout-chip:hover { background: #fbe2df; color: #b44e47; text-decoration: none; }
      .sync-auth-form-grid { display: grid; gap: 10px; }
      .sync-auth-submit { width: 100%; min-height: 44px; font-weight: 700; border-radius: 12px; }
      .sync-auth-status-line { min-height: 1.2rem; color: #5d6d7c; font-size: 0.86rem; }
      .sync-auth-ready-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
      .sync-auth-ready-stat { border-radius: 12px; border: 1px solid #e0e8ef; background: #f7fafc; padding: 10px 12px; }
      .sync-auth-ready-stat-head { display: flex; align-items: start; justify-content: space-between; gap: 8px; margin-bottom: 4px; }
      .sync-auth-ready-label { display: block; font-size: 0.68rem; text-transform: uppercase; letter-spacing: 0.05em; color: #6d7c89; margin-bottom: 4px; }
      .sync-auth-ready-value { display: block; font-size: 0.98rem; font-weight: 700; color: #16344b; word-break: break-word; }
      .sync-auth-edit-link { color: #6b7a88; text-decoration: none; line-height: 1; }
      .sync-auth-edit-link:hover { color: #16344b; text-decoration: none; }
      .sync-auth-inline-editor .form-group, .sync-auth-inline-editor .shiny-input-container { margin-bottom: 0; }
      .sync-auth-inline-editor input { min-height: 40px; border-radius: 10px; }
      .sync-auth-inline-actions { display: flex; gap: 8px; margin-top: 8px; }
      .sync-auth-inline-hint { margin-top: 6px; color: #6a7a88; font-size: 0.8rem; }
      .sync-auth-role-value { display: flex; align-items: center; min-height: 40px; }
      .sync-auth-role-actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
      .sync-auth-role-btn { display: inline-flex; align-items: center; gap: 8px; min-height: 38px; padding: 0.4rem 0.8rem; border-radius: 999px; border: 1px solid #d7e3ea; background: #ffffff; color: #17344a; box-shadow: 0 6px 14px rgba(20, 39, 57, 0.05); }
      .sync-auth-role-btn:hover, .sync-auth-role-btn:focus { background: #f6fbff; border-color: #bfd3e3; color: #16344b; }
      .sync-auth-admin-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
      .sync-auth-admin-card { border: 1px solid #d9e3ec; border-radius: 16px; background: #fff; padding: 16px; }
      .sync-auth-admin-title { margin: 0 0 10px 0; font-size: 0.95rem; font-weight: 700; color: #18354d; }
      .sync-summary-card, .sync-comparison-card, .sync-merge-summary-card { border: 1px solid #d7e3ea; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 26px rgba(16, 38, 56, 0.06); }
      .sync-summary-card { padding: 16px; height: 100%; text-align: left; width: 100%; transition: transform 120ms ease, box-shadow 120ms ease, border-color 120ms ease, background 120ms ease; }
      .sync-summary-card:hover, .sync-summary-card:focus { border-color: #9db7cf; background: #fbfdff; transform: translateY(-1px); box-shadow: 0 14px 30px rgba(24, 53, 77, 0.09); }
      .sync-summary-header { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; margin-bottom: 12px; }
      .sync-summary-title { font-size: 0.95rem; font-weight: 700; color: #18354d; }
      .sync-summary-total { font-size: 1.5rem; font-weight: 700; color: #18354d; }
      .sync-summary-headline { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
      .sync-summary-meta { margin-top: 10px; color: #5f6f7d; font-size: 0.88rem; }
      .sync-summary-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; }
      .sync-summary-chip { border-radius: 12px; padding: 10px 12px; background: #f5f8fb; border: 1px solid #e1e8ef; }
      .sync-summary-chip-label { display: block; font-size: 0.68rem; text-transform: uppercase; letter-spacing: 0.05em; color: #6c7b88; margin-bottom: 4px; white-space: nowrap; }
      .sync-summary-chip-value { display: block; font-size: 1.05rem; font-weight: 700; color: #1b3145; }
      .sync-summary-chip.is-insert { background: #edf7ea; border-color: #cfe4ca; }
      .sync-summary-chip.is-update { background: #fff7de; border-color: #f1dfa2; }
      .sync-summary-chip.is-delete { background: #fdecea; border-color: #f0c7c2; }
      .sync-comparison-card, .sync-merge-summary-card { width: 100%; padding: 16px 18px; text-align: left; min-height: 148px; display: flex; align-items: stretch; transition: transform 120ms ease, box-shadow 120ms ease, border-color 120ms ease, background 120ms ease; }
      .sync-comparison-card .action-label, .sync-merge-summary-card .action-label { display: flex; flex-direction: column; justify-content: space-between; width: 100%; }
      .sync-comparison-card:hover, .sync-comparison-card:focus, .sync-merge-summary-card:hover, .sync-merge-summary-card:focus { border-color: #9db7cf; background: #fbfdff; transform: translateY(-1px); box-shadow: 0 14px 30px rgba(24, 53, 77, 0.09); }
      .sync-comparison-label, .sync-merge-summary-label, .sync-summary-titleline { display: inline-flex; align-items: center; gap: 8px; font-size: 0.74rem; text-transform: uppercase; letter-spacing: 0.06em; color: #6b7785; margin-bottom: 6px; }
      .sync-card-label-icon { color: #7a8a98; font-size: 0.82rem; }
      .sync-comparison-headline, .sync-merge-summary-headline { display: flex; align-items: center; justify-content: space-between; gap: 10px; font-weight: 700; color: #15324b; }
      .sync-comparison-meta, .sync-merge-summary-meta { margin-top: 8px; color: #5f6f7d; font-size: 0.88rem; }
      .sync-comparison-badges, .sync-merge-summary-badges { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 10px; }
      .sync-merge-summary-stats { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; margin-top: 12px; }
      .sync-merge-summary-stat { border-radius: 12px; padding: 10px 12px; background: #f6f8fb; border: 1px solid #e2e8ef; }
      .sync-merge-summary-stat-label { display: block; font-size: 0.68rem; text-transform: uppercase; letter-spacing: 0.05em; color: #6c7b88; margin-bottom: 4px; }
      .sync-merge-summary-stat-value { display: block; font-size: 1rem; font-weight: 700; color: #18354d; }
      .sync-card-pill { display: inline-flex; align-items: center; gap: 6px; border-radius: 999px; padding: 0.35rem 0.72rem; font-size: 0.76rem; font-weight: 700; border: 1px solid transparent; }
      .sync-card-pill-neutral { background: #f4f7fa; color: #5f7283; border-color: #dde5ec; }
      .sync-card-pill-info { background: #eef6ff; color: #35698e; border-color: #cfe0ef; }
      .sync-card-pill-warn { background: #fff5de; color: #8a6a21; border-color: #efdca2; }
      .sync-status-pill { display: inline-flex; align-items: center; gap: 6px; border-radius: 999px; padding: 0.35rem 0.68rem; font-size: 0.76rem; font-weight: 700; border: 1px solid transparent; }
      .sync-status-pill-ready { background: #e3f7ee; color: #1d7a56; border-color: #bee7d3; }
      .sync-status-pill-muted { background: #f2f5f8; color: #687987; border-color: #dde5ec; }
      .sync-merge-panel { display: grid; gap: 16px; }
      .sync-merge-review-shell { padding-top: 6px; }
      .sync-merge-toolbar { display: flex; flex-wrap: wrap; gap: 14px; align-items: end; }
      .sync-merge-toolbar .shiny-input-container { margin-bottom: 0; }
      .sync-merge-table-wrap { border: 1px solid #dde6ee; border-radius: 16px; padding: 12px; background: linear-gradient(180deg, #ffffff 0%, #fbfdff 100%); }
      .sync-merge-table-wrap .dataTables_wrapper { margin-bottom: 0; }
      .sync-merge-table-wrap .dataTables_filter input,
      .sync-merge-table-wrap .dataTables_length select,
      .sync-admin-merge-review .dataTables_filter input,
      .sync-admin-merge-review .dataTables_length select { border-radius: 10px; border: 1px solid #d6e0ea; min-height: 38px; }
      .sync-merge-table-wrap table.dataTable,
      .sync-admin-merge-review table.dataTable { border-collapse: separate !important; border-spacing: 0; width: 100% !important; }
      .sync-merge-table-wrap table.dataTable thead th,
      .sync-admin-merge-review table.dataTable thead th { background: #eef4f9; color: #17344a; border-bottom: 1px solid #d5e0ea !important; font-weight: 700; padding: 12px 14px; }
      .sync-merge-table-wrap table.dataTable tbody td,
      .sync-admin-merge-review table.dataTable tbody td { padding: 12px 14px; border-top: 1px solid #edf2f7; color: #274055; vertical-align: top; }
      .sync-merge-table-wrap table.dataTable tbody tr:hover,
      .sync-admin-merge-review table.dataTable tbody tr:hover { background: #f8fbfe; }
      .sync-merge-table-wrap table.dataTable tbody tr.selected,
      .sync-admin-merge-review table.dataTable tbody tr.selected { background: #e7f1fb !important; }
      .sync-merge-table-wrap .dataTables_paginate .paginate_button,
      .sync-admin-merge-review .dataTables_paginate .paginate_button { border-radius: 999px !important; border: 1px solid #d6e0ea !important; background: #fff !important; color: #17344a !important; margin-left: 4px; }
      .sync-merge-table-wrap .dataTables_paginate .paginate_button.current,
      .sync-admin-merge-review .dataTables_paginate .paginate_button.current { background: #17344a !important; color: #fff !important; border-color: #17344a !important; }
      .sync-merge-table-wrap .dataTables_info,
      .sync-admin-merge-review .dataTables_info { color: #5c6f80; font-size: 0.85rem; }
      .sync-merge-detail-card { border: 1px solid #dce6ef; border-radius: 16px; background: linear-gradient(180deg, #ffffff 0%, #fbfdff 100%); box-shadow: 0 8px 20px rgba(20, 39, 57, 0.05); }
      .sync-merge-detail-card .card-title { font-size: 1rem; font-weight: 700; color: #17344a; }
      .sync-merge-detail-card dt { color: #6a7a88; font-weight: 700; }
      .sync-merge-detail-card dd { color: #243f55; }
      .sync-comparison-modal-shell { display: grid; gap: 16px; }
      .sync-comparison-modal-intro { padding: 18px 20px; border-radius: 16px; background: linear-gradient(135deg, #f6fbff 0%, #edf4fb 100%); border: 1px solid #d8e5f0; }
      .sync-comparison-modal-kicker { display: block; font-size: 0.74rem; text-transform: uppercase; letter-spacing: 0.08em; color: #6b7785; margin-bottom: 6px; font-weight: 700; }
      .sync-comparison-modal-title { display: block; font-size: 1.2rem; font-weight: 700; color: #16344b; margin-bottom: 6px; }
      .sync-comparison-modal-note { color: #587083; font-size: 0.92rem; margin: 0; }
      .sync-comparison-modal-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, 0.95fr); gap: 14px; }
      .sync-comparison-modal-card { border: 1px solid #d8e2eb; border-radius: 16px; background: #ffffff; padding: 16px; }
      .sync-comparison-modal-card-title { font-size: 0.9rem; font-weight: 700; color: #18354d; margin-bottom: 10px; }
      .sync-comparison-modal-card-subtitle { color: #687987; font-size: 0.85rem; margin-bottom: 12px; }
      .sync-source-summary { margin-bottom: 0; }
      .sync-source-badges { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; margin-bottom: 8px; }
      .sync-modal-upload .shiny-input-container { margin-bottom: 0; }
      @media (max-width: 1400px) {
        .sync-updates-hero { grid-template-columns: minmax(0, 1fr); }
      }
      @media (max-width: 1180px) {
        .sync-updates-hero-top { grid-template-columns: minmax(0, 1fr); }
      }
      @media (max-width: 680px) {
        .sync-updates-secondary { grid-template-columns: minmax(0, 1fr); }
      }
      .sync-diff-card { border-left: 4px solid #ccc; margin-bottom: 10px; border-radius: 4px; background: #fff; }
      .sync-diff-card.sync-insert { border-color: #43893e; }
      .sync-diff-card.sync-update { border-color: #f9ca54; }
      .sync-diff-card.sync-delete { border-color: #c03b2b; }
      .sync-diff-header { padding: 7px 12px; font-size: 0.82em; font-weight: 600; display: flex; align-items: center; gap: 8px; }
      .sync-diff-card.sync-insert .sync-diff-header { background: #edf7ea; }
      .sync-diff-card.sync-update .sync-diff-header { background: #fef9ec; }
      .sync-diff-card.sync-delete .sync-diff-header { background: #fdecea; }
      .sync-diff-body { padding: 4px 0; }
      .sync-diff-row { display: grid; grid-template-columns: 160px 1fr; font-size: 0.8em; padding: 2px 12px; }
      .sync-diff-row.changed { grid-template-columns: 160px 1fr auto 1fr; }
      .sync-diff-row.deleted { grid-template-columns: 160px 1fr; }
      .sync-diff-field { color: #666; font-family: monospace; }
      .sync-val-before { font-family: monospace; background: #fff3cd; padding: 1px 4px; border-radius: 2px; }
      .sync-val-after  { font-family: monospace; background: #d4edda; padding: 1px 4px; border-radius: 2px; }
      .sync-val-new    { font-family: monospace; background: #d4edda; padding: 1px 4px; border-radius: 2px; }
      .sync-val-delete { font-family: monospace; background: #f8d7da; padding: 1px 4px; border-radius: 2px; }
      .sync-diff-arrow { color: #888; padding: 0 6px; }
      .sync-section-badge { display: inline-flex; gap: 4px; margin-left: 8px; }
      .sync-section-badge .badge { font-size: 0.72em; font-weight: 600; vertical-align: middle; }
      .sync-diff-actions { margin-left: auto; }
      @media (max-width: 991.98px) {
        .sync-updates-hero { grid-template-columns: 1fr; }
        .sync-updates-hero-top { grid-template-columns: 1fr; }
        .sync-auth-admin-grid { grid-template-columns: 1fr; }
        .sync-auth-ready-grid { grid-template-columns: 1fr; }
        .sync-summary-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
        .sync-comparison-modal-grid { grid-template-columns: 1fr; }
      }
      @media (max-width: 575.98px) {
        .sync-updates-secondary, .sync-merge-summary-stats, .sync-summary-grid, .sync-auth-ready-grid { grid-template-columns: 1fr; }
        .sync-merge-toolbar { flex-direction: column; align-items: stretch; }
        .sync-auth-header { flex-direction: column; }
      }
    "))
  )
}


# ── Server ────────────────────────────────────────────────────────────────────

mod_sync_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    mod_auth_server("auth_embedded", state, con)
    mod_admin_merge_server("admin_merge", state, con)

    section_groups <- list(
      site = c("admin", "env", "su"),
      soil = c("humus", "mineral", "other"),
      veg = c("veg", "herbarium"),
      project = c("metadata")
    )

    touch_site_hierarchy <- function(records = NULL, table_name = NULL) {
      site_tables <- section_groups$site
      should_refresh <- FALSE

      if (!is.null(table_name)) {
        should_refresh <- as.character(table_name) %in% site_tables
      }
      if (!should_refresh && !is.null(records) && length(records) > 0) {
        should_refresh <- any(vapply(records, function(record) {
          as.character(record$table_pg %||% "") %in% site_tables
        }, logical(1)))
      }

      if (isTRUE(should_refresh)) {
        state$HierarchyRefreshVersion <- (state$HierarchyRefreshVersion %||% 0L) + 1L
      }
      invisible(should_refresh)
    }

    # ── Invalidation signals ─────────────────────────────────────────────────
    rv_refresh   <- reactiveVal(0L)
    rv_mr_reload <- reactiveVal(0L)

    observeEvent(input$sync_refresh, rv_refresh(rv_refresh() + 1L))
    observeEvent(input$mr_refresh,   rv_mr_reload(rv_mr_reload() + 1L))

    # Refresh when Sync tab is navigated to
    observeEvent(state$SyncTabActivated, {
      rv_refresh(rv_refresh() + 1L)
    }, ignoreInit = TRUE)

    rv_last_project <- reactiveVal(NULL)
    rv_compare_source_preference <- reactiveVal(NULL)
    rv_delete_merge_request_id <- reactiveVal(NULL)
    rv_last_auth_cloud_ready <- reactiveVal(FALSE)
    is_authenticated <- reactive({
      isTRUE(state$AuthAuthenticated)
    })

    focus_auth_card <- function() {
      shinyjs::runjs(sprintf(
        "(function() { var el = document.getElementById('%s'); if (!el) return; el.classList.add('is-focused'); el.scrollIntoView({behavior: 'smooth', block: 'center'}); if (el.focus) { el.focus({preventScroll: true}); } setTimeout(function() { el.classList.remove('is-focused'); }, 1800); })();",
        ns("sync_auth_card_anchor")
      ))
    }

    observeEvent(state$SyncFocusAuthRequest, {
      req(state$SyncFocusAuthRequest)
      focus_auth_card()
    }, ignoreInit = TRUE)

    # ── Current project from state ────────────────────────────────────────────
    current_project_id <- reactive({
      state$CurrProject %||% state$PrefProject
    })

    default_compare_source <- function(project_id) {
      if (!isTRUE(is_authenticated())) return("backup_file")

      pending_rows <- tryCatch(pending_project_merge_requests(), error = function(e) data.frame())
      if (!is.null(pending_rows) && nrow(pending_rows) > 0) {
        return(sync_compare_source_merge_request_value(pending_rows$id[[1]]))
      }

      info <- sync_resolve_compare_source(con, project_id = project_id, compare_source = "cloud_core")
      if (isTRUE(info$cloud_available)) "cloud_core" else "backup_file"
    }

    .merge_request_total_rows <- function(record_counts) {
      tryCatch({
        parsed <- jsonlite::fromJSON(record_counts %||% "{}")
        as.integer(sum(unlist(parsed), na.rm = TRUE))
      }, error = function(e) 0L)
    }

    pending_project_merge_requests <- reactive({
      rv_mr_reload()
      if (!isTRUE(is_authenticated()) || !sync_cloud_connected(con)) return(data.frame())
      tryCatch(
        sync_get_user_pending_merge_requests(
          con,
          submitter = state$User %||% "",
          project_id = current_project_id()
        ),
        error = function(e) data.frame()
      )
    })

    pending_user_merge_requests <- reactive({
      rv_mr_reload()
      if (!isTRUE(is_authenticated()) || !sync_cloud_connected(con)) return(data.frame())
      tryCatch(
        sync_get_user_pending_merge_requests(
          con,
          submitter = state$User %||% ""
        ),
        error = function(e) data.frame()
      )
    })

    .flatten_choice_values <- function(choices) {
      values <- character(0)
      for (choice in choices) {
        if (is.list(choice)) {
          values <- c(values, .flatten_choice_values(choice))
        } else {
          values <- c(values, unname(as.character(choice)))
        }
      }
      unique(values[nzchar(values)])
    }

    compare_source_choices <- reactive({
      primary_choices <- c("Backup file" = "backup_file")
      if (isTRUE(is_authenticated())) {
        primary_choices <- c("Master" = "cloud_core", primary_choices)
      }

      choices <- list("Compare against" = primary_choices)
      pending_rows <- pending_project_merge_requests()
      if (!is.null(pending_rows) && nrow(pending_rows) > 0) {
        mr_values <- vapply(
          pending_rows$id,
          sync_compare_source_merge_request_value,
          character(1)
        )
        mr_labels <- vapply(seq_len(nrow(pending_rows)), function(row_idx) {
          sprintf(
            "MR #%s (%s row%s)",
            pending_rows$id[[row_idx]],
            .merge_request_total_rows(pending_rows$record_counts[[row_idx]]),
            if (.merge_request_total_rows(pending_rows$record_counts[[row_idx]]) == 1) "" else "s"
          )
        }, character(1))
        choices[["Pending merge requests"]] <- stats::setNames(mr_values, mr_labels)
      }

      choices
    })

    selected_compare_source <- reactive({
      valid_values <- .flatten_choice_values(compare_source_choices())
      selected <- sync_normalize_compare_source(
        rv_compare_source_preference() %||% input$compare_source %||% default_compare_source(current_project_id())
      )
      if (!isTRUE(is_authenticated()) && identical(sync_compare_source_parse(selected)$kind, "cloud")) {
        selected <- SYNC_COMPARE_SOURCE_BACKUP
      }
      if (selected %in% valid_values) return(selected)

      fallback <- default_compare_source(current_project_id())
      if (!isTRUE(is_authenticated()) && identical(sync_compare_source_parse(fallback)$kind, "cloud")) {
        fallback <- SYNC_COMPARE_SOURCE_BACKUP
      }
      if (fallback %in% valid_values) return(fallback)

      if (length(valid_values) > 0) valid_values[[1]] else SYNC_COMPARE_SOURCE_BACKUP
    })

    compare_source_requested <- reactive({
      requested <- selected_compare_source()
      if (!isTRUE(is_authenticated()) && identical(requested, SYNC_COMPARE_SOURCE_CLOUD)) {
        return(SYNC_COMPARE_SOURCE_BACKUP)
      }
      requested
    })

    output$compare_source_ui <- renderUI({
      div(
        style = "min-width: 240px;",
        selectInput(
          ns("compare_source"),
          "Compare local changes against",
          choices = compare_source_choices(),
          selected = selected_compare_source()
        )
      )
    })

    clean_text <- function(value) {
      text <- as.character(value %||% "")
      if (!length(text) || is.na(text[[1]]) || !nzchar(trimws(text[[1]]))) return(NULL)
      text[[1]]
    }

    comparison_context <- reactive({
      pid <- current_project_id()
      baseline <- if (!is.null(pid) && nzchar(as.character(pid))) {
        tryCatch(project_get_baseline(con, pid), error = function(e) NULL)
      } else {
        NULL
      }
      source_info <- sync_resolve_compare_source(
        con,
        project_id = pid,
        compare_source = compare_source_requested()
      )

      source_ref <- NULL
      baseline_path <- NULL
      if (!is.null(baseline) && nrow(baseline) > 0) {
        source_ref <- clean_text(baseline$source_file_path[[1]]) %||% clean_text(baseline$baseline_path[[1]])
        baseline_path <- clean_text(baseline$baseline_path[[1]])
      }

      list(
        project_id = pid,
        baseline = baseline,
        source_info = source_info,
        backup_display = if (!is.null(source_ref) && nzchar(as.character(source_ref))) basename(as.character(source_ref)) else NULL,
        backup_path = baseline_path
      )
    })

    observe({
      pid <- current_project_id() %||% ""
      auth_key <- if (isTRUE(is_authenticated())) "auth" else "guest"
      pending_key <- paste(pending_project_merge_requests()$id %||% integer(0), collapse = ",")
      state_key <- paste(pid, auth_key, pending_key, sep = "::")
      if (!identical(rv_last_project(), state_key)) {
        rv_last_project(state_key)
        if (!selected_compare_source() %in% .flatten_choice_values(compare_source_choices())) {
          rv_compare_source_preference(default_compare_source(pid))
        }
        shinyjs::reset("backup_file")
      }
    })

    observe({
      pid <- current_project_id()
      auth_cloud_ready <- isTRUE(is_authenticated()) && isTRUE(sync_cloud_connected(con))
      previously_ready <- isTRUE(rv_last_auth_cloud_ready())

      if (auth_cloud_ready && !previously_ready) {
        rv_compare_source_preference(default_compare_source(pid))
      }

      rv_last_auth_cloud_ready(auth_cloud_ready)
    })

    observe({
      state$SyncCompareSource <- compare_source_requested()
    })

    output$project_badge <- renderUI({
      pid <- current_project_id()
      if (!is.null(pid) && nzchar(as.character(pid))) {
        span(class = "badge bg-primary", paste("Project:", pid))
      }
    })

    output$changes_snapshot <- renderUI({
      counts <- reactive_summary()$total
      actionButton(
        ns("open_updates_details"),
        label = tags$span(
          class = "action-label",
          div(
            class = "sync-summary-header",
            span(
              class = "sync-summary-titleline",
              icon("clipboard-list", class = "sync-card-label-icon"),
              span(class = "sync-summary-title", "Pending updates")
            ),
            span(class = "sync-summary-total", counts[["total"]] %||% 0L)
          ),
          div(
            class = "sync-summary-headline",
            span(class = "fw-bold text-dark", if ((counts[["total"]] %||% 0L) > 0L) "Review before push" else "No pending edits"),
            icon("chevron-right")
          ),
          div(class = "sync-summary-meta", "Open the expanded review to inspect site, soil, vegetation, and project changes in detail."),
          div(
            class = "sync-summary-grid",
            div(
              class = "sync-summary-chip is-insert",
              span(class = "sync-summary-chip-label", "New"),
              span(class = "sync-summary-chip-value", counts[["insert"]] %||% 0L)
            ),
            div(
              class = "sync-summary-chip is-update",
              span(class = "sync-summary-chip-label", "Updated"),
              span(class = "sync-summary-chip-value", counts[["update"]] %||% 0L)
            ),
            div(
              class = "sync-summary-chip is-delete",
              span(class = "sync-summary-chip-label", "Deleted"),
              span(class = "sync-summary-chip-value", counts[["delete"]] %||% 0L)
            )
          )
        ),
        class = "sync-summary-card btn btn-light"
      )
    })

    show_pending_updates_modal <- function() {
      showModal(modalDialog(
        title = "Pending updates",
        div(
          class = "sync-comparison-modal-shell",
          div(
            class = "sync-comparison-modal-intro",
            span(class = "sync-comparison-modal-kicker", "Change review"),
            span(class = "sync-comparison-modal-title", "Inspect every pending change before you push"),
            p(class = "sync-comparison-modal-note", "Review record-level changes by workflow area. You can still revert individual records or full sections from this window.")
          ),
          bslib::accordion(
            id = ns("acc_changes"),
            open = FALSE,
            bslib::accordion_panel(
              title = div(
                style = "display:inline-flex;align-items:center;",
                tagList(icon("map-location-dot"), " Site"),
                uiOutput(ns("badges_site"), inline = TRUE)
              ),
              value = "site",
              uiOutput(ns("section_actions_site")),
              uiOutput(ns("cards_admin")),
              uiOutput(ns("cards_env")),
              uiOutput(ns("cards_su"))
            ),
            bslib::accordion_panel(
              title = div(
                style = "display:inline-flex;align-items:center;",
                tagList(icon("layer-group"), " Soil"),
                uiOutput(ns("badges_soil"), inline = TRUE)
              ),
              value = "soil",
              uiOutput(ns("section_actions_soil")),
              uiOutput(ns("cards_humus")),
              uiOutput(ns("cards_mineral")),
              uiOutput(ns("cards_other"))
            ),
            bslib::accordion_panel(
              title = div(
                style = "display:inline-flex;align-items:center;",
                tagList(icon("leaf"), " Vegetation"),
                uiOutput(ns("badges_veg"), inline = TRUE)
              ),
              value = "veg",
              uiOutput(ns("section_actions_veg")),
              uiOutput(ns("cards_veg")),
              uiOutput(ns("cards_herbarium"))
            ),
            bslib::accordion_panel(
              title = div(
                style = "display:inline-flex;align-items:center;",
                tagList(icon("folder-open"), " Project"),
                uiOutput(ns("badges_project"), inline = TRUE)
              ),
              value = "project",
              uiOutput(ns("section_actions_project")),
              uiOutput(ns("cards_metadata"))
            )
          )
        ),
        easyClose = TRUE,
        size = "l",
        footer = modalButton("Close")
      ))
    }

    output$comparison_status <- renderUI({
      context <- comparison_context()
      pid <- context$project_id
      source_info <- context$source_info
      if (is.null(pid) || !nzchar(as.character(pid))) {
        return(div(class = "text-muted small sync-source-summary", "Open a project to review sync comparisons."))
      }

      tags$div(
        class = "sync-source-summary",
        div(
          class = "sync-source-badges",
          span(class = "sync-card-pill sync-card-pill-info", paste("Project:", pid)),
          span(class = "sync-card-pill sync-card-pill-neutral", paste("Using:", source_info$resolved_label)),
          if (identical(source_info$resolved_kind, "merge_request") && !is.null(source_info$resolved_merge_request_id)) {
            span(class = "sync-card-pill sync-card-pill-warn", paste("Pending MR:", source_info$resolved_merge_request_id))
          },
          if (!identical(source_info$requested, source_info$resolved)) {
            span(class = "sync-card-pill sync-card-pill-neutral", paste("Selected:", source_info$requested_label))
          },
          if (isTRUE(source_info$backup_available)) {
            span(class = "sync-card-pill sync-card-pill-info", "Backup registered")
          } else {
            span(class = "sync-status-pill sync-status-pill-muted", "No backup registered")
          }
        ),
        div(
          class = "small text-muted",
          if (!is.null(context$backup_display) && nzchar(context$backup_display)) {
            paste("Current backup file:", context$backup_display)
          } else {
            "Current backup file: none"
          }
        ),
        if (!is.null(source_info$fallback_reason) && nzchar(source_info$fallback_reason)) {
          div(class = "small text-muted mt-1", source_info$fallback_reason)
        },
        if (isTRUE(is_authenticated()) && !isTRUE(source_info$push_allowed) && nzchar(source_info$push_block_reason %||% "")) {
          div(class = "small text-muted mt-1", source_info$push_block_reason)
        }
      )
    })

    output$comparison_overview <- renderUI({
      context <- comparison_context()
      source_info <- context$source_info

      actionButton(
        ns("open_comparison"),
        label = tags$span(
          class = "d-block",
          span(
            class = "sync-comparison-label",
            icon("database", class = "sync-card-label-icon"),
            span("Current comparison baseline")
          ),
          tags$span(
            class = "sync-comparison-headline",
            tags$span(source_info$resolved_label %||% "Not set"),
            icon("chevron-right")
          ),
          tags$span(
            class = "sync-comparison-meta d-block",
            if (!is.null(context$backup_display) && nzchar(context$backup_display)) {
              paste("Backup file:", context$backup_display)
            } else if (isTRUE(source_info$cloud_available)) {
              "Using the current master comparison."
            } else {
              "Choose or replace the comparison source."
            }
          ),
          tags$span(
            class = "sync-comparison-badges",
            span(class = "sync-card-pill sync-card-pill-neutral", paste("Selected:", source_info$requested_label %||% source_info$resolved_label)),
            if (identical(source_info$resolved_kind, "merge_request") && !is.null(source_info$resolved_merge_request_id)) {
              span(class = "sync-card-pill sync-card-pill-warn", paste("MR", source_info$resolved_merge_request_id))
            }
          )
        ),
        class = "sync-comparison-card btn btn-light"
      )
    })

    output$merge_request_overview <- renderUI({
      project_rows <- pending_project_merge_requests()
      user_rows <- pending_user_merge_requests()

      latest_row <- if (!is.null(project_rows) && nrow(project_rows) > 0) {
        project_rows[1, , drop = FALSE]
      } else if (!is.null(user_rows) && nrow(user_rows) > 0) {
        user_rows[1, , drop = FALSE]
      } else {
        NULL
      }

      latest_title <- if (!is.null(latest_row) && nrow(latest_row) > 0) {
        sprintf("MR #%s", latest_row$id[[1]])
      } else if (!isTRUE(is_authenticated())) {
        "Sign in to review merge requests"
      } else {
        "No active merge request"
      }

      latest_meta <- if (!is.null(latest_row) && nrow(latest_row) > 0) {
        submitted_text <- latest_row$submitted_utc[[1]]
        sprintf(
          "%s for project %s with %s row%s.",
          as.character(submitted_text %||% "Recently submitted"),
          latest_row$project_id[[1]] %||% "",
          .merge_request_total_rows(latest_row$record_counts[[1]]),
          if (.merge_request_total_rows(latest_row$record_counts[[1]]) == 1) "" else "s"
        )
      } else if (!isTRUE(is_authenticated())) {
        "Merge requests are available after authentication and a successful push to master."
      } else {
        "Push local updates to create a merge request, or open this panel to review past submissions."
      }

      actionButton(
        ns("open_merge_requests"),
        label = tags$span(
          class = "action-label",
          span(
            class = "sync-merge-summary-label",
            icon("code-branch", class = "sync-card-label-icon"),
            span("Merge requests")
          ),
          tags$span(
            class = "sync-merge-summary-headline",
            tags$span(latest_title),
            icon("chevron-down")
          ),
          tags$span(class = "sync-merge-summary-meta d-block", latest_meta),
          tags$span(
            class = "sync-merge-summary-badges",
            span(class = "sync-card-pill sync-card-pill-neutral", paste("Project pending:", nrow(project_rows))),
            span(class = "sync-card-pill sync-card-pill-neutral", paste("My pending:", nrow(user_rows)))
          ),
          tags$span(
            class = "sync-merge-summary-stats",
            tags$span(
              class = "sync-merge-summary-stat",
              span(class = "sync-merge-summary-stat-label", "Current project"),
              span(class = "sync-merge-summary-stat-value", nrow(project_rows))
            ),
            tags$span(
              class = "sync-merge-summary-stat",
              span(class = "sync-merge-summary-stat-label", "All pending"),
              span(class = "sync-merge-summary-stat-value", nrow(user_rows))
            )
          )
        ),
        class = "sync-merge-summary-card btn btn-light"
      )
    })

    show_merge_requests_modal <- function() {
      showModal(modalDialog(
        title = "Merge requests",
        bslib::navset_pill(
          id = ns("merge_modal_tabs"),
          bslib::nav_panel(
            title = "My merge requests",
            value = "mine",
            div(
              class = "sync-merge-panel",
              div(
                class = "sync-merge-toolbar",
                checkboxInput(ns("hide_approved"), "Hide approved/merged", value = isTRUE(input$hide_approved)),
                checkboxInput(ns("hide_rejected"), "Hide rejected", value = isTRUE(input$hide_rejected)),
                actionButton(
                  ns("mr_refresh"),
                  label = tagList(icon("rotate"), "Refresh"),
                  class = "btn btn-outline-secondary btn-sm"
                )
              ),
              div(class = "sync-merge-table-wrap", DT::dataTableOutput(ns("tbl_mrs"))),
              uiOutput(ns("mr_detail"))
            )
          ),
          if (isTRUE(auth_is_admin(state))) {
            bslib::nav_panel(
              title = "Review queue",
              value = "review",
              div(
                class = "sync-merge-panel sync-merge-review-shell",
                mod_admin_merge_ui(ns("admin_merge"))
              )
            )
          }
        ),
        easyClose = TRUE,
        size = "l",
        footer = modalButton("Close")
      ))
    }

    reactive_summary <- reactive({
      rv_refresh()
      state$SyncVersion
      tryCatch(
        sync_get_pending_summary(
          con,
          project_id = current_project_id(),
          compare_source = compare_source_requested()
        ),
        error = function(e) {
          empty_counts <- c(insert = 0L, update = 0L, delete = 0L, total = 0L)
          list(
            by_table = setNames(replicate(length(SYNC_TABLE_CONFIG), empty_counts, simplify = FALSE), vapply(SYNC_TABLE_CONFIG, `[[`, character(1), "pg")),
            total = empty_counts
          )
        }
      )
    })

    has_any_changes <- reactive({
      reactive_summary()$total[["total"]] > 0L
    })

    # Disable/enable push button based on changes
    observe({
      source_info <- comparison_context()$source_info
      push_label <- if (!is_authenticated()) {
        tagList(icon("right-to-bracket"), "Sign in to push changes")
      } else {
        tagList(icon("cloud-arrow-up"), "Push changes")
      }
      updateActionButton(session, "sync_push", label = push_label)

      if (!is_authenticated()) {
        shinyjs::enable("sync_push")
      } else if (has_any_changes() && isTRUE(source_info$push_allowed)) {
        shinyjs::enable("sync_push")
      } else {
        shinyjs::disable("sync_push")
      }
      if (has_any_changes()) {
        shinyjs::enable("sync_revert_all")
      } else {
        shinyjs::disable("sync_revert_all")
      }
    })

    observeEvent(input$open_comparison, {
      showModal(modalDialog(
        title = "Comparison baseline",
        div(
          class = "sync-comparison-modal-shell",
          div(
            class = "sync-comparison-modal-intro",
            span(class = "sync-comparison-modal-kicker", "Comparison settings"),
            span(class = "sync-comparison-modal-title", "Choose the baseline for local updates"),
            p(
              class = "sync-comparison-modal-note",
              "Use Master, a backup file, or a pending merge request as the comparison source. Replace the backup only when you want to change the stored project baseline."
            )
          ),
          div(
            class = "sync-comparison-modal-grid",
            div(
              class = "sync-comparison-modal-card",
              div(class = "sync-comparison-modal-card-title", "Current selection"),
              uiOutput(ns("comparison_status"))
            ),
            div(
              class = "sync-comparison-modal-card",
              div(class = "sync-comparison-modal-card-title", "Choose source"),
              div(class = "sync-comparison-modal-card-subtitle", "Change what the current project compares against."),
              uiOutput(ns("compare_source_ui"))
            )
          ),
          div(
            class = "sync-comparison-modal-card sync-modal-upload",
            div(class = "sync-comparison-modal-card-title", "Backup file"),
            div(class = "sync-comparison-modal-card-subtitle", "Upload a canonical .db project backup, or a legacy .duckdb backup, to replace the saved comparison baseline for this project."),
            fileInput(
              ns("backup_file"),
              "Replace current backup file",
              accept = c(".db", ".duckdb"),
              buttonLabel = "Browse...",
              placeholder = "No file selected"
            )
          )
        ),
        easyClose = TRUE,
        size = "l",
        footer = modalButton("Close")
      ))
    }, ignoreInit = TRUE)

    observeEvent(input$open_updates_details, {
      show_pending_updates_modal()
    }, ignoreInit = TRUE)

    observeEvent(input$open_merge_requests, {
      show_merge_requests_modal()
    }, ignoreInit = TRUE)


    # ── Local changes reactive ────────────────────────────────────────────────
    reactive_changes <- reactive({
      rv_refresh()
      state$SyncVersion  # invalidation signal
      tryCatch(
        sync_get_local_changes(
          con,
          project_id = current_project_id(),
          compare_source = compare_source_requested()
        ),
        error = function(e) {
          setNames(
            lapply(c("admin","env","su","humus","mineral","other","veg","herbarium","metadata"),
                   function(x) data.frame(table_pg = character(0), change_type = character(0))),
            c("admin","env","su","humus","mineral","other","veg","herbarium","metadata")
          )
        }
      )
    })

    # ── Badge + diff card helpers ──────────────────────────────────────────────

    # Helper: count inserts/updates for a set of pg_names from reactive_changes()
    .section_counts <- function(pg_names) {
      reactive({
        summary <- reactive_summary()$by_table
        n_insert <- sum(vapply(pg_names, function(p) summary[[p]][["insert"]] %||% 0L, numeric(1)))
        n_update <- sum(vapply(pg_names, function(p) summary[[p]][["update"]] %||% 0L, numeric(1)))
        n_delete <- sum(vapply(pg_names, function(p) summary[[p]][["delete"]] %||% 0L, numeric(1)))
        c(insert = as.integer(n_insert), update = as.integer(n_update), delete = as.integer(n_delete))
      })
    }

    # Helper: renderUI that emits count badges (hidden when 0)
    .render_badges <- function(counts_rv) {
      renderUI({
        counts <- counts_rv()
        badges <- list()
        if (counts[["insert"]] > 0)
          badges <- c(badges, list(
            tags$span(
              class = "badge",
              style = "background:#43893e;color:#fff;",
              paste(counts[["insert"]], "new")
            )
          ))
        if (counts[["update"]] > 0)
          badges <- c(badges, list(
            tags$span(
              class = "badge",
              style = "background:#f9ca54;color:#222;",
              paste(counts[["update"]], "updated")
            )
          ))
        if (counts[["delete"]] > 0)
          badges <- c(badges, list(
            tags$span(
              class = "badge",
              style = "background:#c03b2b;color:#fff;",
              paste(counts[["delete"]], "deleted")
            )
          ))
        if (length(badges) == 0) return(NULL)
        div(class = "sync-section-badge", badges)
      })
    }

    counts_site    <- .section_counts(c("admin", "env", "su"))
    counts_soil    <- .section_counts(c("humus", "mineral", "other"))
    counts_veg     <- .section_counts(c("veg", "herbarium"))
    counts_project <- .section_counts(c("metadata"))

    output$badges_site    <- .render_badges(counts_site)
    output$badges_soil    <- .render_badges(counts_soil)
    output$badges_veg     <- .render_badges(counts_veg)
    output$badges_project <- .render_badges(counts_project)

    # ── Detailed change records ────────────────────────────────────────────────

    reactive_all_details <- reactive({
      rv_refresh()
      state$SyncVersion
      pid <- current_project_id()
      selected_source <- compare_source_requested()
      out <- list()
      for (cfg in SYNC_TABLE_CONFIG) {
        out[[cfg$pg]] <- tryCatch(
          sync_get_change_detail(con, cfg, project_id = pid, compare_source = selected_source),
          error = function(e) list()
        )
      }
      out
    })

    .records_for_tables <- function(pg_names) {
      details <- reactive_all_details()
      unlist(details[pg_names], recursive = FALSE, use.names = FALSE)
    }

    .count_change_types <- function(records) {
      counts <- c(insert = 0L, update = 0L, delete = 0L)
      if (length(records) == 0) return(counts)
      for (record in records) {
        change_type <- record$change_type %||% ""
        if (change_type %in% names(counts)) {
          counts[[change_type]] <- counts[[change_type]] + 1L
        }
      }
      counts
    }

    .change_badges <- function(counts) {
      tags$div(
        class = "d-inline-flex align-items-center gap-2 flex-wrap ms-2",
        if (counts[["insert"]] > 0) {
          tags$span(class = "badge", style = "background:#43893e;color:#fff;", sprintf("%d insert%s", counts[["insert"]], if (counts[["insert"]] == 1) "" else "s"))
        },
        if (counts[["update"]] > 0) {
          tags$span(class = "badge", style = "background:#f9ca54;color:#222;", sprintf("%d update%s", counts[["update"]], if (counts[["update"]] == 1) "" else "s"))
        },
        if (counts[["delete"]] > 0) {
          tags$span(class = "badge", style = "background:#c03b2b;color:#fff;", sprintf("%d delete%s", counts[["delete"]], if (counts[["delete"]] == 1) "" else "s"))
        }
      )
    }

    .format_counts <- function(counts) {
      count_parts <- character(0)
      if (!is.null(counts[["insert"]]) && counts[["insert"]] > 0) {
        count_parts <- c(count_parts, sprintf("%d insert%s", counts[["insert"]], if (counts[["insert"]] == 1) "" else "s"))
      }
      if (!is.null(counts[["update"]]) && counts[["update"]] > 0) {
        count_parts <- c(count_parts, sprintf("%d update%s", counts[["update"]], if (counts[["update"]] == 1) "" else "s"))
      }
      if (!is.null(counts[["delete"]]) && counts[["delete"]] > 0) {
        count_parts <- c(count_parts, sprintf("%d delete%s", counts[["delete"]], if (counts[["delete"]] == 1) "" else "s"))
      }
      if (length(count_parts) == 0) "no records" else paste(count_parts, collapse = ", ")
    }

    .set_sync_status <- function(message = NULL, counts = NULL, error = FALSE) {
      final_message <- message
      if (is.null(final_message) && !is.null(counts)) {
        final_message <- paste("Completed:", .format_counts(counts))
      }
      if (!is.null(final_message) && nzchar(as.character(final_message))) {
        show_toast(toast(final_message,
          type = if (isTRUE(error)) "danger" else "success",
          duration_s = if (isTRUE(error)) NA else 4
        ))
      }
      invisible(final_message)
    }

    observeEvent(input$compare_source, {
      rv_compare_source_preference(sync_normalize_compare_source(input$compare_source))
      rv_refresh(rv_refresh() + 1L)
    }, ignoreInit = TRUE)

    observeEvent(input$backup_file, {
      file_info <- input$backup_file
      pid <- current_project_id()

      if (is.null(file_info) || is.null(file_info$datapath) || !nzchar(file_info$datapath %||% "")) {
        return()
      }
      if (is.null(pid) || !nzchar(as.character(pid))) {
        .set_sync_status("Open a project before replacing the backup file.", error = TRUE)
        shinyjs::reset("backup_file")
        return()
      }
      file_ext <- tolower(tools::file_ext(file_info$name %||% ""))
      if (!(file_ext %in% c("db", "duckdb"))) {
        .set_sync_status("Backup file must be a .db project database or a legacy .duckdb backup.", error = TRUE)
        shinyjs::reset("backup_file")
        return()
      }

      tryCatch({
        project_replace_baseline_from_file(
          con,
          project_id = pid,
          source_path = file_info$datapath,
          source_file_path = file_info$name,
          source_kind = "sync_backup_upload"
        )
        sync_touch_state(state)
        rv_refresh(rv_refresh() + 1L)
        .set_sync_status(sprintf("Registered backup file for project %s: %s", pid, file_info$name), error = FALSE)
      }, error = function(e) {
        .set_sync_status(conditionMessage(e), error = TRUE)
      })

      shinyjs::reset("backup_file")
    }, ignoreInit = TRUE)

    .revert_records <- function(records, label = "changes") {
      if (length(records) == 0) {
        .set_sync_status(sprintf("No pending %s to revert.", label), counts = c(insert = 0L, update = 0L, delete = 0L), error = TRUE)
        return(invisible(FALSE))
      }

      dedupe_keys <- unique(vapply(records, function(record) paste(record$table_pg %||% "", record$pk_value %||% "", sep = "::"), character(1)))
      reverted_counts <- c(insert = 0L, update = 0L, delete = 0L)
      failures <- character(0)

      for (key in dedupe_keys) {
        parts <- strsplit(key, "::", fixed = TRUE)[[1]]
        result <- tryCatch(
          sync_revert_pending_change(
            con,
            table_name = parts[[1]],
            pk_value = parts[[2]],
            project_id = current_project_id()
          ),
          error = function(e) e
        )

        if (inherits(result, "error")) {
          failures <- c(failures, conditionMessage(result))
          next
        }

        change_type <- result$change_type %||% ""
        if (change_type %in% names(reverted_counts)) {
          reverted_counts[[change_type]] <- reverted_counts[[change_type]] + 1L
        }
      }

      if (sum(reverted_counts) > 0L) {
        sync_touch_state(state)
        rv_refresh(rv_refresh() + 1L)
        touch_site_hierarchy(records = records)
      }

      if (length(failures) > 0L) {
        .set_sync_status(
          sprintf("Reverted %d %s, with %d failure%s.", sum(reverted_counts), label, length(failures), if (length(failures) == 1) "" else "s"),
          counts = reverted_counts,
          error = TRUE
        )
      } else {
        .set_sync_status(
          counts = reverted_counts,
          error = FALSE
        )
      }

      invisible(length(failures) == 0L)
    }

    for (section_name in names(section_groups)) {
      local({
        .section_name <- section_name
        .button_id <- paste0("revert_all_", .section_name)
        output[[paste0("section_actions_", .section_name)]] <- renderUI({
          records <- .records_for_tables(section_groups[[.section_name]])
          if (length(records) == 0) return(NULL)
          div(
            class = "d-flex justify-content-end mb-2",
            actionButton(
              ns(.button_id),
              label = tagList(icon("rotate-left"), sprintf("Revert %s", .section_name)),
              class = "btn btn-outline-danger btn-sm"
            )
          )
        })

        observeEvent(input[[.button_id]], {
          .revert_records(.records_for_tables(section_groups[[.section_name]]), label = paste(.section_name, "changes"))
        }, ignoreInit = TRUE)
      })
    }

    # Helper: build one diff card HTML tag
    .build_diff_card <- function(record, pk) {
      is_insert <- identical(record$change_type, "insert")
      is_delete <- identical(record$change_type, "delete")
      before_data <- record$compare_data %||% record$core_data %||% record$baseline_data %||% record$delete_data
      card_class <- if (is_insert) {
        "sync-diff-card sync-insert"
      } else if (is_delete) {
        "sync-diff-card sync-delete"
      } else {
        "sync-diff-card sync-update"
      }
      badge_text <- if (is_insert) "INSERT" else if (is_delete) "DELETE" else "UPDATE"
      badge_col  <- if (is_insert) "#43893e" else if (is_delete) "#c03b2b" else "#f9ca54"
      badge_txt_col <- if (is_insert || is_delete) "#fff" else "#222"

      header <- div(
        class = "sync-diff-header",
        tags$span(
          class = "badge",
          style = paste0("background:", badge_col, ";color:", badge_txt_col, ";"),
          badge_text
        ),
        tags$span(class = "badge text-bg-light", record$compare_source_actual_label %||% "Comparison"),
        tags$span(class = "text-muted small text-uppercase", record$table_pg %||% ""),
        tags$span(paste(pk, "=", record$pk_value)),
        div(
          class = "sync-diff-actions",
          tags$button(
            type = "button",
            class = "btn btn-outline-secondary btn-sm",
            onclick = sprintf(
              "Shiny.setInputValue('%s', {table: '%s', pk: %s, nonce: Date.now()}, {priority: 'event'})",
              ns("revert_change"),
              record$table_pg %||% "",
              jsonlite::toJSON(as.character(record$pk_value), auto_unbox = TRUE)
            ),
            "Revert"
          )
        )
      )

      local_d <- record$local_data
      core_d  <- before_data
      pk_lc   <- tolower(pk)

      rows <- if (is_insert) {
        # show non-PK, non-null local fields
        field_names <- names(local_d)
        field_names <- field_names[tolower(field_names) != pk_lc]
        field_names <- field_names[vapply(field_names, function(f) {
          v <- local_d[[f]]
          !is.null(v) && length(v) > 0 && !is.na(v[1]) && nzchar(as.character(v[1]))
        }, logical(1))]
        lapply(field_names, function(f) {
          div(
            class = "sync-diff-row",
            span(class = "sync-diff-field", f),
            span(class = "sync-val-new", as.character(local_d[[f]]))
          )
        })
      } else if (is_delete) {
        field_names <- names(core_d %||% list())
        field_names <- field_names[tolower(field_names) != pk_lc]
        field_names <- field_names[vapply(field_names, function(f) {
          v <- core_d[[f]]
          !is.null(v) && length(v) > 0 && !is.na(v[1]) && nzchar(as.character(v[1]))
        }, logical(1))]
        lapply(field_names, function(f) {
          div(
            class = "sync-diff-row deleted",
            span(class = "sync-diff-field", f),
            span(class = "sync-val-delete", as.character(core_d[[f]]))
          )
        })
      } else {
        # show only fields that differ between local and core
        field_names <- names(local_d)
        field_names <- field_names[tolower(field_names) != pk_lc]
        diff_fields <- Filter(function(f) {
          lv <- as.character(local_d[[f]] %||% NA)
          cv <- if (!is.null(core_d) && f %in% names(core_d))
            as.character(core_d[[f]] %||% NA) else NA_character_
          !identical(lv, cv)
        }, field_names)
        if (length(diff_fields) == 0) {
          return(div(
            class = card_class,
            header,
            div(class = "sync-diff-body",
              div(class = "sync-diff-row",
                tags$em(class = "text-muted", "no field differences detected")
              )
            )
          ))
        }
        lapply(diff_fields, function(f) {
          lv <- as.character(local_d[[f]] %||% NA)
          cv <- if (!is.null(core_d) && f %in% names(core_d))
            as.character(core_d[[f]] %||% NA) else NA_character_
          div(
            class = "sync-diff-row changed",
            span(class = "sync-diff-field", f),
            span(class = "sync-val-before", cv),
            span(class = "sync-diff-arrow", "\u2192"),
            span(class = "sync-val-after",  lv)
          )
        })
      }

      div(
        class = card_class,
        header,
        div(class = "sync-diff-body", rows)
      )
    }

    # Helper: wire output$cards_<pg> for one table
    .render_cards_output <- function(pg_name, cfg) {
      output[[paste0("cards_", pg_name)]] <- renderUI({
        details <- reactive_all_details()[[pg_name]]
        if (is.null(details) || length(details) == 0) {
          return(div(class = "text-muted small py-2",
            paste0(pg_name, ": no local changes")
          ))
        }
        tagList(lapply(details, .build_diff_card, pk = cfg$pk))
      })
    }

    for (cfg in SYNC_TABLE_CONFIG) {
      local({
        .cfg <- cfg
        .render_cards_output(.cfg$pg, .cfg)
      })
    }
    observeEvent(input$revert_change, {
      info <- input$revert_change
      if (is.null(info$table) || is.null(info$pk)) return()

      tryCatch({
        result <- sync_revert_pending_change(
          con,
          table_name = as.character(info$table),
          pk_value = as.character(info$pk),
          project_id = current_project_id()
        )
        sync_touch_state(state)
        rv_refresh(rv_refresh() + 1L)
        touch_site_hierarchy(table_name = info$table)
        counts <- c(insert = 0L, update = 0L, delete = 0L)
        if ((result$change_type %||% "") %in% names(counts)) {
          counts[[result$change_type]] <- 1L
        }
        .set_sync_status(counts = counts, error = FALSE)
      }, error = function(e) {
        .set_sync_status(conditionMessage(e), error = TRUE)
      })
    }, ignoreInit = TRUE)

    observeEvent(input$sync_revert_all, {
      .revert_records(.records_for_tables(unname(unlist(section_groups))), label = "pending changes")
    }, ignoreInit = TRUE)


    # ── Push handler ─────────────────────────────────────────────────────────
    observeEvent(input$sync_push, {
      pid       <- current_project_id()
      submitter <- state$User %||% "unknown"
      pending_counts <- reactive_summary()$total[c("insert", "update", "delete")]
      selected_source <- compare_source_requested()
      selected_source_info <- comparison_context()$source_info

      if (!is_authenticated()) {
        state$SyncFocusAuthRequest <- as.numeric(Sys.time())
        .set_sync_status("Sign in within Sync to push changes.", error = FALSE)
        return()
      }
      if (!has_any_changes()) {
        .set_sync_status("No pending changes to push.", error = TRUE)
        return()
      }
      if (!isTRUE(selected_source_info$push_allowed)) {
        .set_sync_status(selected_source_info$push_block_reason %||% "Push is unavailable for the selected comparison source.", error = TRUE)
        return()
      }

      tryCatch({
        result <- sync_push(
          con,
          project_id = pid,
          submitter = submitter,
          compare_source = selected_source,
          target_merge_request_id = selected_source_info$resolved_merge_request_id
        )

        sync_touch_state(state)
        rv_refresh(rv_refresh() + 1L)
        rv_mr_reload(rv_mr_reload() + 1L)

        mr_id  <- result$merge_request_id %||% "?"
        counts <- result$counts %||% list()
        # Build per-table summary (omit tables with 0 rows)
        non_zero <- Filter(function(n) as.integer(n) > 0L, counts)
        count_str <- if (length(non_zero) > 0)
          paste(names(non_zero), unlist(non_zero), sep = ": ", collapse = ", ")
        else
          "no rows"

        msg <- if (isTRUE(result$updated_existing)) {
          sprintf("Updated MR #%s (%s).", mr_id, count_str)
        } else {
          sprintf("Push submitted \u2014 MR #%s (%s). Awaiting admin review.", mr_id, count_str)
        }
        rv_compare_source_preference(sync_compare_source_merge_request_value(mr_id))
        .set_sync_status(message = msg, counts = pending_counts, error = FALSE)
        show_merge_requests_modal()
      }, error = function(e) {
        .set_sync_status(conditionMessage(e), error = TRUE)
      })
    })


    # ── Merge requests panel ─────────────────────────────────────────────────
    reactive_mrs <- reactive({
      rv_mr_reload()
      state$SyncVersion
      sync_get_user_merge_requests(
        con,
        submitter     = state$User %||% "",
        show_approved = !isTRUE(input$hide_approved),
        show_rejected = !isTRUE(input$hide_rejected)
      )
    })

    output$mr_tab_badge <- renderUI({
      pending_rows <- pending_user_merge_requests()
      if (is.null(pending_rows) || nrow(pending_rows) == 0) return(NULL)
      span(class = "badge text-bg-warning ms-1", nrow(pending_rows))
    })

    selected_merge_request_row <- reactive({
      sel <- input$tbl_mrs_rows_selected
      df <- reactive_mrs()
      if (is.null(sel) || length(sel) == 0 || nrow(df) == 0 || sel > nrow(df)) return(NULL)
      df[sel, , drop = FALSE]
    })

    output$tbl_mrs <- DT::renderDataTable({
      df <- reactive_mrs()
      if (nrow(df) == 0) {
        return(DT::datatable(
          data.frame(Message = "No merge requests found."),
          rownames = FALSE,
          options  = list(dom = "t")
        ))
      }

      df$status_label <- dplyr::case_when(
        df$status == "pending_review" ~ "Pending",
        df$status == "merged"         ~ "Merged",
        df$status == "approved"       ~ "Approved",
        df$status == "rejected"       ~ "Rejected",
        TRUE                          ~ df$status
      )

      # Parse record_counts JSONB to compute total
      df$total_rows <- vapply(df$record_counts, function(rc) {
        tryCatch({
          nn <- jsonlite::fromJSON(rc %||% "{}")
          as.integer(sum(unlist(nn), na.rm = TRUE))
        }, error = function(e) NA_integer_)
      }, integer(1))

      display_cols <- intersect(
        c("id", "project_id", "submitted_utc", "status_label", "total_rows", "review_notes"),
        names(df)
      )

      DT::datatable(
        df[, display_cols, drop = FALSE],
        rownames  = FALSE,
        selection = "single",
        colnames  = c("ID", "Project", "Submitted", "Status", "Rows", "Review Notes")[seq_along(display_cols)],
        options   = list(pageLength = 20, scrollX = TRUE)
      ) |>
        DT::formatStyle(
          "status_label",
          target          = "row",
          backgroundColor = DT::styleEqual(
            c("Pending", "Merged", "Approved", "Rejected"),
            c("#fff3cd",  "#d4edda", "#d4edda",  "#f8d7da")
          )
        )
    })

    output$mr_detail <- renderUI({
      row <- selected_merge_request_row()
      if (is.null(row)) return(NULL)

      # Parse record_counts JSON -> per-table display
      counts_list <- tryCatch(
        jsonlite::fromJSON(row$record_counts[1] %||% "{}"),
        error = function(e) list()
      )
      count_rows <- if (length(counts_list) > 0) {
        tagList(
          tags$dt(class = "col-sm-3", "Rows by table"),
          tags$dd(class = "col-sm-9",
            tags$ul(
              class = "list-unstyled mb-0",
              lapply(names(counts_list), function(tbl)
                tags$li(paste0(tbl, ": ", counts_list[[tbl]]))
              )
            )
          )
        )
      } else {
        tagList(
          tags$dt(class = "col-sm-3", "Rows"),
          tags$dd(class = "col-sm-9", "—")
        )
      }

      notes   <- row$review_notes[1]
      rev_utc <- row$reviewed_utc[1]

      div(
        class = "card mt-3",
        div(
          class = "card-body",
          h6(class = "card-title", paste("MR #", row$id[1], "— detail")),
          tags$dl(
            class = "row mb-0",
            count_rows,
            tags$dt(class = "col-sm-3", "Reviewed"),
            tags$dd(class = "col-sm-9",
              if (!is.na(rev_utc) && !is.null(rev_utc)) as.character(rev_utc) else "—"
            ),
            tags$dt(class = "col-sm-3", "Review notes"),
            tags$dd(class = "col-sm-9",
              if (!is.na(notes) && nzchar(notes %||% "")) notes else "—"
            )
          ),
          if ((row$status[1] %||% "") %in% c("pending_review", "rejected")) {
            div(
              class = "mt-3",
              actionButton(
                ns("mr_delete"),
                label = tagList(icon("trash"), "Delete merge request"),
                class = "btn btn-outline-danger btn-sm"
              )
            )
          }
        )
      )
    })

    observeEvent(input$mr_delete, {
      row <- selected_merge_request_row()
      if (is.null(row)) return()
      rv_delete_merge_request_id(as.integer(row$id[[1]]))
      showModal(modalDialog(
        title = sprintf("Delete MR #%s", row$id[[1]]),
        sprintf("This will permanently remove merge request #%s and any staged rows attached to it.", row$id[[1]]),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("mr_delete_confirm"), "Delete", class = "btn btn-danger")
        )
      ))
    }, ignoreInit = TRUE)

    observeEvent(input$mr_delete_confirm, {
      mr_id <- rv_delete_merge_request_id()
      if (is.null(mr_id) || is.na(mr_id)) return()

      tryCatch({
        sync_delete_user_merge_request(con, mr_id, submitter = state$User %||% "")
        removeModal()
        rv_delete_merge_request_id(NULL)

        current_source <- compare_source_requested()
        current_source_parsed <- sync_compare_source_parse(current_source)
        if (identical(current_source_parsed$kind, "merge_request") && identical(current_source_parsed$merge_request_id, as.integer(mr_id))) {
          rv_compare_source_preference(default_compare_source(current_project_id()))
        }

        sync_touch_state(state)
        rv_refresh(rv_refresh() + 1L)
        rv_mr_reload(rv_mr_reload() + 1L)
        .set_sync_status(sprintf("Deleted MR #%s.", mr_id), error = FALSE)
      }, error = function(e) {
        removeModal()
        rv_delete_merge_request_id(NULL)
        .set_sync_status(conditionMessage(e), error = TRUE)
      })
    }, ignoreInit = TRUE)
  })
}
