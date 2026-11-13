# vpro 2.0: Companion R SDK & Quantitative Ecology Engine for VPro

`vpro` is the headless R companion package and scientific analytics engine for **`VPro` (`vpro_wails`)** under the British Columbia Ministry of Forests **Biogeoclimatic Ecosystem Classification (BEC)** Program.

Interactive plot-card data entry, datasheet editing, and 3D MapLibre/WebGPU spatial inspection live in the desktop `VPro` application; `vpro` gives quantitative ecologists direct, WAL-safe programmatic access to the same 7-database `VP08` SQLite workspace from R, Quarto, and `_targets`.

## Quick Start

```r
library(vpro)

# Connect to the live vpro_wails workspace (or bundled 2026 Sample workspace)
con <- vpro_sample()

# Extract tidy environment, lumped vegetation, and LMH25-ordered soil horizons
env  <- vpro_env(con, exclude_modifiers = TRUE)
veg  <- vpro_veg(con, strata = "total", lump = TRUE)
soil <- vpro_soil(con)

# Build a vegan-ready plot x species community matrix with row-aligned env metadata
mat <- vpro_matrix(con, transform = "sqrt")

# Run fuzzy noise clustering and round-trip candidate units back to VPro
cl <- vpro_cluster(con, method = "vegclust_nc", k = 4)

# Compute BEC diagnostics, climate/aSMR, and dual 9x5 edatopic grids
diag_res <- vpro_diagnostics(con)
asmr_df  <- vpro_asmr(con, force_offline = TRUE)
ed       <- vpro_edatopic_grid(con, mode = "dual", force_offline = TRUE)
plot_edatope(ed)
```
