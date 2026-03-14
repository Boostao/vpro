mod_nav_launcher_ui <- function(id, title, description = NULL, primary_label = "Open destination") {
  ns <- NS(id)

  bslib::card(
    class = "h-100",
    full_screen = FALSE,
    bslib::card_header(div(class = "fw-semibold", title)),
    bslib::card_body(
      if (!is.null(description) && nzchar(description)) {
        p(class = "text-muted", description)
      },
      div(
        class = "d-flex flex-wrap gap-2",
        actionButton(ns("open"), primary_label, class = "btn btn-primary btn-sm"),
        actionButton(ns("run"), "Run action", class = "btn btn-outline-secondary btn-sm")
      ),
      tags$p(
        class = "small text-muted mt-3 mb-0",
        "This launcher keeps menu behavior in-app while reusing existing VPro modules."
      ),
      shiny::singleton(
        tags$script(HTML(
          "
          Shiny.addCustomMessageHandler('vpro-nav-launcher-click', function(payload) {
            if (!payload || !payload.id) return;
            var el = document.getElementById(payload.id);
            if (el) { el.click(); }
          });
          "
        ))
      )
    )
  )
}

mod_nav_launcher_server <- function(
  id,
  open_main_tab = NULL,
  open_nested_tab_id = NULL,
  open_nested_value = NULL,
  click_id = NULL,
  run_notification = NULL
) {
  moduleServer(id, function(input, output, session) {
    root_session <- session$rootScope()

    observeEvent(input$open, {
      if (!is.null(open_main_tab) && nzchar(open_main_tab)) {
        bslib::nav_select("main_tabs", selected = open_main_tab, session = root_session)
      }

      if (!is.null(open_nested_tab_id) && nzchar(open_nested_tab_id) &&
          !is.null(open_nested_value) && nzchar(open_nested_value)) {
        bslib::nav_select(open_nested_tab_id, selected = open_nested_value, session = root_session)
      }
    }, ignoreInit = TRUE)

    observeEvent(input$run, {
      if (!is.null(click_id) && nzchar(click_id)) {
        session$sendCustomMessage("vpro-nav-launcher-click", list(id = click_id))
      }
      if (!is.null(run_notification) && nzchar(run_notification)) {
        showNotification(run_notification, type = "message")
      }
    }, ignoreInit = TRUE)

    # Hide the secondary action button when there is nothing to run.
    observe({
      if (is.null(click_id) || !nzchar(click_id)) {
        shinyjs::hide(session$ns("run"))
      }
    })

    invisible(NULL)
  })
}
