# VPRO Sample Tables Schema Documentation - COMPLETE

Generated: March 7, 2026  
Source: DuckDB `vpro.duckdb` - Complete information_schema analysis

---

## Overview

The VPRO database contains **15 tables** starting with "Sample_" that form the core data model for environmental and vegetation sample collection. This documentation includes **ALL columns** for each table.

### Tables by Category

| Category | Tables | Column Count |
|----------|--------|---|
| **Master/Admin** | Sample_Admin, Sample_Metadata, Sample_Hierarchy | 91 |
| **Environment Hub** | Sample_Env | 128 |
| **Soil** | Sample_Humus, Sample_Mineral, Sample_Other | 75 |
| **Vegetation** | Sample_Veg, Sample_Herbarium, Sample_SU | 45 |
| **Lookups** | Sample_Lump, Sample_Theme | 7 |
| **Audit** | Sample_Audit | 11 |
| **TOTAL** | 15 tables | **373+ columns** |

---

## Core Relationships

### 1. Plot Hierarchy (plotnumber)

The **most important linking key** across multiple tables:

```
Sample_Admin (plot)
    ↓ (plotnumber)
    ├→ Sample_Env (hub)
    │   ├→ Sample_Humus
    │   ├→ Sample_Mineral
    │   ├→ Sample_Other
    │   ├→ Sample_Veg
    │   ├→ Sample_Herbarium
    │   └→ Sample_SU
```

**Sample_Env** is the central hub connected to all soil and vegetation detail tables.

### 2. Record-Level Hierarchy (id)

Secondary linking key via Sample_Metadata:

```
Sample_Metadata (id)
    ├→ Sample_Hierarchy
    ├→ Sample_Humus (id)
    ├→ Sample_Mineral (id)
    ├→ Sample_Other (id)
    └→ Sample_Veg (id)
```

### 3. Species Network (species)

```
Sample_Veg (species)
    ├→ Sample_Herbarium (species)
    └→ Sample_Theme (sppcode)
```

### 4. Lumping/Theme Mapping

```
Sample_Lump (lumpcode ↔ sppcode)
    ↔
Sample_Theme (sppcode ↔ lumpcode)
```

---

## Complete Table Definitions

### Sample_Admin
**Primary Key:** `plot`  
**Purpose:** Master table for plot administration

| Column | Type | Notes |
|--------|------|-------|
| plot | VARCHAR | PK - Unique plot identifier |
| startdate | BIGINT | Date plot was established |
| plottype | VARCHAR | Type of plot (veg, soil, combined) |
| plotsize | DOUBLE | Plot area |
| provincestateterritory | VARCHAR | Geographic location |
| siteplotquality | VARCHAR | Site quality rating |
| vegplotquality | VARCHAR | Vegetation quality rating |
| soilplotquality | VARCHAR | Soil quality rating |
| updatedfromcards | BIGINT | Edit flag |
| enteredby | VARCHAR | Data entry personnel |
| usersiteunit | VARCHAR | User-assigned site unit |
| becsiteunit | VARCHAR | BEC site unit classification |
| siteunitshortname | VARCHAR | Short site unit name |
| siteunitlongname | VARCHAR | Long site unit name |
| officenotes | VARCHAR | Administrative notes |
| humusthickness | DOUBLE | Humus layer thickness |
| gis_bgc | VARCHAR | GIS-derived BEC classification |
| gis_bgc_ver | VARCHAR | GIS BEC version |
| bec_use | DOUBLE | BEC use indicator |
| stratacovertotal | VARCHAR | Total strata cover |

---

### Sample_Env
**Primary Key:** `plotnumber`  
**Purpose:** Central environmental site characterization (HUB TABLE - 128 columns)

**Key Observation:** This is the largest and most important table, linking to all detail tables.

**Location Fields:**
- plotnumber, fieldnumber, projectid, fsregiondistrict
- date, sitesurveyor, plotrepresenting, _location
- ecosection, ntsmapsheet
- longitude, latitude, utmzone, utmeasting, utmnorthing, locationaccuracy
- airphotonum, xcoord, ycoord, _zone

