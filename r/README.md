# vpro 2.0: Quantitative Ecology and R Companion for VPro <a href="https://boostao.github.io/vpro/r/"><img src="man/figures/logo.svg" align="right" height="138" alt="vpro R package" /></a>

`vpro` is the R companion package and quantitative ecology engine for **VPro Desktop** under the British Columbia Ministry of Forests **Biogeoclimatic Ecosystem Classification (BEC)** Program.

## Installation

```r
# Recommended via pak (monorepo r/ subdirectory):
pak::pak("Boostao/vpro/r")

# Or via remotes:
remotes::install_github("Boostao/vpro", subdir = "r")
```

- **VPro Desktop Portal & Downloads:** <https://boostao.github.io/vpro/>
- **R Package Reference & Vignettes:** <https://boostao.github.io/vpro/r/>

Interactive FS882 and SIVI plot-card data entry, multi-plot datasheet editing, and 3D spatial mapping live in **VPro Desktop**; `vpro` gives quantitative ecologists and data custodians direct, read-safe programmatic access to local VPro project files (`.db`), portable self-contained `.rds` project snapshots, and the provincial **`BECMaster`** cloud service (`becmaster`, `staging`, and `standards` schemas) from R, Quarto, and `_targets`.

## Quick Start

```r
library(vpro)

# Connect to the live VPro workspace (or bundled 2026 Sample workspace)
ws <- vpro_connect("Sample")

# Extract tidy environment, lumped vegetation, and LMH25-ordered soil horizons
env  <- vpro_env(ws, exclude_modifiers = TRUE)
veg  <- vpro_veg(ws, strata = "total", lump = TRUE)
soil <- vpro_soil(ws)

# Build a vegan-ready plot x species community matrix with row-aligned env metadata
mat <- vpro_matrix(ws, transform = "sqrt")

# Run fuzzy noise clustering and round-trip candidate units back to VPro
cl <- vpro_cluster(ws, method = "vegclust_nc", k = 4)

# Compute BEC diagnostics, climate/aSMR, and dual 9x5 edatopic grids
diag_res <- vpro_diagnostics(ws)
asmr_df  <- vpro_asmr(ws, force_offline = TRUE)
ed       <- vpro_edatopic_grid(ws, mode = "dual", force_offline = TRUE)
vpro_plot_edatope(ed)
```

## Portable `.rds` Project Snapshots

Archive any VPro project—or open `.rds` project exports from VPro Desktop—as a self-contained `vpro_workspace` with full `BECdb v13`, `BCPlantTaxonomy v19`, and audit provenance:

```r
snap_file <- tempfile("bec-snapshot-", fileext = ".rds")
vpro_export_rds(ws, path = snap_file, snapshot_tag = "Sample_2026")

rds_ws <- vpro_import_rds(snap_file)
vpro_diagnostics(rds_ws, min_constancy = 50)
```

## Cloud `BECMaster` Queries, Contributor Staging, and Custodian Merge

When `BECMaster` cloud credentials (`VPRO_PG_*` or `becmaster.env` in `vpro_config_dir()`) are configured, contributors and provincial custodians can query `becmaster.*`, check out regional working subsets as local VPro `.db` files, stage validated plot edits, execute conflict-checked three-way merges with custodian-protected `Admin` field guards (`BECSiteUnit`, `BEC_Use`, `GIS_BGC`), and publish multi-format releases:

```r
if (vpro_has_pg_credentials("contributor")) {
  pg <- vpro_master_connect(role = "contributor")

  # Push-down cloud queries & self-cleaning analytical workspaces
  cwh_env  <- vpro_master_env(pg, zones = "CWH", subzones = "vm1")
  ws_cloud <- vpro_master_workspace(pg, zones = "CWH", subzones = "vm1")
  attr(vpro_master_audit(pg, limit = 500, verify_chain = TRUE), "chain_verification")$valid

  # Regional VPro project checkout & pre-flight-validated staging submission
  subset_pull <- vpro_master_pull(pg, dest_db = "CWHvm_2026.db", project = "CWHvm_2026", zones = "CWH", subzones = "vm1")
  vpro_staging_submit(pg, subset_pull$workspace, submitter = "Regional Ecologist")

  vpro_master_disconnect(pg)
}
```
