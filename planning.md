# VPro64 Migration Plan: Access to R Shiny + DuckDB

## Goal
Convert the complete VPro64 Microsoft Access application to a modern R Shiny application backed by DuckDB. This migration aims for feature parity, ensuring all forms, logic, and navigation flows are preserved while modernizing the backend and reporting engine.

## Context
- **Source Assets**: `VPRO_ACCESS/VPro64_forAI/` containing extracted CSV data, Form definitions, VBA modules, and Queries.
- **Target Stack**: R (Backend Logic), Shiny (UI), DuckDB (Embedded Database), Quarto (Reporting).

## Migration Strategy
- **Consolidation**: Access "Subforms" (e.g., `SubVegA`..`D`) are merged into their parent functionality (e.g., `mod_veg_sample`) as Tabs or Accordion items.
- **Database Topology**: Mirroring the Access split-database architecture using multiple attached DuckDB files:
    - `vpro.duckdb`: Main Project Data (`Sample_*`, `USys*` local).
    - `vpro_lists.duckdb`: Reference Data (`USysTableOfLists`, `USysSiteSeriesNames`).
    - `vpro_metadata.duckdb`: Central Project Registry.
    - `vpro_user.duckdb`: User Preferences.
    - `vpro_messages.duckdb`: System Messages.
- **System Forms**: Operational forms (`Splash`, `Progress`, `Directories`) are replaced by native Shiny/R architecture.
- **Dialogs**: Popups (`PickItem`, `AddSpp`) become Shiny Modals.
- **Layout**: "Responsive Design" replaces specific print-size layouts (`FS882-6x4` etc.).

## Execution Steps

### Phase 1: Foundation & Data Architecture
1.  **Project Initialization**:
    -   Setup R Shiny structure (`app.R`, `global.R`, `R/`, `data/`, `www/`, `reports/`).
    -   Configure `renv` with core libraries (`shiny`, `duckdb`, `dplyr`, `dbplyr`, `bslib`, `DT`, `quarto`, `sf`, `janitor`).
2.  **Database Migration**:
    -   Script `01_build_database.R`: Ingest CSVs from multiple sources:
        -   `VPro64` -> `data/vpro.duckdb`
        -   `VLists` -> `data/vpro_lists.duckdb`
        -   `VMetaData` -> `data/vpro_metadata.duckdb`
        -   `VUser` -> `data/vpro_user.duckdb`
        -   `VMessageBoard` -> `data/vpro_messages.duckdb`
    -   Script `02_create_views.R`: Replicate key Access Unions within `vpro.duckdb` (ATTACH other DBs if needed).
        -   **`vw_USysAllVeg`**: The critical "Unpivot" view. It must UNION `Cover1..10`, `TotalA`, `TotalB`, etc. into a normalized layer-based structure (`PlotNumber`, `MyLayer`, `Species`, `Cover`). Reference `Queries/USysAllVeg.txt` for the exact logic.
        -   **`vw_USysEnv`**: Join `Sample_Env` and `Sample_Admin` (and likely `Sample_SU`) to create the master environment table matching `Queries/USysEnv.txt`.
3.  **Global State Management**:
    -   Replicate `V7mdlGlobalDeclarations` in `global.R` or `R/logic_state.R`.
    -   **Multi-DB**: Logic to `ATTACH` auxiliary databases on connection.
    -   **Context**: `sysCurrProject`, `sysCurrSU`, `sysCurrHierarchy` (Classification).
    -   **Lumping Settings**: `sysLumpingTable`.

### Phase 2: Core Data Entry Forms
1.  **Navigation Shell (`ui_shell`)**:
    -   Recreate `frmMainMenuFloat` layout.
    -   Sidebar: "Context Selector" filtering `USysProjectMetadata` (from `vpro_metadata`) -> `Sample_SU` (via `USysSuTable`).
2.  **Vegetation Data Module (`mod_veg_sample`)**:
    -   **Source**: `frmVegSample` and its subforms (`SubVegA`, `SubVegC`, `SubVegD`).
    -   **UI**: 
        -   Tabbed interface for layers (Trees, Shrubs, Herbs, Mosses).
        -   **Grid**: Use `DT` with editable cells. Columns must map to `Sample_Veg` wide format (`Cover1`...`Cover10`) for 1:1 compatibility.
    -   **Logic**: Saving data must write back to the specific `CoverX` columns in `Sample_Veg`.
3.  **Site & Environmental Module (`mod_site_env`)**:
    -   **Source**: `frmSIVIsite` (The "Main" Site form).
    -   **Tabs**:
        -   **Header**: `Sample_Env` (Location, Dates, Surveyors).
        -   **Soil**: `Sample_Humus`, `Sample_Mineral` (formerly `SoilHumus`, `SoilMineral` subforms).
        -   **Mensuration**: `Sample_Mensuration` (if present, or columns in Env).
    -   **Lookups**: Use `vpro_lists.duckdb` -> `USysTableOfLists` for dropdowns.

### Phase 3: Business Logic & Processing
1.  **Lumping Engine (`logic_lumping`)**:
    -   **Source**: `V7mdlLumping.txt` and `USysLumpTable`.
    -   Implement function `apply_lumping(species_code, lump_table_id)` to resolve synonyms.
2.  **Export Engine (`mod_export`)**:
    -   **Source**: `V7mdlExportToR...` and `V7mdlExportCompactNew`.
    -   Implement `export_to_r_dataset()`: Generates the "Wide" matrix expected by ecologists.
    -   Implement `export_venus()`: XML generation for the VENUS format.
3.  **Import Engine (`mod_import`)**:
    -   Replace `V7mdlAttach...` with a robust CSV/Excel importer.
    -   Allow uploading a ZIP of CSVs (VPro export format) to merge into the DuckDB.

### Phase 4: Reporting System (Quarto)
1.  **Dynamic Reporting**:
    -   Replace `Reports/USysSiteUnitReport.txt` (and similar) with `reports/site_summary.qmd`.
    -   **Features**: One-page-per-site PDF generation including:
        -   Header data (`vw_USysEnv`).
        -   Formatted Veg table (`vw_USysAllVeg` repivoted for display).
        -   Photos (`USysPictureBlob`).

### Phase 5: Advanced Tools
1.  **Image Management (`mod_images`)**:
    -   **Source**: `frmPlotPictures`, `USysPictureBlob`.
    -   Display images stored in binary blobs (decoding required) or mapped file paths.
2.  **Google Earth KML (`logic_kml`)**:
    -   **Source**: `V7mdlGoogleEarth`.
    -   Generate `.kml` files from Lat/Long in `vw_USysEnv`.
3.  **Hierarchy Tools**:
    -   Manage the `Sample_Hierarchy` recursively.

### Phase 6: Administration
1.  **Project Metadata Editor (`mod_admin_project`)**:
    -   **Source**: `frmProjectMetaData`.
    -   CRUD interface for `USysProjectMetadata` (Projects, Surveys, Dates).
2.  **Code Maintenance (`mod_admin_codes`)**:
    -   **Source**: `frmTableOfLists`.
    -   Interface to edit `USysBeclabels` (valid codes for dropdowns).