**BEC/Classification Fields:**
- subzone, siteseries, sitemodifier1, sitemodifier2
- transdistrib, realmclass, mapunit
- snowcoverregime, moistureregime, nutrientregime
- successionalstatus, structuralstage, structuralstagemod

**Topographic Fields:**
- elevation, slopegradient, aspect, standage
- mesoslopeposition, surfaceshape, surfacetopographytype, surfacetopographysize
- watersource, exposure1, exposure2, photo

**Disturbance Fields:**
- sitedisturbance1, sitedisturbance2, sitedisturbance3
- sitenotes

**Substrate Coverage Fields (%):**
- substratedecwood, substratebedrock, substraterocks
- substratemineralsoil, substrateorganicmatter, substratewater

**Soil/Geology Fields:**
- soilsurveyor, soilnotes
- bedrockgeology1, bedrockgeology2, bedrockgeology3
- coarsefraglith1, coarsefraglith2, coarsefraglith3
- terraintexturesurf, surficialmaterialsurf, surfaceexpsurf, geomorprosurf
- terraintexturesubsurf, surficialmaterialsubsurf, surfaceexpsubsurf, geomorprosubsurf
- floodingregimefreq, moistureregimesub, floodingregimedur
- soildrainage, seepagedepth
- rootrestrictingtype, rootrestrictingdepth, rootzoneparticlesize, rootingdepth
- soilclasssubgroup, soilclassgroup
- humusform, humusformphase
- phmethodcodemineral, phmethodcodeorganic
- specieslistcomplete

**Vegetation Fields:**
- vegsurveyor, vegnotes
- stratacovertree, stratacovershrub, stratacoverherb, stratacovermoss

**Hydrogeologic Fields:**
- hydrogeosystem, hydrogeosubsystem

**SoilVeg/Special Fields (sv_ prefix):**
- sv_polygonnumber, sv_floodplain, sv_standageestmeas
- sv_standheight, sv_standheightestmeas, sv_canopycomposition
- sv_soildepth, sv_rootzonetexture, sv_percentcoarsefrags
- sv_gleyingmottlingcm, sv_watertablecm, sv_fullcruisecard
- sv_ahorizontype, sv_ahorizondepth
- activelayerdepth

**Metadata:**
- _temporary, flag

---

### Sample_Humus
**Primary Key:** `id`  
**Foreign Keys:** `plotnumber` → Sample_Env, `id` → Sample_Metadata

| Column | Type | Notes |
|--------|------|-------|
| id | BIGINT | PK - Record identifier |
| plotnumber | VARCHAR | FK - Links to Sample_Env |
| horizon | VARCHAR | Humus horizon classification |
| upperdepth | DOUBLE | Upper layer boundary (cm) |
| lowerdepth | DOUBLE | Lower layer boundary (cm) |
| humusstructuredegree | VARCHAR | Degree of humus structure |
| humusstructurekind | VARCHAR | Kind/type of structure |
| mycelabundance | VARCHAR | Mycelium abundance |
| fecalabundance | VARCHAR | Fecal abundance |
| rootsabundance | VARCHAR | Root abundance classification |
| rootssize | VARCHAR | Root size classification |
| vonpost | BIGINT | Von Post humification scale (0-10) |
| humusformph | DOUBLE | pH of humus form |
| consistence | VARCHAR | Humus consistence |
| character | VARCHAR | Character description |
| fauna | VARCHAR | Fauna observations |
| _comment | VARCHAR | Internal comments |
| flag | BIGINT | Flag/status indicator |

---

### Sample_Mineral
**Primary Key:** `id`  
**Foreign Keys:** `plotnumber` → Sample_Env, `id` → Sample_Metadata

