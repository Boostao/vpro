mod_data_entry_context_server <- function(id, state, con, open_data_entry_trigger = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    observeEvent(open_data_entry_trigger(), {
      open_fs882_destination_context(
        state = state,
        con = con,
        form_name = "FS882-6x4XL",
        close_forms = c("FS882-8x6XL", "FS882-1x1")
      )
    }, ignoreInit = TRUE)
  })
}
