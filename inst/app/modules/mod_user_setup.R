# Module: User setup
# Access parity: frmRunOnce — "VPro Setup" dialog.
# Tab 1 (General): UserName text field, read-only Current Project / SU / Hierarchy,
#   explanatory labels, Continue + Cancel buttons.
# Tab 2 (Registry): AuditStrength setting.
# On Continue: saves user name and initial registry prefs via SaveSetting.
# In Shiny we persist the same values through the app configuration adapter (USysPrefs / yaml).

mod_user_setup_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::card(
    class = "h-100",
    full_screen = FALSE,
    bslib::card_header(
      shiny::tags$div(
        class = "d-flex justify-content-between align-items-center",
        shiny::tags$span(class = "fw-semibold", "VPro Setup"),
        shiny::actionButton(ns("btnCancel"), "Cancel", class = "btn btn-outline-secondary btn-sm")
      )
    ),
    bslib::card_body(
      bslib::navset_tab(
        id = ns("setup_tabs"),
        # ---- General tab (Access Page1) ----
        bslib::nav_panel(
          "General",
          shiny::tags$p(
            class = "text-muted small",
            "Please enter a user name. The user name will be used to log audit records."
          ),
          shiny::textInput(ns("UserName"), "User Name", value = ""),
          shiny::tags$hr(),
          shiny::tags$p(
            class = "text-muted small",
            "The following settings are initial entries which will be made into your registry.",
            "There will also be some entries made recording the size and location of some forms."
          ),
          bslib::layout_columns(
            shiny::tags$div(
              shiny::tags$label(class = "form-label", "Current Project"),
              shiny::verbatimTextOutput(ns("txtProject"))
            ),
            shiny::tags$div(
              shiny::tags$label(class = "form-label", "Current SU table"),
              shiny::verbatimTextOutput(ns("txtSU"))
            ),
            shiny::tags$div(
              shiny::tags$label(class = "form-label", "Current Hierarchy"),
              shiny::verbatimTextOutput(ns("txtHierarchy"))
            ),
            col_widths = c(4, 4, 4)
          ),
          shiny::tags$div(
            class = "d-flex gap-2 mt-3",
            shiny::actionButton(ns("btnContinue"), "Continue", class = "btn btn-primary btn-sm")
          )
        ),
        # ---- Registry tab (Access "Registry" page) ----
        bslib::nav_panel(
          "Registry",
          shiny::tags$p(class = "text-muted small", "Audit Strength:"),
          shiny::selectInput(
            ns("txtAuditStrength"),
            "Audit Strength",
            choices = c("0" = "0", "1" = "1", "2" = "2", "3" = "3"),
            selected = "1"
          )
        )
      ),
      shiny::textOutput(ns("status"))
    )
  )
}

mod_user_setup_server <- function(id, state, con) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    status_text <- shiny::reactiveVal("")

    # ---- Form_Load parity ----
    observeEvent(
      TRUE,
      {
        user <- app_config_get("Current", "User") %||% Sys.info()[["user"]] %||% ""
        shiny::updateTextInput(session, "UserName", value = user)
        audit <- app_config_get("Audit", "AuditStrength") %||% "1"
        shiny::updateSelectInput(session, "txtAuditStrength", selected = as.character(audit))
      },
      once = TRUE
    )

    output$txtProject <- shiny::renderText({
      state$CurrProject %||% app_config_get("Current", "CurrProject") %||% "Sample"
    })
    output$txtSU <- shiny::renderText({
      app_config_get("Current", "CurrPlotlist") %||% "None"
    })
    output$txtHierarchy <- shiny::renderText({
      app_config_get("Current", "CurrHierarchy") %||% "Sample"
    })

    # ---- Continue button (Access btnContinue_Click) ----
    observeEvent(input$btnContinue, {
      user_name <- trimws(input$UserName %||% "")
      if (!nzchar(user_name)) {
        status_text("Please enter a user name.")
        return()
      }
      # Save user name
      app_config_set("Current", "User", user_name)
      # Ensure default registry entries exist (Access SaveSetting parity)
      if (is.null(app_config_get("Current", "CurrProject")) || !nzchar(app_config_get("Current", "CurrProject"))) {
        app_config_set("Current", "CurrProject", "Sample")
      }
      if (is.null(app_config_get("Current", "CurrPlotlist")) || !nzchar(app_config_get("Current", "CurrPlotlist"))) {
        app_config_set("Current", "CurrPlotlist", "None")
      }
      if (is.null(app_config_get("Current", "CurrHierarchy")) || !nchar(app_config_get("Current", "CurrHierarchy"))) {
        app_config_set("Current", "CurrHierarchy", "Sample")
      }
      if (is.null(app_config_get("Current", "DataFormName")) || !nchar(app_config_get("Current", "DataFormName"))) {
        app_config_set("Current", "DataFormName", "FS882-6x4")
      }
      # Audit strength
      audit_val <- input$txtAuditStrength %||% "1"
      app_config_set("Audit", "AuditStrength", audit_val)

      status_text(sprintf("Setup saved for user '%s'.", user_name))
      show_toast(toast("Setup saved.", type = "success"))
    })

    # ---- Cancel button (Access btnCancel_Click -> DoCmd.Close) ----
    observeEvent(input$btnCancel, {
      return_tab <- state$DataEntryReturnTab %||% "fs882_6x4"
      bslib::nav_select("main_tabs", return_tab, session = session$rootScope())
    })

    output$status <- shiny::renderText(status_text())
  })
}