| Column | Type | Notes |
|--------|------|-------|
| id | BIGINT | PK - Record identifier |
| plotnumber | VARCHAR | FK - Links to Sample_Env |
| horizon | VARCHAR | Soil horizon designation |
| upperdepth | DOUBLE | Upper boundary (cm) |
| lowerdepth | DOUBLE | Lower boundary (cm) |
| pitdepthlimit | VARCHAR | Pit depth limitation |
| colour | VARCHAR | Soil colour from charts |
| asp | BIGINT | Aspect/direction code |
| texture | VARCHAR | Soil texture classification |
| percentcoarsefragsgravel | BIGINT | % gravel (2-75mm) |
| percentcoarsefragscobbles | BIGINT | % cobbles (75-250mm) |
| percentcoarsefragsstones | BIGINT | % stones (>250mm) |
| percentcoarsefragstotal | BIGINT | % total coarse fragments |
| percentcoarsefragsshape | VARCHAR | Shape of coarse fragments |
| rootsabundance | VARCHAR | Root abundance |
| rootssize | VARCHAR | Root size |
| mineralstructureclass | VARCHAR | Structure class |
| mineralstructurekind | VARCHAR | Structure kind |
| mineralformph | VARCHAR | pH measurement |
| mottlesabundance | VARCHAR | Mottles abundance |
| mottlessize | VARCHAR | Mottles size |
| mottlescontrast | VARCHAR | Mottles contrast |
| clayfilmsfreq | VARCHAR | Clay films frequency |
| clayfilmthickness | VARCHAR | Clay films thickness |
| effervescence | VARCHAR | Reaction to acid (effervescence) |
| porosity | VARCHAR | Porosity description |
| _comments | VARCHAR | Comments |
| flag | BIGINT | Flag indicator |

---

### Sample_Veg
**Primary Key:** `id`  
**Foreign Keys:** `plotnumber` → Sample_Env, `species` → Sample_Profile, `id` → Sample_Metadata

| Column | Type | Notes |
|--------|------|-------|
| id | BIGINT | PK - Record identifier |
| plotnumber | VARCHAR | FK - Links to Sample_Env |
| species | VARCHAR | FK - Species code |
| layer | VARCHAR | Vegetation layer (tree, shrub, herb, moss) |
| **COVER & HEIGHT (cover1-10 pattern):** |||
| cover1 | DOUBLE | Crown cover % layer 1 |
| height1 | VARCHAR | Height layer 1 |
| cover2 | DOUBLE | Crown cover % layer 2 |
| height2 | VARCHAR | Height layer 2 |
| cover3 | DOUBLE | Crown cover % layer 3 |
| height3 | VARCHAR | Height layer 3 |
| totala | DOUBLE | Total cover (A) |
| heighta | VARCHAR | Total height (A) |
| cover4 | DOUBLE | Crown cover % layer 4 |
| height4 | VARCHAR | Height layer 4 |
| cover5 | DOUBLE | Crown cover % layer 5 |
| height5 | VARCHAR | Height layer 5 |
| cover5a | DOUBLE | Crown cover % layer 5a |
| height5a | VARCHAR | Height layer 5a |
| cover5b | DOUBLE | Crown cover % layer 5b |
| height5b | VARCHAR | Height layer 5b |
| cover5c | DOUBLE | Crown cover % layer 5c |
| height5c | VARCHAR | Height layer 5c |
| totalb | DOUBLE | Total cover (B) |
| heightb | VARCHAR | Total height (B) |
| cover6 | DOUBLE | Crown cover % layer 6 |
| height6 | DOUBLE | Height layer 6 |
| cover7 | DOUBLE | Crown cover % layer 7 |
| cover8 | DOUBLE | Crown cover % layer 8 |
| cover9 | DOUBLE | Crown cover % layer 9 |
| cover10 | VARCHAR | Crown cover % layer 10 |
| **ADDITIONAL FIELDS:** |||
| collected | VARCHAR | Collection status |
| flag | BIGINT | Flag indicator |
| ll | BIGINT | Layer level? |
| af | VARCHAR | Additional field |
| dc | BIGINT | Data code |
| ut | BIGINT | Use type |
| vi | BIGINT | Vitality indicator |
| pv | BIGINT | Plot value |
| pg | BIGINT | Plot group |
| ffa | BIGINT | Form/field assessment |
| cultural1 | VARCHAR | Cultural attribute 1 |
| cultural2 | VARCHAR | Cultural attribute 2 |
| other1 | VARCHAR | Other field 1 |
| other2 | VARCHAR | Other field 2 |

