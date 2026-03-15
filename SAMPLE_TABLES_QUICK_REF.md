# VPRO Sample Tables - Quick Reference Guide

## Data Flow Diagram

```
                           ┌─────────────────────┐
                           │   Sample_Admin      │
                           │    [plot: PK]       │
                           └──────────┬──────────┘
                                      │
                        ┌─────────────┴──────────────┐
                        ▼                            ▼
         ┌──────────────────────────┐    ┌─────────────────┐
         │    Sample_Env            │    │ Sample_Metadata │
         │  [plotnumber: PK] ───────┼────┤   [id: PK]      │
         │  - location (lat/lon)    │    │ - projectid     │
         │  - BEC (zone, series)    │    │ - startdate     │
         │  - elevation, aspect     │    └────────┬────────┘
         │  - disturbance           │             │
         └────────┬────────┬────────┘             │
                  │        │                      ▼
      ┌───────────┼────────┼────────────────┐  ┌──────────────┐
      │           │        │                │  │  Sample_     │
      │           │        │                │  │ Hierarchy    │
      ▼           ▼        ▼                │  │  [id: PK]    │
   Sample_    Sample_   Sample_      Sample_│  └──────────────┘
   Humus      Mineral   Other         Veg   │
  [id:PK]    [id:PK]   [id:PK]     [id:PK] │
  ↓layer      ↓layer    ↓           ↓       │
   soil       soil      misc       species ◄┐
  humus     horizon    data         layer   │
                                           │
                    ┌───────────────┬──────┴─────────┐
                    │               │                │
                    ▼               ▼                ▼
            ┌──────────────┐  ┌─────────────┐  ┌──────────────┐
            │ Sample_      │  │ Sample_SU   │  │ Sample_      │
            │ Herbarium    │  │[plotnumber: │  │ Herbarium    │
            │[plotnumber: │  │  PK]        │  │[plotnumber:PK]
            │  PK]         │  │ - site unit │  │ - photo      │
            │ - photo      │  │   assgnmt   │  │ - specimen   │
            │ - specimen   │  └─────────────┘  │   records    │
            └──────────────┘                   └──────────────┘
                    │
                    │ (via species FK)
                    ▼
         ┌──────────────────────┐
         │  Sample_Profile      │
         │  [species: PK]       │
         │  - field, layer      │
         │  - criteria, op      │
         └──────────────────────┘

         ┌──────────────────────┐
         │  Sample_Lump         │  ◄────────┐
         │ [lumpcode: PK] ◄────────────────┤ (Species Grouping)
         │ - sppcode (FK)───────────────────────────┐
         └──────────────────────┘                   │
                                                    ▼
                                    ┌──────────────────────┐
                                    │  Sample_Theme        │
                                    │ [sppcode: PK]        │
                                    │ - lumpcode (FK)      │
                                    └──────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                          Sample_Audit [id: PK]                          │
│  Logs all edits across ALL Sample_ tables                               │
│  - _table: which table was edited                                       │
│  - editfield: which field changed                                       │
│  - beforeedit, afteredit: before/after values                           │
│  - _user: who made the change                                           │
│  - editwhen: when it was changed                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Primary Keys by Table

| Table | Primary Key | Type |
|-------|-------------|------|
| **Sample_Admin** | `plot` | VARCHAR (text identifier) |
| **Sample_Env** | `plotnumber` | VARCHAR (links to Sample_Admin) |
| **Sample_Humus** | `id` | BIGINT |
| **Sample_Mineral** | `id` | BIGINT |
| **Sample_Other** | `id` | BIGINT |
| **Sample_Veg** | `id` | BIGINT |
| **Sample_Herbarium** | `plotnumber` | VARCHAR |
| **Sample_SU** | `plotnumber` | VARCHAR |
| **Sample_Metadata** | `id` | BIGINT |
| **Sample_Hierarchy** | `id` | BIGINT |
| **Sample_Profile** | `species` | VARCHAR |
| **Sample_Lump** | `lumpcode` | VARCHAR |
| **Sample_Theme** | `sppcode` | VARCHAR |
| **Sample_Audit** | `id` | BIGINT |

---

## Foreign Key Relationships

### Chain: Sample_Admin → Sample_Env → Detail Tables

```
Sample_Admin.plot
    ↓ (rename to plotnumber in Sample_Env)
Sample_Env.plotnumber
    ├→ Sample_Humus.plotnumber
    ├→ Sample_Mineral.plotnumber
    ├→ Sample_Other.plotnumber
    ├→ Sample_Veg.plotnumber
    ├→ Sample_Herbarium.plotnumber
    └→ Sample_SU.plotnumber
```

### Metadata chain

```
Sample_Metadata.id
    ├→ Sample_Hierarchy.id
    ├→ Sample_Humus.id
    ├→ Sample_Mineral.id
    ├→ Sample_Other.id
    └→ Sample_Veg.id
```

### Species hierarchy

```
Sample_Veg.species
    ├→ Sample_Herbarium.species
    └→ Sample_Profile.species
