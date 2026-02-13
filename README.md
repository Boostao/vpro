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

## Dependencies

**Required packages** (installed via renv):
- shiny, bslib, DT, rhandsontable, shinyjs, shinyTree
- duckdb, dplyr, dbplyr
- quarto (for report generation)
- testthat (for testing)

**Optional packages**:
- **climr** (bcgov/climr): Enables automatic climate data fetching for BC plot locations
  - Provides climate normals (MAT, MAP, MWMT, MCMT, etc.), BEC zone prediction, and elevation from DEM
  - Install: `remotes::install_github('bcgov/climr')`
  - If not installed, climate data features will be disabled with graceful degradation
  - See Site & Environment module for "Fetch Climate Data" button

## Usage

1. Run `scripts/01_build_database.R` to populate the DuckDB database (to be created).
2. Run the application using `shiny::runApp()`.

### Mobile Context sidebar

On narrow/mobile layouts, the **Context** sidebar (Project/Plot selectors) collapses into an off-canvas panel. Use the **Context** button to open/close it.

## Testing

- Unit and integration tests: `Rscript -e "testthat::test_dir('tests/testthat')"`
- UI regression tests (shinytest2):
	- Scaffold: `Rscript -e "shinytest2::use_shinytest2()"`
	- Record: `Rscript -e "shinytest2::record_test()"`
	- Run: `Rscript -e "testthat::test_dir('tests/testthat')"`

## Report Testing

When rendering Quarto reports from the terminal, use an absolute path for `db_path` because Quarto runs from the reports folder. Example:

```bash
Rscript -e "db_path <- normalizePath('data/vpro.duckdb', winslash='/', mustWork=TRUE); quarto::quarto_render('reports/short_veg_hierarchy.qmd', output_format='html', execute_params=list(plot_number='00000', plot_numbers='', site_unit='', project_id='', display_value='presence_mean', constancy_format=FALSE, db_path=db_path, project_root=getwd()))"
```

Or use the helper script:

```bash
scripts/render_report.sh short_veg_hierarchy.qmd --display presence_mean
```

If the Shiny app is running and holding the DuckDB write lock, use the in-app report preview (which renders from Parquet exports) or stop the app before rendering from the terminal.