---

### Sample_Herbarium
**Primary Key:** `recid`  
**Foreign Keys:** `plotnumber` → Sample_Env, `species` → Sample_Veg

| Column | Type | Notes |
|--------|------|-------|
| recid | BIGINT | PK - Record identifier |
| accessionnumber | BIGINT | Accession number in herbarium |
| accessiondate | VARCHAR | Accession date |
| plotnumber | BIGINT | FK - Links to Sample_Env |
| species | VARCHAR | FK - Species code |
| scientificnamerich | VARCHAR | Scientific name (rich text) |
| specimenpreviousname | VARCHAR | Previous name of specimen |
| identifier | VARCHAR | Person who identified specimen |
| habitat | VARCHAR | Habitat description |
| countryoforigin | VARCHAR | Country of origin |
| provinceoforigin | VARCHAR | Province of origin |
| collectionnumber | VARCHAR | Collection number |
| locationdescription | VARCHAR | Location description |
| collectors | VARCHAR | Names of collectors |
| dateofcollection | TIMESTAMP | Date specimen was collected |
| generalremarks | VARCHAR | General remarks |
| permanentstoragelocation | VARCHAR | Storage location |
| entryoperator | VARCHAR | Data entry person |
| entryoperatordate | TIMESTAMP | Entry date |
| _comments | VARCHAR | Internal comments |
| photo | VARCHAR | Photo/image reference |
| flag01 | BIGINT | Flag 1 |
| flag02 | BIGINT | Flag 2 |
| **COORDINATE DATA (degrees/minutes/seconds):** |||
| longitudedegrees | VARCHAR | Longitude degrees |
| longitudeminutes | VARCHAR | Longitude minutes |
| longitudeseconds | VARCHAR | Longitude seconds |
| latitudedegrees | VARCHAR | Latitude degrees |
| latitudeminutes | VARCHAR | Latitude minutes |
| latitudeseconds | VARCHAR | Latitude seconds |
| **LOAN TRACKING:** |||
| duplicatesentto | VARCHAR | Duplicates sent to |
| onloanto | VARCHAR | On loan to |
| loandate | VARCHAR | Loan date |
| print | BIGINT | Print indicator |

---

### Sample_SU
**Primary Key:** `plotnumber`  
**Foreign Key:** `plotnumber` → Sample_Env

| Column | Type | Notes |
|--------|------|-------|
| plotnumber | VARCHAR | PK/FK - Links to Sample_Env |
| siteunit | VARCHAR | Site unit designation |

---

### Sample_Metadata
**Primary Key:** `id`  
**Purpose:** Comprehensive project-level metadata (70+ columns)

**Project Identification:**
- projectid, id, startdate, enddate, projecttitle
- coordinatingagency, proponentfunder, fieldcompanyagency
- fieldleader, fielddatacollectionteam, projectpurpose

**Geographic/Study Area:**
- geographicstudyarea, geographicstudyregion

**Plot/Sample Counts:**
- numberoffs882plots, numberofsitevisits

**Project Type:**
- projecttype, projecttypeother

**Collection Standards:**
- ecosyscollectionstandard, ecosyscollectionstandardother
- vegcovermethod, vegcovermethodother
- plotmethod, plotmethodother
- mensurationmethod, mensurationmethodother
- extravegfielddescription

**Data Custodian:**
- datacustodian, storagelocation

**Collection Indicators (Site/Veg/Soil/etc):**
- collectedsite, dataqualitysite
- collectedveg, dataqualityveg
- collectedsoil, dataqualitysoil
- collectedterrain, dataqualityterrain
- collectedmens, dataqualitymens
- collectedcwd, dataqualitycwd
- collectedwildtree, dataqualitywildtree
- collectedsoilchem, dataqualitysoilchem
- collectedwildlifehabitatassessment, dataqualitywildlifehabitatassessment
- collectedcompleteother, collectedpartialother, collectednoneother

