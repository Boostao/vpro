# Project Initialization Script
# Run this to set up dependencies

if (!require("renv")) install.packages("renv")

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
install.packages(required_packages)

# Snapshot the state
renv::snapshot()
