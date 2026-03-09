# Project Initialization Script
# Run this to set up dependencies

# Initialize renv for the project if not already done
# renv::init()

# List of required packages
required_packages <- c(
  "shiny",
  "duckdb",
  "dplyr",
  "dbplyr",
  "bslib", # Modern UI
  "DT"     # Data Tables
)

# Install packages
installed.packages() |> rownames() |> setdiff(x = required_packages) |> install.packages()