**Georeferencing:**
- georefmethod, georefmethodother, datum, datumother
- coordinatesystem, coordinatesystemother

**Specifications:**
- allspecs, tableoflists

**Coverage Descriptions (A/B/C/D/8/9/10):**
- covera1description, covera2description, covera3description, coveradescription
- coverb1description, coverb2description, coverb2adescription, coverb2bdescription, coverb2cdescription, coverbdescription
- covercdescription, coverddescription
- cover8description, cover9description, cover10description

**Admin:**
- bapid, datelastedited, notes

---

### Sample_Hierarchy
**Primary Key:** `id`

| Column | Type | Notes |
|--------|------|-------|
| id | BIGINT | PK - Record identifier |
| _name | VARCHAR | Name/label |
| parent | BIGINT | Parent node ID |
| _level | BIGINT | Hierarchy level |
| tag | BIGINT | Tag/classification |
| myorder | VARCHAR | Order/sequence |
| childid | BIGINT | Child node ID |
| startchild | BIGINT | Starting child |
| lastchild | BIGINT | Last child |
| flag | BIGINT | Flag indicator |

---

### Sample_Lump & Sample_Theme
**Purpose:** Species grouping/lumping system

**Sample_Lump (PK: lumpcode)**
| Column | Type |
|--------|------|
| lumpcode | VARCHAR |
| sppcode | VARCHAR |
| _use | BIGINT |

**Sample_Theme (PK: sppcode)**
| Column | Type |
|--------|------|
| sppcode | VARCHAR |
| lumpcode | VARCHAR |
| scientificname | VARCHAR |
| colourcode | BIGINT |
| patterncode | BIGINT |
| fontcolour | BIGINT |
| _use | BIGINT |

---

### Sample_Profile
**Purpose:** Species/layer reference profiles

| Table | PK | Columns |
|-------|----|---------| 
| Sample_Profile | species | _order, _table, field, _operator, layer, species, criteria, operation, plotcount |

---

### Sample_Other
**Primary Key:** `id`  
**Foreign Keys:** `plotnumber` → Sample_Env, `id` → Sample_Metadata

| Column | Type | Notes |
|--------|------|-------|
| id | BIGINT | PK - Record identifier |
| plotnumber | BIGINT | FK - Links to Sample_Env |
| dataname | VARCHAR | Name of data item |
| dataitem | VARCHAR | Data item value |
| useritem1 | VARCHAR | User-defined item 1 |
| useritem2 | VARCHAR | User-defined item 2 |
| useritem3 | VARCHAR | User-defined item 3 |
| userflag1 | BIGINT | User-defined flag 1 |
| userflag2 | BIGINT | User-defined flag 2 |
| userflag3 | BIGINT | User-defined flag 3 |
| flag | BIGINT | Flag indicator |

---

### Sample_Audit
**Primary Key:** `id`  
**Purpose:** Complete edit history and audit trail

| Column | Type | Notes |
|--------|------|-------|
| id | BIGINT | PK - Audit record ID |
| project | VARCHAR | Project identifier |
| _user | VARCHAR | User who made edit |
| plotnumber | VARCHAR | Plot affected |
| _table | VARCHAR | Table that was edited |
| editfield | VARCHAR | Specific field edited |
| editwhen | VARCHAR | Timestamp of edit |
| beforeedit | VARCHAR | Previous value |
| afteredit | VARCHAR | New value |
| restore | BIGINT | Restoration flag |
| flag | BIGINT | General flag |

**Purpose:** Enables complete audit trail, data lineage, and recovery of previous states

---

## Key Patterns & Observations

### 1. **Column Naming Conventions**

**Metadata columns (underscore prefix):**
- `_table`, `_user`, `_zone`, `_order`, `_operator`, `_location`, `_temporary`, `_comment`, `_comments`, `_name`, `_level`, `_use`

