# Shiny App Entrypoint
# Sources global, ui, and server definitions

source("global.R")
source("ui.R")
source("server.R")

shinyApp(ui = ui, server = server)
