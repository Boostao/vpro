# BEC Web Map - Published Datasets

This directory contains published RDS datasets for the BEC Map Explorer public interface.

## Dataset Format

Each published project consists of three RDS files:

### 1. `<project_id>_environment.rds`
Plot-level environmental data including:
- `plotnumber`: Unique plot identifier
- `date_sampled`: Collection date
- `latitude`, `longitude`: Geographic coordinates (decimal degrees)
- `bec_zone`, `bec_subzone`, `bec_site_series`: BEC classification
- `data_quality`: Quality rating (Poor, Fair, Good, Excellent)
- `_location`: Location description

**Required fields:** `latitude`, `longitude` (non-NULL, non-zero)

### 2. `<project_id>_vegetation.rds`
Species cover data:
- `plot_id`: Links to `plotnumber` in environment file
- `species_code`: Species identifier (e.g., PSME, PIPO)
- `layer`: Vegetation layer (A, B, C, D, E, F, G, H, I, M)
- `cover`: Cover value (numeric 0-100 or text code like `+`, `r`)

Optional but enables dominant species display.

### 3. `<project_id>_metadata.rds`
Project-level metadata:
- `project_id`: Unique project identifier
- `project_name`: Display name for project
- `is_public`: Boolean (TRUE for public access, FALSE for authenticated only)
- `primary_bec_zone`: Main BEC zone of project
- `description`: Project description

## Publishing Workflow

### Method 1: Script-Based Publishing

Use the provided script to publish a project from the VPRO database:

```bash
Rscript scripts/publish_dataset.R <project_id>
```

Example:
```bash
Rscript scripts/publish_dataset.R MKRF2023
```

This will extract data from the DuckDB database and create the three RDS files.

### Method 2: Manual Publishing

```r
# 1. Environment data
env <- data.frame(
  plotnumber = c("P1", "P2"),
  date_sampled = as.Date(c("2023-06-01", "2023-07-15")),
  latitude = c(49.5, 50.0),
  longitude = c(-120.0, -121.0),
  bec_zone = c("IDF", "MS"),
  bec_subzone = c("xh", "dm"),
  bec_site_series = c("01", "02"),
  data_quality = c("Good", "Excellent"),
  _location = c("Near Kamloops", "North of Revelstoke")
)
saveRDS(env, "data/published/MYPROJECT_environment.rds")

# 2. Vegetation data (optional)
veg <- data.frame(
  plot_id = c("P1", "P1", "P2"),
  species_code = c("PSME", "PIPO", "TSHE"),
  cover = c("60", "35", "70"),
  layer = c("A", "A", "A")
)
saveRDS(veg, "data/published/MYPROJECT_vegetation.rds")

# 3. Metadata
meta <- data.frame(
  project_id = "MYPROJECT",
  project_name = "My BEC Survey 2023",
  is_public = TRUE,
  primary_bec_zone = "IDF",
  description = "Survey of IDF and MS ecosystems"
)
saveRDS(meta, "data/published/MYPROJECT_metadata.rds")
```

## Access Control

The `is_public` flag in metadata controls visibility:
- **`is_public = TRUE`**: Visible to all users (public map interface)
- **`is_public = FALSE`**: Visible only to authenticated users (requires login)

When `auth_level = "public"` in the BEC Web Map module, only datasets with `is_public = TRUE` are loaded.

## File Naming Convention

**IMPORTANT**: All three files must share the same `<project_id>` prefix:

✅ **Correct:**
```
MKRF2023_environment.rds
MKRF2023_vegetation.rds
MKRF2023_metadata.rds
```

❌ **Incorrect:**
```
MKRF2023_environment.rds
MKRF2023veg.rds          # Wrong pattern
metadata_MKRF2023.rds    # Wrong pattern
```

## Data Quality Standards

### Coordinates
- Must use decimal degrees (WGS84 / EPSG:4326)
- Valid latitude: -90 to 90
- Valid longitude: -180 to 180
- BC typical ranges: lat 48-60, lon -139 to -114
- NULL or 0 coordinates will be filtered out

### BEC Classification
- Use standard BEC zone codes (IDF, BG, MS, ESSF, ICH, CDF, CWH, MH, BAFA, SBS, SBPS, SWB)
- Subzone codes should match official BECdb standards
- Site series codes typically 01-99

### Dates
- Use R Date class: `as.Date("2023-06-15")`
- ISO format recommended: YYYY-MM-DD

## Updating Published Data

To update a published dataset:

1. Delete the old RDS files for that project_id
2. Re-run the publishing script or manually save new RDS files
3. Refresh the BEC Map Explorer (app automatically detects new files on startup)

## Performance Considerations

- Keep individual datasets under 10,000 plots per project for optimal map performance
- Very large projects should be split geographically or temporally
- The map auto-clusters markers when > 100 plots are displayed
- Display is limited to 5000 plots max (filtered results)

## Troubleshooting

**"No datasets found"**
- Check that this directory exists: `data/published/`
- Verify file naming follows `<project_id>_<type>.rds` pattern
- Ensure at least `_environment.rds` file exists with valid coordinates

**"Plots not showing on map"**
- Verify `latitude` and `longitude` are numeric (not character)
- Check for NULL or 0 coordinate values
- Ensure coordinates are in decimal degrees (not UTM or DMS)

**"Dataset not visible in public mode"**
- Check `is_public = TRUE` in metadata file
- Verify metadata file exists and is named correctly

## Example Datasets

See `scripts/publish_dataset.R` for automated publishing from VPRO database.

For test/demo datasets, see `tests/testthat/test-mod_becweb_map.R` for minimal working examples.
