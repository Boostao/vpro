# Migration Prompts: VPro64 to R Shiny

Use these prompts sequentially to guide the migration. Each prompt represents a distinct unit of work.

## Current Database Architecture Note

These prompts were originally written around local DuckDB files as the main store. That is no longer the target local architecture.

- Canonical local storage is now SQLite under `data/`, `data/pics/`, and `data/projects/`.
- DuckDB should be treated as an in-memory boot-time query layer that attaches those SQLite files.
- Cross-database compatibility queries such as `MasterSiteUnitList` and `MasterUnitList_Hierarchy` should be recreated at app boot in the in-memory DuckDB session, not stored in the canonical SQLite files.

## Phase 1: Foundation

### Prompt 1: Project & Database Initialization
```text
I am migrating VPro64 to R Shiny.
1. Initialize structure: `app.R`, `global.R`, `R/`, `data/`, `www/`, `reports/`.
2. Packages: `shiny`, `duckdb`, `RSQLite`, `dplyr`, `dbplyr`, `bslib`, `DT`, `quarto`, `sf`, `janitor`.
3. Treat the migrated SQLite files as canonical local storage:
   - `data/VPro64.db`
   - `data/VLists.db`
   - `data/VMetaData.db`
   - `data/VUser.db`
   - `data/VMessageBoard.db`
   - `data/pics/VPics.db`
   - `data/projects/*.db` for project tables migrated from `Sample_*`
4. At app boot, open an in-memory DuckDB connection and attach those SQLite databases under stable aliases.
5. Create runtime-only compatibility views in the in-memory DuckDB layer for cross-database Access queries such as `MasterSiteUnitList` and `MasterUnitList_Hierarchy`.
```

### Prompt 2: Global State Management
```text
Replicate `V7mdlGlobalDeclarations` logic.
1. In `global.R`:
   - Initialize `SysState` reactiveValues.
   - Manage DB Connections: the app should use one in-memory DuckDB connection that attaches the canonical SQLite databases (`VPro64.db`, `VLists.db`, `VMetaData.db`, `VUser.db`, `VMessageBoard.db`, `pics/VPics.db`, plus project DBs from `data/projects/`).
2. Create `R/logic_state.R` with helper `set_project(id)`.
   - When project sets, query attached metadata/user/list databases through the in-memory DuckDB session.
```

## Phase 2: Core Data Entry

### Prompt 3: Main Navigation Shell
```text
Create `ui.R` / `server.R` shell.
1. `page_navbar` layout with title "VPro Shiny".
2. Generic Sidebar:
   - `selectInput("sel_project", ...)` sourced from `USysProjectMetadata`.
   - `selectInput("sel_su", ...)` filtered by project, sourced from `USysSuTable`.
   - TextOutput "Current Context".
3. Server: Populate choices from the in-memory DuckDB session over attached SQLite databases.
```

### Prompt 4: Vegetation Data Module (The Complex Grid)
```text
Create `R/mod_veg_sample.R`.
1. UI: Tabs for Layers A (Trees), B (Shrubs), C (Herbs), D (Moss).
   - *Architecture Note*: Consolidated from Access subforms `SubVegA`..`D`.
2. Data Source: 
   - **Read**: `Sample_Veg` table (Wide format) for direct grid editing to maintain 1:1 parity with Access storage.
   - *Note*: Use `vw_USysAllVeg` only for summary displays, NOT for the editing grid which needs the explicit Cover1..10 columns.
3. `DT` Implementation:
   - Display Species + `Cover1`..`Cover10` + `Height1`..`Height5`.
   - Column visibility: Only show relevant cols for the active Layer tab (e.g. Trees need Heights, Herbs might not).
   - Editable cells.
4. Logic:
   - "Save" button updates `Sample_Veg`.
```

### Prompt 5: Site & Environment Module
```text
Create `R/mod_site_env.R`.
1. UI: Tabs "Header", "Soil", "Mensuration".
   - *Architecture Note*: Consolidates `frmSIVIsite`, `SoilHumus`, `SoilMineral`.
   - Header: Inputs for `vw_USysEnv` fields (Lat/Long, Dates).
   - Soil: Nested Tabset for "Humus" (`Sample_Humus`) and "Mineral" (`Sample_Mineral`).
2. Server:
   - Load `Sample_Humus` for current plot.
   - Save logic for all tabs.
```

## Phase 3: Logic & Tools

### Prompt 6: Import/Export Engine
```text
Create `R/mod_export.R`.
1. UI: "Export R Dataset", "Export Venus".
2. Logic (Porting `V7mdlExportToR...`):
   - Query `vw_USysAllVeg`.
   - Pivot data to Wide format (Sites x Species).
   - Join with `vw_USysEnv`.
   - `downloadHandler` providing `.csv` or `.rds`.
```

### Prompt 7: Lumping Logic
```text
Port `V7mdlLumping`.
1. Create `R/logic_lumping.R`.
2. Function `apply_lumping(df, lump_table_id)`:
   - Read `Sample_Lump` / `USysLumpTable`.
   - Join to input data.
   - Group by `LumpCode` (synonym) and sum Covers.
```

## Phase 4: Reporting & Advanced

### Prompt 8: Quarto Reporting
```text
1. Create `reports/site_summary.qmd`.
   - Params: `plot_number`.
   - Query `vw_USysEnv` for header.
   - Query `vw_USysAllVeg` for species list.
2. Create `R/mod_reporting.R` to drive the render.
```

## Phase 5: Administration

### Prompt 9: Admin Tools
```text
Create `R/mod_admin.R`.
1. Project Metadata (`frmProjectMetaData`):
   - CRUD interface for `USysProjectMetadata`.
   - Allow adding new projects or editing survey dates.
2. Code Maintenance (`frmTableOfLists`):
   - Editable DT for `USysBeclabels` or `Sample_Lookups`.
   - Allow users to add valid codes for dropdowns.
```

### Prompt 9: Images & Maps
```text
1. `mod_images.R`:
   - Query `USysPictureBlob`.
   - UI: Gallery of images for current plot.
2. `logic_kml.R`:
   - Function to generate Google Earth KML from `USysEnv` coordinates.
```
