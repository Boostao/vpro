mod_home_ui <- function(id) {
  ns <- NS(id)

  card(
    card_header("Welcome to VPro 64")
  )
  # tagList(
  #   uiOutput(ns("page")),
  #   tags$style(HTML("
  #     .vpro-home-shell {
  #       min-height: 0;
  #       display: grid;
  #       grid-template-rows: auto auto;
  #       gap: 0.68rem;
  #       padding: 0.1rem 0 0.25rem;
  #       color: #17344a;
  #     }
  #     .vpro-home-hero {
  #       display: grid;
  #       grid-template-columns: minmax(0, 1.28fr) minmax(20rem, 0.82fr);
  #       gap: 0.8rem;
  #     }
  #     .vpro-home-hero-main,
  #     .vpro-home-panel,
  #     .vpro-home-studio-card {
  #       position: relative;
  #       overflow: hidden;
  #       border-radius: 1.35rem;
  #       border: 1px solid rgba(13, 65, 119, 0.12);
  #       box-shadow: 0 18px 38px rgba(18, 38, 57, 0.08);
  #     }
  #     .vpro-home-hero-main {
  #       padding: 1rem 1.05rem 0.95rem;
  #       background:
  #         radial-gradient(circle at top right, rgba(255, 255, 255, 0.16), transparent 34%),
  #         linear-gradient(145deg, #0d4177 0%, #123e67 58%, #194d7f 100%);
  #       color: #ffffff;
  #     }
  #     .vpro-home-hero-main::after {
  #       content: '';
  #       position: absolute;
  #       right: -3rem;
  #       bottom: -4rem;
  #       width: 14rem;
  #       height: 14rem;
  #       border-radius: 999px;
  #       background: rgba(255, 255, 255, 0.08);
  #     }
  #     .vpro-home-hero-brand {
  #       display: inline-flex;
  #       align-items: center;
  #       gap: 0.75rem;
  #       position: relative;
  #       z-index: 1;
  #     }
  #     .vpro-home-brandmark {
  #       width: 8.8rem;
  #       max-width: 100%;
  #       height: auto;
  #       display: block;
  #       filter: brightness(0) invert(1);
  #     }
  #     .vpro-home-eyebrow {
  #       display: inline-flex;
  #       align-items: center;
  #       gap: 0.42rem;
  #       margin: 0;
  #       font-size: 0.68rem;
  #       letter-spacing: 0.1em;
  #       text-transform: uppercase;
  #       font-weight: 700;
  #       color: rgba(255, 255, 255, 0.78);
  #     }
  #     .vpro-home-hero-copy {
  #       position: relative;
  #       z-index: 1;
  #       display: grid;
  #       gap: 0.42rem;
  #       margin-top: 1.2rem;
  #       max-width: 36rem;
  #     }
  #     .vpro-home-hero-title {
  #       margin: 0;
  #       font-size: 2rem;
  #       line-height: 0.96;
  #       letter-spacing: -0.03em;
  #       font-weight: 800;
  #     }
  #     .vpro-home-hero-lead {
  #       margin: 0;
  #       font-size: 0.82rem;
  #       line-height: 1.45;
  #       color: rgba(255, 255, 255, 0.82);
  #       max-width: 34rem;
  #     }
  #     .vpro-home-glance-grid {
  #       position: relative;
  #       z-index: 1;
  #       display: grid;
  #       grid-template-columns: repeat(4, minmax(0, 1fr));
  #       gap: 0.5rem;
  #       margin-top: 1rem;
  #     }
  #     .vpro-home-glance-card {
  #       display: grid;
  #       gap: 0.18rem;
  #       padding: 0.62rem 0.7rem;
  #       border-radius: 1rem;
  #       background: rgba(255, 255, 255, 0.1);
  #       border: 1px solid rgba(255, 255, 255, 0.14);
  #       backdrop-filter: blur(8px);
  #     }
  #     .vpro-home-glance-label {
  #       font-size: 0.6rem;
  #       text-transform: uppercase;
  #       letter-spacing: 0.08em;
  #       color: rgba(255, 255, 255, 0.72);
  #       font-weight: 700;
  #     }
  #     .vpro-home-glance-value {
  #       font-size: 0.9rem;
  #       line-height: 1.1;
  #       font-weight: 700;
  #       color: #ffffff;
  #       white-space: nowrap;
  #       overflow: hidden;
  #       text-overflow: ellipsis;
  #     }
  #     .vpro-home-actions {
  #       position: relative;
  #       z-index: 1;
  #       display: grid;
  #       gap: 0.42rem;
  #     }
  #     .vpro-home-actions.is-split {
  #       grid-template-columns: repeat(3, minmax(0, 1fr));
  #       margin-top: 0.9rem;
  #     }
  #     .vpro-home-action-btn {
  #       display: inline-flex;
  #       align-items: center;
  #       justify-content: center;
  #       gap: 0.44rem;
  #       min-height: 2.5rem;
  #       padding: 0.5rem 0.72rem;
  #       border-radius: 999px;
  #       border: 1px solid rgba(13, 65, 119, 0.14);
  #       background: rgba(255, 255, 255, 0.9);
  #       color: #12395c;
  #       text-decoration: none;
  #       font-size: 0.74rem;
  #       font-weight: 700;
  #       box-shadow: 0 10px 24px rgba(18, 38, 57, 0.08);
  #       transition: transform 120ms ease, border-color 120ms ease, box-shadow 120ms ease, background 120ms ease;
  #     }
  #     .vpro-home-action-btn:hover,
  #     .vpro-home-action-btn:focus {
  #       transform: translateY(-1px);
  #       text-decoration: none;
  #       color: #12395c;
  #       background: #ffffff;
  #       border-color: rgba(13, 65, 119, 0.26);
  #       box-shadow: 0 14px 28px rgba(18, 38, 57, 0.12);
  #     }
  #     .vpro-home-action-btn.is-primary {
  #       background: linear-gradient(180deg, #f0b730 0%, #e0a619 100%);
  #       border-color: rgba(193, 138, 18, 0.45);
  #       color: #14344d;
  #     }
  #     .vpro-home-action-btn.is-primary:hover,
  #     .vpro-home-action-btn.is-primary:focus {
  #       color: #14344d;
  #       background: linear-gradient(180deg, #f4bf45 0%, #e4ab20 100%);
  #       border-color: rgba(193, 138, 18, 0.56);
  #     }
  #     .vpro-home-panel {
  #       display: grid;
  #       align-content: start;
  #       gap: 0.72rem;
  #       padding: 0.92rem 0.9rem;
  #       background: linear-gradient(180deg, #ffffff 0%, #f7fafc 100%);
  #     }
  #     .vpro-home-panel-head {
  #       display: grid;
  #       gap: 0.18rem;
  #     }
  #     .vpro-home-panel-kicker,
  #     .vpro-home-card-kicker {
  #       margin: 0;
  #       font-size: 0.62rem;
  #       letter-spacing: 0.09em;
  #       text-transform: uppercase;
  #       font-weight: 700;
  #       color: #6b7d8d;
  #     }
  #     .vpro-home-panel-title,
  #     .vpro-home-card-title {
  #       margin: 0;
  #       font-size: 1.05rem;
  #       line-height: 1.06;
  #       font-weight: 800;
  #       color: #15344c;
  #     }
  #     .vpro-home-panel-copy,
  #     .vpro-home-card-copy {
  #       margin: 0;
  #       font-size: 0.73rem;
  #       line-height: 1.34;
  #       color: #617687;
  #     }
  #     .vpro-home-session-focus {
  #       display: grid;
  #       gap: 0.24rem;
  #       padding: 0.88rem 0.9rem;
  #       border-radius: 1.05rem;
  #       background: linear-gradient(180deg, rgba(13, 65, 119, 0.06) 0%, rgba(255, 255, 255, 0.96) 100%);
  #       border: 1px solid rgba(13, 65, 119, 0.1);
  #     }
  #     .vpro-home-session-label {
  #       font-size: 0.6rem;
  #       letter-spacing: 0.08em;
  #       text-transform: uppercase;
  #       font-weight: 700;
  #       color: #6d7f8f;
  #     }
  #     .vpro-home-session-value {
  #       font-size: 1.02rem;
  #       line-height: 1.08;
  #       font-weight: 800;
  #       color: #0d4177;
  #       white-space: nowrap;
  #       overflow: hidden;
  #       text-overflow: ellipsis;
  #     }
  #     .vpro-home-session-note {
  #       margin: 0;
  #       font-size: 0.71rem;
  #       color: #607586;
  #     }
  #     .vpro-home-session-list {
  #       display: grid;
  #       gap: 0.42rem;
  #     }
  #     .vpro-home-session-item {
  #       display: grid;
  #       grid-template-columns: minmax(0, 1fr) auto;
  #       gap: 0.6rem;
  #       align-items: center;
  #       padding: 0.54rem 0.1rem;
  #       border-bottom: 1px solid rgba(13, 65, 119, 0.08);
  #     }
  #     .vpro-home-session-item:last-child {
  #       border-bottom: 0;
  #       padding-bottom: 0;
  #     }
  #     .vpro-home-session-item-label {
  #       font-size: 0.69rem;
  #       color: #688090;
  #     }
  #     .vpro-home-session-item-value {
  #       font-size: 0.73rem;
  #       font-weight: 700;
  #       color: #15344c;
  #     }
  #     .vpro-home-badge {
  #       display: inline-flex;
  #       align-items: center;
  #       gap: 0.35rem;
  #       border-radius: 999px;
  #       padding: 0.32rem 0.58rem;
  #       font-size: 0.66rem;
  #       font-weight: 700;
  #       border: 1px solid transparent;
  #       white-space: nowrap;
  #     }
  #     .vpro-home-badge.is-project,
  #     .vpro-home-badge.is-ready,
  #     .vpro-home-badge.is-live {
  #       background: rgba(13, 65, 119, 0.08);
  #       color: #18456a;
  #       border-color: rgba(13, 65, 119, 0.1);
  #     }
  #     .vpro-home-badge.is-warn {
  #       background: rgba(13, 65, 119, 0.1);
  #       color: #18456a;
  #       border-color: rgba(13, 65, 119, 0.12);
  #     }
  #     .vpro-home-badge.is-muted {
  #       background: #f3f7fa;
  #       color: #6a7d8d;
  #       border-color: rgba(13, 65, 119, 0.06);
  #     }
  #     .vpro-home-deck {
  #       min-height: 0;
  #       display: grid;
  #       grid-template-columns: minmax(0, 1.16fr) minmax(18rem, 0.72fr) minmax(0, 0.98fr);
  #       gap: 0.68rem;
  #     }
  #     .vpro-home-studio-card {
  #       min-width: 0;
  #       display: grid;
  #       align-content: start;
  #       gap: 0.62rem;
  #       padding: 0.8rem;
  #       background: linear-gradient(180deg, #ffffff 0%, #f9fbfd 100%);
  #     }
  #     .vpro-home-studio-card.is-sync {
  #       background: linear-gradient(180deg, #ffffff 0%, #fbfdff 100%);
  #     }
  #     .vpro-home-studio-card.is-deliver {
  #       background: linear-gradient(180deg, #f7fbff 0%, #ffffff 100%);
  #     }
  #     .vpro-home-tool-grid,
  #     .vpro-home-output-grid {
  #       display: grid;
  #       grid-template-columns: repeat(2, minmax(0, 1fr));
  #       gap: 0.42rem;
  #     }
  #     .vpro-home-tool-link,
  #     .vpro-home-output-link {
  #       display: grid;
  #       gap: 0.3rem;
  #       align-content: start;
  #       padding: 0.7rem 0.72rem;
  #       border-radius: 1rem;
  #       background: linear-gradient(180deg, #ffffff 0%, #fbfdff 100%);
  #       border: 1px solid rgba(13, 65, 119, 0.08);
  #       color: #17344a;
  #       text-decoration: none;
  #       box-shadow: 0 10px 24px rgba(18, 38, 57, 0.05);
  #       transition: transform 120ms ease, border-color 120ms ease, box-shadow 120ms ease, background 120ms ease;
  #     }
  #     .vpro-home-output-link {
  #       grid-template-columns: auto minmax(0, 1fr) auto;
  #       align-items: center;
  #       gap: 0.48rem;
  #     }
  #     .vpro-home-tool-link:hover,
  #     .vpro-home-tool-link:focus,
  #     .vpro-home-output-link:hover,
  #     .vpro-home-output-link:focus {
  #       transform: translateY(-1px);
  #       text-decoration: none;
  #       color: #17344a;
  #       background: #ffffff;
  #       border-color: rgba(13, 65, 119, 0.2);
  #       box-shadow: 0 14px 28px rgba(18, 38, 57, 0.1);
  #     }
  #     .vpro-home-tool-icon,
  #     .vpro-home-output-icon {
  #       width: 1.9rem;
  #       height: 1.9rem;
  #       display: inline-flex;
  #       align-items: center;
  #       justify-content: center;
  #       border-radius: 0.82rem;
  #       background: rgba(13, 65, 119, 0.08);
  #       color: #0d4177;
  #     }
  #     .vpro-home-tool-link.is-outline .vpro-home-tool-icon,
  #     .vpro-home-output-icon.is-gold {
  #       background: rgba(13, 65, 119, 0.12);
  #       color: #0d4177;
  #     }
  #     .vpro-home-tool-title,
  #     .vpro-home-output-title {
  #       margin: 0;
  #       font-size: 0.76rem;
  #       line-height: 1.18;
  #       font-weight: 700;
  #       color: #16344b;
  #     }
  #     .vpro-home-tool-note,
  #     .vpro-home-output-note {
  #       margin: 0;
  #       font-size: 0.62rem;
  #       line-height: 1.25;
  #       color: #64798a;
  #     }
  #     .vpro-home-output-arrow {
  #       color: #72869a;
  #       font-size: 0.76rem;
  #     }
  #     .vpro-home-sync-summary {
  #       display: grid;
  #       gap: 0.52rem;
  #       padding: 0.82rem;
  #       border: 1px solid #d7e3ea;
  #       border-radius: 1.08rem;
  #       background: #ffffff;
  #       box-shadow: 0 10px 26px rgba(16, 38, 56, 0.06);
  #     }
  #     .vpro-home-sync-summary-header {
  #       display: flex;
  #       align-items: flex-start;
  #       justify-content: space-between;
  #       gap: 0.65rem;
  #     }
  #     .vpro-home-sync-summary-titleline {
  #       display: inline-flex;
  #       align-items: center;
  #       gap: 0.45rem;
  #       font-size: 0.67rem;
  #       text-transform: uppercase;
  #       letter-spacing: 0.06em;
  #       color: #6b7785;
  #     }
  #     .vpro-home-sync-summary-title {
  #       font-size: 0.8rem;
  #       font-weight: 700;
  #       color: #18354d;
  #     }
  #     .vpro-home-sync-summary-total {
  #       font-size: 1.3rem;
  #       font-weight: 700;
  #       line-height: 1;
  #       color: #18354d;
  #     }
  #     .vpro-home-sync-summary-headline {
  #       display: flex;
  #       align-items: center;
  #       justify-content: space-between;
  #       gap: 0.6rem;
  #       font-weight: 700;
  #       color: #16344b;
  #     }
  #     .vpro-home-sync-summary-meta {
  #       margin: 0;
  #       font-size: 0.68rem;
  #       color: #5f6f7d;
  #       line-height: 1.3;
  #     }
  #     .vpro-home-pending-grid {
  #       display: grid;
  #       grid-template-columns: repeat(3, minmax(0, 1fr));
  #       gap: 0.38rem;
  #     }
  #     .vpro-home-pending-chip {
  #       display: grid;
  #       gap: 0.1rem;
  #       padding: 0.58rem 0.6rem;
  #       border-radius: 0.95rem;
  #       border: 1px solid rgba(13, 65, 119, 0.08);
  #       background: rgba(255, 255, 255, 0.86);
  #     }
  #     .vpro-home-pending-chip.is-insert {
  #       background: #edf7ea;
  #       border-color: #cfe4ca;
  #     }
  #     .vpro-home-pending-chip.is-update {
  #       background: #fff7de;
  #       border-color: #f1dfa2;
  #     }
  #     .vpro-home-pending-chip.is-delete {
  #       background: #edf4fb;
  #       border-color: #d4e1ec;
  #     }
  #     .vpro-home-pending-chip-label {
  #       font-size: 0.56rem;
  #       letter-spacing: 0.08em;
  #       text-transform: uppercase;
  #       font-weight: 700;
  #       color: #70808d;
  #     }
  #     .vpro-home-pending-chip-value {
  #       font-size: 0.86rem;
  #       line-height: 1.08;
  #       font-weight: 700;
  #       color: #18354d;
  #     }
  #     .vpro-home-inline-note {
  #       margin: 0;
  #       font-size: 0.71rem;
  #       color: #667b8b;
  #     }
  #     @media (max-width: 1020px) {
  #       .vpro-home-hero,
  #       .vpro-home-deck {
  #         grid-template-columns: 1fr;
  #       }
  #     }
  #     @media (max-width: 900px) {
  #       .vpro-home-glance-grid,
  #       .vpro-home-actions.is-split,
  #       .vpro-home-tool-grid,
  #       .vpro-home-output-grid,
  #       .vpro-home-pending-grid {
  #         grid-template-columns: repeat(2, minmax(0, 1fr));
  #       }
  #     }
  #     @media (max-width: 680px) {
  #       .vpro-home-glance-grid,
  #       .vpro-home-actions.is-split,
  #       .vpro-home-tool-grid,
  #       .vpro-home-output-grid,
  #       .vpro-home-pending-grid {
  #         grid-template-columns: 1fr;
  #       }
  #       .vpro-home-hero-title {
  #         font-size: 1.6rem;
  #       }
  #     }
  #   "))
  # )
}

