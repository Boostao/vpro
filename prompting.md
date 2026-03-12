# Migration Prompts: VPro64 to R Shiny

Use these prompts sequentially to guide the migration. Each prompt represents a distinct unit of work.

## Phase 1: Foundation

### Prompt 1: Project & Database Initialization
```text
I am migrating VPro64 to R Shiny.
1. Initialize structure: `app.R`, `global.R`, `R/`, `data/`, `www/`, `reports/`.
2. Packages: `shiny`, `duckdb`, `dplyr`, `dbplyr`, `bslib`, `DT`, `quarto`, `sf`, `janitor`.
3. Create `scripts/01_build_database.R` to ingest CSVs into 5 separate DuckDB files:
   - `data/vpro.duckdb`: From `../VPRO_ACCESS/VPro64_forAI/Tables_Data/` (Main Data).
   - `data/vpro_lists.duckdb`: From `../VPRO_ACCESS/VLists/Tables_Data/` (Reference Lists).
   - `data/vpro_metadata.duckdb`: From `../VPRO_ACCESS/VMetaData/Tables_Data/` (Project Meta).
   - `data/vpro_user.duckdb`: From `../VPRO_ACCESS/VUser/Tables_Data/` (User Prefs).
   - `data/vpro_messages.duckdb`: From `../VPRO_ACCESS/VMessageBoard/Tables_Data/` (Messages).
4. Create `scripts/02_create_views.R`:
   - View `vw_USysAllVeg`: UNION query combining `Cover1`..`Cover10`, `TotalA/B` from `Sample_Veg` into a normalized `(PlotNumber, MyLayer, Species, Cover)` structure.
   - View `vw_USysEnv`: JOIN `Sample_Env` and `Sample_Admin` on `PlotNumber`.
   - Run both scripts to prime the DBs.
```

### Prompt 2: Global State Management
```text
Replicate `V7mdlGlobalDeclarations` logic.
1. In `global.R`:
   - Initialize `SysState` reactiveValues.
   - Manage DB Connections: Note that we have 5 DBs. Main operations are on `vpro.duckdb`, but we need to `ATTACH 'data/vpro_lists.duckdb' AS lists` etc.
2. Create `R/logic_state.R` with helper `set_project(id)`.
   - When project sets, query `USysProjectMetadata` (from `vpro_metadata`) for defaults.
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
3. Server: Populate choices from DuckDB `USys...` tables.
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