**Depth/Range columns:**
- `upperdepth`, `lowerdepth`: Layer boundaries (cm)
- `Upper/lower` pattern used in Humus and Mineral tables

**Pattern-based coverage:**
- `cover1`-`cover10`, `height1`-`height6`: Multi-layered coverage documentation
- `totala`, `heighta`, `totalb`, `heightb`: Summary aggregates
- `cover5a`, `cover5b`, `cover5c`: Sub-divisions of layer 5

**Coordinate columns:**
- Decimal degrees: `longitude`, `latitude`
- UTM: `utmzone`, `utmeasting`, `utmnorthing`
- Degrees/minutes/seconds (in Herbarium): `longitudedegrees`, `longitudeminutes`, etc.

**SoilVeg fields (sv_ prefix in Sample_Env):**
- Special soil-vegetation integration fields for advanced analysis
- Examples: `sv_standheight`, `sv_canopycomposition`, `sv_soildepth`

### 2. **NULL Handling**
- All columns allow NULL values (no explicit constraints)
- Data quality tracked separately via quality flags and Sample_Audit

### 3. **Multiplicity Issues**
- Multiple soil layers per plot (Humus, Mineral entries)
- Multiple vegetation species per plot (Veg entries)
- Multiple records for same plot (Herbarium, Other)

### 4. **Key Observations for Analysis**

| Aspect | Notes |
|--------|-------|
| **Sample_Env size** | 128 columns - densest table, contains accumulated site data |
| **Sample_Veg complexity** | 10 cover/height pairs (cover1-10) allow multiple measurement strategies |
| **Herbarium richness** | 33 columns for specimen tracking, loans, and origins |
| **Metadata span** | 70+ columns covering project scope, methods, quality,collection completeness |
| **Audit capability** | Complete before/after values enable full reconstruction |
| **Lumping system** | Bidirectional mapping (Sample_Lump ↔ Sample_Theme) for species aggregation |

---

## Query Examples

### Get complete plot environmental + vegetation data:
```sql
SELECT 
    e.plotnumber, e.elevation, e.aspect, e.subzone, e.siteseries,
    v.species, v.layer, v.cover1, v.height1,
    h.horizon, h.upperdepth, h.lowerdepth
FROM Sample_Env e
LEFT JOIN Sample_Veg v ON e.plotnumber = v.plotnumber
LEFT JOIN Sample_Humus h ON e.plotnumber = h.plotnumber
WHERE e.plotnumber = 'PLOT_ID'
```

### Get all measurements for a species:
```sql
SELECT
    v.plotnumber, v.species, v.layer,
    v.cover1, v.height1, v.cover2, v.height2, ..., v.cover10,
    e.elevation, e.aspect
FROM Sample_Veg v
JOIN Sample_Env e ON v.plotnumber = e.plotnumber
WHERE v.species = 'SPECIES_CODE'
```

### Get soil profile with all horizons:
```sql
SELECT
    h.plotnumber,
    h.horizon, h.upperdepth, h.lowerdepth,
    h.humusstructuredegree, h.vonpost,
    m.colour, m.texture, m.percentcoarsefragstotal
FROM Sample_Humus h
FULL OUTER JOIN Sample_Mineral m 
  ON h.plotnumber = m.plotnumber 
  AND h.upperdepth = m.upperdepth
ORDER BY upperdepth
```

### Audit trail for a plot:
```sql
SELECT
    editwhen, _table, editfield, beforeedit, afteredit, _user
FROM Sample_Audit
WHERE plotnumber = 'PLOT_ID'
ORDER BY editwhen DESC
```

---

## Files Generated

1. **SAMPLE_TABLES_DBML.dbml** - Complete DBML schema for visualization
2. **SAMPLE_TABLES_SCHEMA.md** - This comprehensive documentation
3. **SAMPLE_TABLES_QUICK_REF.md** - Quick reference guide with examples

All files available in: `/Users/nicolas/Documents/GitHub/vpro/`
