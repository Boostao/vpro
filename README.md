# VPro64 R Shiny Migration

This project is a migration of the VPro64 Microsoft Access application to R Shiny with a DuckDB backend.

## Structure

- **R/**: Shiny modules and helper functions.
- **data/**: Database files (`vpro.duckdb`).
- **www/**: Static assets (CSS, images).
- **scripts/**: Migration and maintenance scripts.
- **global.R**: App initialization and global state.
- **ui.R**: Main UI definition.
- **server.R**: Main server logic.

## Usage

1. Run `scripts/01_build_database.R` to populate the DuckDB database (to be created).
2. Run the application using `shiny::runApp()`.

## Testing

- Unit and integration tests: `Rscript -e "testthat::test_dir('tests/testthat')"`
- UI regression tests (shinytest2):
	- Scaffold: `Rscript -e "shinytest2::use_shinytest2()"`
	- Record: `Rscript -e "shinytest2::record_test()"`
	- Run: `Rscript -e "testthat::test_dir('tests/testthat')"`
