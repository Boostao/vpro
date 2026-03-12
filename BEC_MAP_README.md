# BEC Web Map Explorer

**Public-facing interactive map for browsing published Biogeoclimatic Ecosystem Classification (BEC) plot data.**

## Overview

The BEC Web Map Explorer provides a geographic interface for discovering and exploring BEC vegetation and environmental data collected across British Columbia. Users can filter plots by location, date, species composition, and data quality, then export results for further analysis.

## Features

### Interactive Map
- **Leaflet-based** web map showing plot locations across BC
- **Marker clustering** for areas with high plot density (auto-activates for >100 plots)
- **Color-coded by BEC zone** for quick visual classification
- **Click popups** with plot summary information

### Advanced Filtering
- **BEC Classification**: Filter by zone (IDF, MS, ESSF, etc.) and subzone
- **Project Selection**: View plots from specific research projects
- **Date Range**: Temporal filtering from 1980s to present
- **Species Search**: Find plots containing specific species (e.g., "Pseudotsuga menziesii")
- **Data Quality**: Filter by quality rating (Good+, Excellent only, or all)

### Data Export
- **CSV Download**: Export filtered plot list with coordinates, BEC classification, and dominant species
- **Fields included**: Plot ID, Project, Date, Coordinates, BEC classification, Species counts, Quality rating

### Popup Information

Each plot marker displays:
- Plot ID and project name
- Collection date
- Full BEC classification (Zone/Subzone/Site Series)
- Dominant species (top 5 by cover) with layer designation
- Total species count
- Data quality rating

## Access the Map

1. **Launch the VPRO Shiny app**:
   ```bash
   Rscript -e "shiny::runApp('.', port = 3838)"
   ```

2. **Navigate to "BEC Map Explorer" tab**

3. **Apply filters** to explore the data:
   - Start broad (e.g., select a BEC zone)
   - Zoom to area of interest
   - Click markers for plot details
   - Refine filters as needed

4. **Export results**:
   - Click "Download CSV" to save filtered dataset

## Data Publishing

### For Administrators

To make a project dataset available on the public map:

```bash
Rscript scripts/publish_dataset.R <project_id>
```

Example:
```bash
Rscript scripts/publish_dataset.R MKRF2023
```

This extracts data from the VPRO DuckDB database and creates three RDS files in `data/published/`:
- `<project_id>_environment.rds` - Plot locations and environmental data
- `<project_id>_vegetation.rds` - Species cover data
- `<project_id>_metadata.rds` - Project information and access control

See [data/published/README.md](../data/published/README.md) for detailed publishing documentation.

### Access Control

Datasets can be marked as public or private via the `is_public` flag in metadata:
- **Public** (`is_public = TRUE`): Visible to all users
- **Private** (`is_public = FALSE`): Visible only to authenticated users

The BEC Map Explorer currently operates in public mode, showing only `is_public = TRUE` datasets.

## Performance

### Optimization Features
- **Lazy loading**: Datasets loaded only on app startup
- **In-memory caching**: Loaded data persists for session duration
- **Marker clustering**: Automatic clustering for >100 plots reduces map clutter
- **Result limiting**: Display capped at 5,000 plots with filter refinement prompts
- **Efficient filtering**: All filters use in-memory data operations

### Recommended Limits
- **Per-project dataset**: <10,000 plots
- **Total published**: <100,000 plots
- **Simultaneous users**: Tested with 10+ concurrent sessions

Large projects should be split geographically or temporally before publishing.

## Architecture

### Module Structure
- **UI**: `mod_becweb_map_ui()` in `R/mod_becweb_map.R`
- **Server**: `mod_becweb_map_server()` in `R/mod_becweb_map.R`
- **Data Source**: RDS files in `data/published/`
- **Integration**: Standalone tab, independent of project/plot context

### Data Flow
```
VPRO DuckDB Database
    ↓ (via publish_dataset.R)
data/published/*.rds files
    ↓ (on app startup)
In-memory cache (session reactive)
    ↓ (user filters)
Filtered plot data
    ↓
Leaflet map display
```

### Key Dependencies
- **leaflet**: Interactive web maps
- **bslib**: UI components
- **dplyr**: Data filtering

## Testing

Comprehensive test suite: `tests/testthat/test-mod_becweb_map.R`

Run tests:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-mod_becweb_map.R')"
```

**41 tests covering**:
- RDS dataset discovery and loading
- Filter logic (BEC, date, species, quality)
- Coordinate validation
- Color assignment by BEC zone
- Popup HTML generation
- CSV export structure
- Access control (public vs. private)
- Performance limits (clustering, max plots)

All tests passing ✅

## Extension Opportunities

### Planned Features
- **BEC polygon overlay**: Add official BEC boundary layers
- **Ecoregion boundaries**: Display ecoregion context
- **Photo thumbnails**: Show plot photos in popups
- **Report generation**: Create custom reports for selected area
- **Advanced search**: Query by environmental variables (elevation, aspect, soil type)

### Customization Hooks

The module includes extension points for advanced users:

```r
# In mod_becweb_map.R, add custom layers
observe({
  leafletProxy("map") %>%
    addPolygons(
      data = bec_boundaries_sf,
      color = "blue",
      weight = 2,
      fillOpacity = 0.1,
      group = "BEC Zones"
    )
})
```

## Troubleshooting

### "No plots to display"
- **Check**: Is `data/published/` directory empty?
- **Solution**: Run `scripts/publish_dataset.R` to publish a project

### "Too many results" warning
- **Cause**: Filter returned >5,000 plots
- **Solution**: Narrow filters (select specific BEC subzone, date range, or species)

### Plots not showing
- **Check**: Verify coordinates are valid decimal degrees
- **Check**: Ensure `latitude` and `longitude` are numeric (not character)
- **Check**: No NULL or 0 coordinate values

### Map not rendering
- **Check**: Browser console for errors
- **Check**: Leaflet JavaScript loaded (view page source)
- **Restart**: Refresh browser or restart Shiny app

## Credits

**Developed for**: BC Ministry of Forests - Biogeoclimatic Ecosystem Classification Program

**Requirements Source**: 
- `../VPRO_ACCESS/_BEC_data_system_fs1a_schedule_of_services_v2 (13).md`
- Schedule A - Services, Task 1b: "Build a map-based R-shiny tool for public access to BECMaster plot data and user download in multiple data formats"

**Related Systems**:
- [BECWeb](https://www.for.gov.bc.ca/hre/becweb/) - Official BEC classification guide
- [BEC_plots_Shiny](https://github.com/MoF-Skeena-Research/BEC_plots_Shiny.git) - Research prototypes
- VPro Access - Legacy field data entry system

## License

Part of the VPRO 2.0 Shiny application ecosystem.
