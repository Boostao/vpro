# VPro64 R Shiny Migration

This project is a migration of the VPro64 Microsoft Access application to R Shiny.

The current local database strategy is:

- Canonical local storage lives in SQLite files under `data/` and `data/projects/`.
- DuckDB is the planned in-memory runtime query layer used to attach those SQLite databases at app boot.
- PostgreSQL remains a separate cloud/sync concern and does not replace the local canonical SQLite stores.

See `docs/database-runtime-strategy.md` for the current database architecture note.

## Structure

- **R/**: Shiny modules and helper functions.
- **data/**: Canonical SQLite companion databases (`VPro64.db`, `VLists.db`, `VMetaData.db`, `VUser.db`, `VMessageBoard.db`, `pics/VPics.db`) and per-project SQLite files in `data/projects/`.
- **www/**: Static assets (CSS, images).
- **scripts/**: Migration and maintenance scripts.
- **global.R**: App initialization and global state.
- **ui.R**: Main UI definition.
- **server.R**: Main server logic.

## Dependencies

**Required packages** (installed via renv):
- shiny, bslib, DT, rhandsontable, shinyjs, shinyTree
- duckdb, RSQLite, dplyr, dbplyr
- quarto (for report generation)
- testthat (for testing)

**Optional packages**:
- **climr** (bcgov/climr): Enables automatic climate data fetching for BC plot locations
  - Provides climate normals (MAT, MAP, MWMT, MCMT, etc.), BEC zone prediction, and elevation from DEM
  - Install: `remotes::install_github('bcgov/climr')`
  - If not installed, climate data features will be disabled with graceful degradation
  - See Site & Environment module for "Fetch Climate Data" button

## Usage

1. Treat the SQLite files under `data/` and `data/projects/` as the canonical migrated local databases.
2. Use `docs/database-runtime-strategy.md` as the reference for the upcoming in-memory DuckDB attachment layer.
3. Run the application using `shiny::runApp()`.

### Mobile Context sidebar

On narrow/mobile layouts, the **Context** sidebar (Project/Plot selectors) collapses into an off-canvas panel. Use the **Context** button to open/close it.

## Testing

- Unit and integration tests: `Rscript -e "testthat::test_dir('tests/testthat')"`
- UI regression tests (shinytest2):
	- Scaffold: `Rscript -e "shinytest2::use_shinytest2()"`
	- Record: `Rscript -e "shinytest2::record_test()"`
	- Run: `Rscript -e "testthat::test_dir('tests/testthat')"`

## Report Testing

When rendering Quarto reports from the terminal, use an absolute path for `db_path` because Quarto runs from the reports folder.

Transitional note: some report code paths in the repo still reference a direct DuckDB file path. Treat those examples as legacy until the report/runtime layer is moved over to the in-memory DuckDB + attached SQLite model described in `docs/database-runtime-strategy.md`.

Or use the helper script:

```bash
scripts/render_report.sh short_veg_hierarchy.qmd --display presence_mean
```

If the Shiny app is running and holding the active runtime connection, use the in-app report preview (which renders from Parquet exports) or stop the app before rendering from the terminal.