mod_home_server <- function(id, state, con) {
  moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()

    #   normalize_text <- function(value) {
    #     value <- trimws(as.character(value %||% ""))
    #     if (!nzchar(value)) "" else value
    #   }

    #   click_id <- function(element_id, delay_ms = 120L) {
    #     shinyjs::runjs(sprintf(
    #       "window.setTimeout(function(){ var el = document.getElementById('%s'); if (el) { el.click(); } }, %d);",
    #       element_id,
    #       as.integer(delay_ms)
    #     ))
    #   }

    #   navigate_to <- function(tab) {
    #     bslib::nav_select("main_tabs", selected = tab, session = root_session)
    #     invisible(tab)
    #   }

    #   current_project <- reactive({
    #     normalize_text(state$CurrProject %||% state$PrefProject)
    #   })

    #   current_plot <- reactive({
    #     normalize_text(state$CurrSU)
    #   })

    #   project_scope <- reactive({
    #     state$SyncVersion
    #     state$HierarchyRefreshVersion
    #     project_id <- current_project()
    #     if (!nzchar(project_id)) {
    #       return(data.frame(plotnumber = character(0), siteunit = character(0), stringsAsFactors = FALSE))
    #     }
    #     tryCatch(
    #       read_project_site_unit_scope(con, project_id),
    #       error = function(e) data.frame(plotnumber = character(0), siteunit = character(0), stringsAsFactors = FALSE)
    #     )
    #   })

    #   open_projects <- reactive({
    #     tryCatch(list_open_projects(con), error = function(e) character(0))
    #   })

    #   pending_summary <- reactive({
    #     state$SyncVersion
    #     project_id <- current_project()
    #     if (!nzchar(project_id)) {
    #       return(list(total = c(insert = 0L, update = 0L, delete = 0L, total = 0L)))
    #     }
    #     tryCatch(
    #       sync_get_pending_summary(con, project_id = project_id, compare_source = state$SyncCompareSource %||% NULL),
    #       error = function(e) list(total = c(insert = 0L, update = 0L, delete = 0L, total = 0L))
    #     )
    #   })

    #   project_metrics <- reactive({
    #     scoped <- project_scope()
    #     list(
    #       plot_count = length(unique(scoped$plotnumber[nzchar(scoped$plotnumber)])),
    #       site_unit_count = length(unique(scoped$siteunit[nzchar(scoped$siteunit)]))
    #     )
    #   })

    #   badge <- function(label, icon_name = NULL, class_name = "is-muted") {
    #     div(
    #       class = paste("vpro-home-badge", class_name),
    #       if (!is.null(icon_name)) icon(icon_name),
    #       span(label)
    #     )
    #   }

    #   pill <- function(label, icon_name = NULL) {
    #     div(
    #       class = "vpro-home-pill",
    #       if (!is.null(icon_name)) icon(icon_name),
    #       span(label)
    #     )
    #   }

    #   action_btn <- function(id, label, icon_name, primary = FALSE) {
    #     actionLink(
    #       session$ns(id),
    #       label = tagList(icon(icon_name), label),
    #       class = paste("vpro-home-action-btn", if (isTRUE(primary)) "is-primary" else "")
    #     )
    #   }

    #   tool_link <- function(id, icon_name, title, note = NULL, accent = FALSE) {
    #     actionLink(
    #       session$ns(id),
    #       label = tagList(
    #         div(class = paste("vpro-home-tool-icon", if (isTRUE(accent)) "is-outline" else ""), icon(icon_name)),
    #         div(
    #           h4(class = "vpro-home-tool-title", title),
    #           if (!is.null(note)) p(class = "vpro-home-tool-note", note)
    #         )
    #       ),
    #       class = paste("vpro-home-tool-link", if (isTRUE(accent)) "is-outline" else "")
    #     )
    #   }

    #   output_link <- function(id, icon_name, title, note = NULL, gold = FALSE) {
    #     actionLink(
    #       session$ns(id),
    #       label = tagList(
    #         div(class = paste("vpro-home-output-icon", if (isTRUE(gold)) "is-gold" else ""), icon(icon_name)),
    #         div(
    #           h4(class = "vpro-home-output-title", title),
    #           if (!is.null(note)) p(class = "vpro-home-output-note", note)
    #         ),
    #         div(class = "vpro-home-output-arrow", icon("chevron-right"))
    #       ),
    #       class = "vpro-home-output-link"
    #     )
    #   }

    #   output$page <- renderUI({
    #     project_id <- current_project()
    #     plot_id <- current_plot()
    #     metrics <- project_metrics()
    #     pending <- pending_summary()$total
    #     pending_total <- pending[["total"]] %||% 0L
    #     pending_insert <- pending[["insert"]] %||% 0L
    #     pending_update <- pending[["update"]] %||% 0L
    #     open_count <- length(open_projects())
    #     auth_ready <- isTRUE(state$AuthAuthenticated)
    #     project_loaded <- nzchar(project_id)

    #     pending_delete <- pending[["delete"]] %||% 0L
    #     hero_title <- "Integrated data and classification management for BEC."
    #     hero_lead <- if (project_loaded) {
    #       "Manage BEC project data, site and vegetation classifications, sync review, and delivery outputs from one integrated workspace."
    #     } else {
    #       "Create or import a project, work through forms and classification tools, then review sync and generate outputs without leaving the main workflow."
    #     }
    #     session_title <- if (project_loaded) project_id else "No project selected"
    #     session_note <- if (nzchar(plot_id)) paste("Current plot", plot_id) else "No active plot selected"
    #     action_three_label <- if (project_loaded) "Project details" else "Open forms"
    #     plot_count_label <- if (metrics$plot_count == 1) "1 plot" else paste(metrics$plot_count, "plots")
    #     su_count_label <- if (metrics$site_unit_count == 1) "1 site unit" else paste(metrics$site_unit_count, "site units")
    #     open_count_label <- if (open_count == 1) "1 open project" else paste(open_count, "open projects")
    #     pending_message <- if (pending_total > 0) "Review pending site, vegetation, soil, and project changes before pushing." else "Open the expanded review to inspect pending changes before you push."

    #     div(
    #       class = "vpro-home-shell",
    #       div(
    #         class = "vpro-home-hero",
    #         div(
    #           class = "vpro-home-hero-main",
    #           div(
    #             class = "vpro-home-hero-brand",
    #             tags$img(class = "vpro-home-brandmark", src = "images/bcid-logo-en.svg", alt = "British Columbia")
    #           ),
    #           div(
    #             class = "vpro-home-hero-copy",
    #             p(class = "vpro-home-eyebrow", icon("house"), "VPro home"),
    #             h1(class = "vpro-home-hero-title", hero_title),
    #             p(class = "vpro-home-hero-lead", hero_lead)
    #           ),
    #           div(
    #             class = "vpro-home-glance-grid",
    #             div(
    #               class = "vpro-home-glance-card",
    #               div(class = "vpro-home-glance-label", "Project"),
    #               div(class = "vpro-home-glance-value", if (project_loaded) project_id else "Not loaded")
    #             ),
    #             div(
    #               class = "vpro-home-glance-card",
    #               div(class = "vpro-home-glance-label", "Field scope"),
    #               div(class = "vpro-home-glance-value", plot_count_label)
    #             ),
    #             div(
    #               class = "vpro-home-glance-card",
    #               div(class = "vpro-home-glance-label", "Pending"),
    #               div(class = "vpro-home-glance-value", if (pending_total > 0) paste(pending_total, "changes") else "All clear")
    #             ),
    #             div(
    #               class = "vpro-home-glance-card",
    #               div(class = "vpro-home-glance-label", "Sync"),
    #               div(class = "vpro-home-glance-value", if (auth_ready) "Signed in" else "Needs sign in")
    #             )
    #           ),
    #           div(
    #             class = "vpro-home-actions is-split",
    #             action_btn("create_project", "Create project", "folder-plus", primary = TRUE),
    #             action_btn("import_project", if (project_loaded) "Import another" else "Import project", "file-import"),
    #             if (project_loaded) {
    #               action_btn("edit_project", action_three_label, "pen-to-square")
    #             } else {
    #               action_btn("open_vegetation", action_three_label, "leaf")
    #             }
    #           )
    #         ),
    #         div(
    #           class = "vpro-home-panel",
    #           div(
    #             class = "vpro-home-panel-head",
    #             p(class = "vpro-home-panel-kicker", "Current session"),
    #             h2(class = "vpro-home-panel-title", "Where you are right now"),
    #             p(class = "vpro-home-panel-copy", "A compact read on the active project so you know what to open next.")
    #           ),
    #           div(
    #             class = "vpro-home-session-focus",
    #             div(class = "vpro-home-session-label", if (project_loaded) "Active project" else "Workspace status"),
    #             div(class = "vpro-home-session-value", session_title),
    #             p(class = "vpro-home-session-note", session_note)
    #           ),
    #           div(
    #             class = "vpro-home-session-list",
    #             div(
    #               class = "vpro-home-session-item",
    #               div(class = "vpro-home-session-item-label", "Open projects"),
    #               div(class = "vpro-home-session-item-value", open_count_label)
    #             ),
    #             div(
    #               class = "vpro-home-session-item",
    #               div(class = "vpro-home-session-item-label", "Site unit coverage"),
    #               div(class = "vpro-home-session-item-value", su_count_label)
    #             ),
    #             div(
    #               class = "vpro-home-session-item",
    #               div(class = "vpro-home-session-item-label", "Pending changes"),
    #               div(class = "vpro-home-session-item-value", if (pending_total > 0) paste(pending_total, "waiting") else "None")
    #             )
    #           ),
    #         )
    #       ),
    #       div(
    #         class = "vpro-home-deck",
    #         div(
    #           class = "vpro-home-studio-card",
    #           div(
    #             class = "vpro-home-card-head",
    #             div(
    #               class = "vpro-home-card-band",
    #               p(class = "vpro-home-card-kicker", "Workbench"),
    #               h3(class = "vpro-home-card-title", "Open a data tool"),
    #               p(class = "vpro-home-card-copy", "The field, vegetation, and hierarchy tools live here when you want to get straight to editing.")
    #             )
    #           ),
    #           div(
    #             class = "vpro-home-tool-grid",
    #             tool_link("open_fs882", "mountain", "FS882-6x4XL", "Main field form"),
    #             tool_link("open_vegetation", "leaf", "Vegetation", "Species and layers"),
    #             tool_link("open_su_table", "table", "Site unit tree", "Reference structure"),
    #             tool_link("open_hierarchy", "sitemap", "Hierarchy", "Navigate linked records", accent = TRUE)
    #           )
    #         ),
    #         div(
    #           class = "vpro-home-studio-card is-sync",
    #           div(
    #             class = "vpro-home-card-band",
    #             p(class = "vpro-home-card-kicker", "Sync"),
    #             h3(class = "vpro-home-card-title", "Push changes"),
    #             p(class = "vpro-home-card-copy", pending_message)
    #           ),
    #           div(
    #             class = "vpro-home-sync-summary",
    #             div(
    #               class = "vpro-home-sync-summary-header",
    #               div(
    #                 class = "vpro-home-sync-summary-titleline",
    #                 icon("clipboard-list"),
    #                 span(class = "vpro-home-sync-summary-title", "Pending updates")
    #               ),
    #               span(class = "vpro-home-sync-summary-total", pending_total)
    #             ),
    #             div(
    #               class = "vpro-home-sync-summary-headline",
    #               span(if (pending_total > 0) "Review before push" else "No pending edits"),
    #               icon("chevron-right")
    #             ),
    #             p(class = "vpro-home-sync-summary-meta", if (auth_ready) "Open the expanded review to inspect site, soil, vegetation, and project changes in detail." else "Open Sync to sign in and inspect pending site, soil, vegetation, and project changes in detail."),
    #             div(
    #               class = "vpro-home-pending-grid",
    #               div(
    #                 class = "vpro-home-pending-chip is-insert",
    #                 div(class = "vpro-home-pending-chip-label", "New"),
    #                 div(class = "vpro-home-pending-chip-value", pending_insert)
    #               ),
    #               div(
    #                 class = "vpro-home-pending-chip is-update",
    #                 div(class = "vpro-home-pending-chip-label", "Updated"),
    #                 div(class = "vpro-home-pending-chip-value", pending_update)
    #               ),
    #               div(
    #                 class = "vpro-home-pending-chip is-delete",
    #                 div(class = "vpro-home-pending-chip-label", "Deleted"),
    #                 div(class = "vpro-home-pending-chip-value", pending_delete)
    #               )
    #             )
    #           ),
    #           div(
    #             class = "vpro-home-actions",
    #             action_btn("sync_workspace", "Open Sync", "arrows-rotate")
    #           )
    #         ),
    #         div(
    #           class = "vpro-home-studio-card is-deliver",
    #           div(
    #             class = "vpro-home-card-band",
    #             p(class = "vpro-home-card-kicker", "Deliver"),
    #             h3(class = "vpro-home-card-title", "Export and report"),
    #             p(class = "vpro-home-card-copy", "Build the files, reports, maps, and location outputs you need when the project is ready to leave the workspace.")
    #           ),
    #           div(
    #             class = "vpro-home-output-grid",
    #             output_link("export_workspace", "file-export", "Export files", "Structured outputs"),
    #             output_link("reports_workspace", "file-lines", "Run reports", "Reporting workspace"),
    #             output_link("images_workspace", "map-location-dot", "Images and maps", "Visual deliverables"),
    #             output_link("plot_locations_workspace", "earth-americas", "Plot location KML", "Google Earth output")
    #           )
    #         )
    #       )
    #     )
    #   })

    #   observeEvent(input$create_project, {
    #     navigate_to("Vegetation")
    #     click_id("project-btn_new")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$import_project, {
    #     navigate_to("Import")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$edit_project, {
    #     navigate_to("project_metadata")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$open_fs882, {
    #     navigate_to("FS882-6x4XL")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$open_vegetation, {
    #     navigate_to("Vegetation")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$open_su_table, {
    #     navigate_to("SU Table")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$open_hierarchy, {
    #     navigate_to("Hierarchy")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$sync_workspace, {
    #     navigate_to("Sync")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$export_workspace, {
    #     navigate_to("Export")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$reports_workspace, {
    #     navigate_to("Reports")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$images_workspace, {
    #     navigate_to("Images & Maps")
    #   }, ignoreInit = TRUE)

    #   observeEvent(input$plot_locations_workspace, {
    #     navigate_to("report_show_plot_locations_google_earth")
    #   }, ignoreInit = TRUE)
  })
}
