# Install required packages
install.packages(shiny)
install.packages(duckdb)
install.packages(yaml)
install.packages(dplyr)
install.packages(dbplyr)
install.packages(bslib)
install.packages(DT)
install.packages(rhandsontable)
install.packages(shinyjs)
install.packages(shinyTree)
install.packages(leaflet)
install.packages(sf)
install.packages(quarto)

# Install bcgov theme
source("./scripts/theme/add_bcgov_bootswatch_to_bslib.R")

# Initialize app databases
source("./initdb/initdb.R")

# Create default config file if it doesn't exist
if (!file.exists(Sys.getenv("VPRO_CONFIG_FILE", "./app/config.yml"))) {
  file.copy("./app/config.init.yml", Sys.getenv("VPRO_CONFIG_FILE", "./app/config.yml"))
}