```

### Lookup/reference

```
Sample_Profile.projectid → Sample_Metadata.projectid
Sample_Lump.sppcode ↔ Sample_Theme.sppcode (many-to-many)
```

---

## Query Patterns

### Get complete plot data (environmental + vegetation)

```sql
SELECT 
    a.plot,
    a.plottype,
    e.*,
    v.species,
    v.layer
FROM Sample_Admin a
JOIN Sample_Env e ON a.plot = e.plotnumber
LEFT JOIN Sample_Veg v ON e.plotnumber = v.plotnumber
WHERE a.plot = 'PLOT_ID'
```

### Get soil profile (humus + mineral)

```sql
SELECT
    e.plotnumber,
    h.horizon as humus_horizon,
    h.upperdepth as h_upper,
    h.lowerdepth as h_lower,
    m.horizon as mineral_horizon,
    m.upperdepth as m_upper,
    m.lowerdepth as m_lower
FROM Sample_Env e
LEFT JOIN Sample_Humus h ON e.plotnumber = h.plotnumber
LEFT JOIN Sample_Mineral m ON e.plotnumber = m.plotnumber
WHERE e.plotnumber = 'PLOT_ID'
```

### Get all edits for a plot (audit trail)

```sql
SELECT
    editwhen,
    _table,
    editfield,
    beforeedit,
    afteredit,
    _user
FROM Sample_Audit
WHERE plotnumber = 'PLOT_ID'
ORDER BY editwhen DESC
```

### Get species occurrences and metadata

```sql
SELECT
    v.plotnumber,
    v.species,
    v.layer,
    p.field,
    p.criteria,
    p.plotcount
FROM Sample_Veg v
LEFT JOIN Sample_Profile p ON v.species = p.species
WHERE v.species = 'SPECIES_CODE'
```

### Get lumped species groups

```sql
SELECT
    l.lumpcode,
    COUNT(DISTINCT t.sppcode) as species_count,
    GROUP_CONCAT(t.sppcode, ', ') as species_list
FROM Sample_Lump l
LEFT JOIN Sample_Theme t ON l.lumpcode = t.lumpcode
GROUP BY l.lumpcode
ORDER BY l.lumpcode
```

---

## Column Naming Conventions

### Metadata columns (underscore prefix)
- `_table`: Reference to source table
- `_user`: User identifier
- `_zone`: Zone designation
- `_order`: Ordering/sequence
- `_operator`: Operation type
- `_location`: Location designation

### Measurement columns (depth/distance)
- `upperdepth`, `lowerdepth`: Layer boundaries
- `utmeasting`, `utmnorthing`: UTM coordinates
- `slopegradient`: Slope as decimal
- `elevation`: Elevation in meters
- `plotsize`: Plot area (likely m²)

### Percentage/coverage columns
- `substratedecwood`, `substratebedrock`, `substraterocks`, `substratemineralsoil`, `substrateorganicmatter`, `substratewater`: % substrate

### Boolean/flag columns
- `sitemodifier2`: Boolean modifier
- `updatedfromcards`: Edit flag
- `restore`: Restoration flag
- `flag`: Generic flag (multiple uses)

### Code/reference columns
- `lumpcode`: Lumping group code
- `sppcode`: Species code
- `plotnumber`: Plot identifier
- `projectid`: Project code
- `becsiteunit`, `usersiteunit`: BEC site unit classifications

---

## Field Counts by Table

| Table | Column Count | Notable Fields |
|-------|---|---|
| Sample_Admin | 20 | plot, startdate, plottype, gis_bgc |
| Sample_Env | 78 | **Central table** - comprehensive site data |
| Sample_Humus | 5 | horizon, depth ranges |
| Sample_Mineral | 8 | horizon, depth, roots |
| Sample_Other | 1 | (minimal table) |
| Sample_Veg | 3 | plotnumber, species, layer |
| Sample_Herbarium | 3 | plotnumber, species, photo |
| Sample_SU | 1 | (minimal table) |
| Sample_Metadata | 3 | id, projectid, startdate |
| Sample_Hierarchy | 1 | (minimal table) |
| Sample_Profile | 6 | species, field, layer, criteria, operation, plotcount |
| Sample_Lump | 2 | lumpcode, sppcode |
| Sample_Theme | 2 | sppcode, lumpcode |
| Sample_Audit | 11 | Complete edit history |

---

## Data Quality Observations

- All columns allow NULL (no explicit NOT NULL constraints in DuckDB schema)
- No explicit UNIQUE constraints defined (relationships rely on naming convention)
- Audit table allows complete recovery of previous states
- No cascading delete relationships defined (orphaned records possible)
- Species hierarchy supports both individual species and grouped/lumped species

---

## Recommendations for Queries

1. **Always join through `plotnumber` in Sample_Env** — it's the central hub
2. **Use Sample_Metadata.id carefully** — multiple records per id possible
3. **Check Sample_Audit** when data inconsistencies occur
4. **Watch for NULL values** — all columns can be null
5. **Species lookups** — check both Sample_Profile (singular)

---

Generated from: `/Users/nicolas/Documents/GitHub/vpro/data/vpro.duckdb`
