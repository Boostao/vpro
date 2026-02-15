mod_data_entry_context_server <- function(id, state, con, open_data_entry_trigger = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    observeEvent(open_data_entry_trigger(), {
      state$DataEntryOpenRequest <- list(
        close_forms = c("FS882-8x6XL", "FS882-1x1"),
        open_form = "FS882-6x4XL",
        requested_at = Sys.time()
      )
      state$CurrForm <- "FS882-6x4XL"
      state$sysCurrForm <- "FS882-6x4XL"
      set_pref(con, "Current", "DataFormName", "FS882-6x4XL")
    }, ignoreInit = TRUE)
  })
}
