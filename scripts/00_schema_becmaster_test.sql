-- ============================================================================
-- PostgreSQL Schema for VPro BEC Data Management
-- Complete schema with all Sample_ table definitions from DuckDB
-- ============================================================================

-- Drop existing schemas (for clean rebuild)
DROP SCHEMA IF EXISTS audit CASCADE;
DROP SCHEMA IF EXISTS core CASCADE;
DROP SCHEMA IF EXISTS lists CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS admin CASCADE;
DROP SCHEMA IF EXISTS public_export CASCADE;

-- ============================================================================
CREATE SCHEMA audit;
CREATE SCHEMA core;
CREATE SCHEMA lists;
CREATE SCHEMA staging;
CREATE SCHEMA admin;
CREATE SCHEMA public_export;

-- ============================================================================
-- TRIGGER FUNCTIONS (before table definitions)
-- ============================================================================

CREATE OR REPLACE FUNCTION core.row_version_trigger()
RETURNS TRIGGER AS $$
BEGIN
    NEW."rowVersion" := COALESCE(OLD."rowVersion", 0) + 1;
    NEW."lastModifiedUTC" := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION audit.if_modified_func()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit.logged_actions ("schemaName", "tableName", "userName", "actionTstampSTM", 
        action, "statementOnly")
    VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, CURRENT_USER, NOW(), 
            CASE TG_OP WHEN 'INSERT' THEN 'I' WHEN 'UPDATE' THEN 'U' WHEN 'DELETE' THEN 'D' END, 
            FALSE);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- AUDIT SCHEMA - Change tracking
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit.logged_actions (
    id SERIAL PRIMARY KEY,
    "schemaName" TEXT NOT NULL,
    "tableName" TEXT NOT NULL,
    "userName" TEXT DEFAULT CURRENT_USER,
    "actionTstampTX" TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    "actionTstampSTM" TIMESTAMPTZ NOT NULL,
    "transactionID" BIGINT,
    "applicationName" TEXT,
    "clientAddr" INET,
    "clientPort" INTEGER,
    "clientQuery" TEXT,
    action TEXT NOT NULL CHECK (action IN ('I','D','U')),
    "changedFields" JSONB,
    "statementOnly" BOOLEAN NOT NULL
);

CREATE INDEX IF NOT EXISTS logged_actions_schema_table_idx ON audit.logged_actions("schemaName", "tableName");
CREATE INDEX IF NOT EXISTS logged_actions_action_tstamp_tx_idx ON audit.logged_actions("actionTstampTX");
CREATE INDEX IF NOT EXISTS logged_actions_action_idx ON audit.logged_actions(action);

-- ============================================================================
-- LISTS SCHEMA - Reference tables for codes and lookups
-- ============================================================================

CREATE TABLE IF NOT EXISTS lists.spplist (
    id SERIAL PRIMARY KEY,
    "sppCode" TEXT UNIQUE NOT NULL,
    "sppName" TEXT NOT NULL,
    "sppScientific" TEXT,
    "isActive" BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS lists.layercode (
    id SERIAL PRIMARY KEY,
    "layerCode" TEXT UNIQUE NOT NULL,
    "layerName" TEXT NOT NULL,
    "sortOrder" INTEGER
);

CREATE TABLE IF NOT EXISTS lists.usyszonelist (
    id SERIAL PRIMARY KEY,
    "zoneCode" TEXT UNIQUE NOT NULL,
    "zoneName" TEXT NOT NULL,
    province TEXT
);

CREATE TABLE IF NOT EXISTS lists.usyssubzonelist (
    id SERIAL PRIMARY KEY,
    "zoneCode" TEXT NOT NULL,
    "subzoneCode" TEXT NOT NULL,
    "subzoneName" TEXT NOT NULL,
    UNIQUE("zoneCode", "subzoneCode")
);

CREATE TABLE IF NOT EXISTS lists.usystableoflists (
    id SERIAL PRIMARY KEY,
    "listID" TEXT NOT NULL,
    "itemCode" TEXT NOT NULL,
    "itemName" TEXT NOT NULL,
    "itemSort" INTEGER,
    UNIQUE("listID", "itemCode")
);

CREATE TABLE IF NOT EXISTS lists.usyssppattributes (
    id SERIAL PRIMARY KEY,
    "sppCode" TEXT UNIQUE NOT NULL,
    "treeShrubHerb" TEXT,
    "nativeIntroduced" TEXT,
    FOREIGN KEY ("sppCode") REFERENCES lists.spplist("sppCode")
);

-- ============================================================================
-- CORE SCHEMA - Main data tables (from Sample_* tables in DuckDB)
-- ============================================================================

-- core.admin: Master record for plot administration and metadata
CREATE TABLE IF NOT EXISTS core.admin (
    plot TEXT PRIMARY KEY,
    startdate BIGINT,
    plottype TEXT,
    plotsize NUMERIC,
    provincestateterritory TEXT,
    siteplotquality TEXT,
    vegplotquality TEXT,
    soilplotquality TEXT,
    updatedfromcards BIGINT,
    enteredby TEXT,
    usersiteunit TEXT,
    becsiteunit TEXT,
    siteunitshortname TEXT,
    siteunitlongname TEXT,
    officenotes TEXT,
    humusthickness NUMERIC,
    gis_bgc TEXT,
    gis_bgc_ver TEXT,
    bec_use NUMERIC,
    stratacovertotal TEXT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_admin_modified ON core.admin("lastModifiedUTC");

CREATE TRIGGER admin_row_version
    BEFORE INSERT OR UPDATE ON core.admin
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER admin_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.admin
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.metadata: Comprehensive project metadata
CREATE TABLE IF NOT EXISTS core.metadata (
    id BIGINT PRIMARY KEY,
    projectid TEXT,
    startdate BIGINT,
    enddate TEXT,
    projecttitle TEXT,
    coordinatingagency TEXT,
    proponentfunder TEXT,
    fieldcompanyagency TEXT,
    fieldleader TEXT,
    fielddatacollectionteam TEXT,
    projectpurpose TEXT,
    geographicstudyarea TEXT,
    geographicstudyregion TEXT,
    numberoffs882plots TEXT,
    numberofsitevisits TEXT,
    projecttype TEXT,
    projecttypeother TEXT,
    ecosyscollectionstandard TEXT,
    ecosyscollectionstandardother TEXT,
    vegcovermethod TEXT,
    vegcovermethodother TEXT,
    plotmethod TEXT,
    plotmethodother TEXT,
    mensurationmethod TEXT,
    mensurationmethodother TEXT,
    extravegfielddescription TEXT,
    datacustodian TEXT,
    storagelocation TEXT,
    collectedsite BIGINT,
    dataqualitysite TEXT,
    collectedveg BIGINT,
    dataqualityveg TEXT,
    collectedsoil BIGINT,
    dataqualitysoil TEXT,
    collectedterrain TEXT,
    dataqualityterrain TEXT,
    collectedmens TEXT,
    dataqualitymens TEXT,
    collectedcwd TEXT,
    dataqualitycwd TEXT,
    collectedwildtree TEXT,
    dataqualitywildtree TEXT,
    collectedsoilchem TEXT,
    dataqualitysoilchem TEXT,
    collectedwildlifehabitatassessment TEXT,
    dataqualitywildlifehabitatassessment TEXT,
    collectedcompleteother TEXT,
    collectedpartialother TEXT,
    collectednoneother TEXT,
    georefmethod TEXT,
    georefmethodother TEXT,
    datum TEXT,
    datumother TEXT,
    coordinatesystem TEXT,
    coordinatesystemother TEXT,
    allspecs TEXT,
    tableoflists TEXT,
    covera1description TEXT,
    covera2description TEXT,
    covera3description TEXT,
    coveradescription TEXT,
    coverb1description TEXT,
    coverb2description TEXT,
    coverb2adescription TEXT,
    coverb2bdescription TEXT,
    coverb2cdescription TEXT,
    coverbdescription TEXT,
    covercdescription TEXT,
    coverddescription TEXT,
    cover8description TEXT,
    cover9description TEXT,
    cover10description TEXT,
    bapid TEXT,
    datelastedited TEXT,
    notes TEXT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_metadata_modified ON core.metadata("lastModifiedUTC");

CREATE TRIGGER metadata_row_version
    BEFORE INSERT OR UPDATE ON core.metadata
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER metadata_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.metadata
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.hierarchy: Hierarchical classification/organization data
CREATE TABLE IF NOT EXISTS core.hierarchy (
    id BIGINT PRIMARY KEY,
    _name TEXT,
    parent BIGINT,
    _level BIGINT,
    tag BIGINT,
    myorder TEXT,
    childid BIGINT,
    startchild BIGINT,
    lastchild BIGINT,
    flag BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_hierarchy_parent ON core.hierarchy(parent);
CREATE INDEX IF NOT EXISTS idx_core_hierarchy_modified ON core.hierarchy("lastModifiedUTC");

CREATE TRIGGER hierarchy_row_version
    BEFORE INSERT OR UPDATE ON core.hierarchy
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER hierarchy_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.hierarchy
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.env: Central environmental site characterization table
CREATE TABLE IF NOT EXISTS core.env (
    plotnumber TEXT PRIMARY KEY,
    fieldnumber TEXT,
    projectid TEXT,
    fsregiondistrict TEXT,
    date TEXT,
    sitesurveyor TEXT,
    plotrepresenting TEXT,
    _location TEXT,
    ecosection TEXT,
    ntsmapsheet TEXT,
    longitude NUMERIC,
    latitude NUMERIC,
    utmzone BIGINT,
    utmeasting NUMERIC,
    utmnorthing NUMERIC,
    locationaccuracy BIGINT,
    airphotonum TEXT,
    xcoord NUMERIC,
    ycoord NUMERIC,
    _zone TEXT,
    subzone TEXT,
    siteseries TEXT,
    sitemodifier1 TEXT,
    sitemodifier2 BOOLEAN,
    transdistrib BIGINT,
    realmclass TEXT,
    mapunit TEXT,
    snowcoverregime TEXT,
    moistureregime TEXT,
    nutrientregime TEXT,
    successionalstatus TEXT,
    structuralstage TEXT,
    structuralstagemod TEXT,
    standage BIGINT,
    elevation BIGINT,
    slopegradient NUMERIC,
    aspect BIGINT,
    mesoslopeposition TEXT,
    surfaceshape TEXT,
    surfacetopographytype TEXT,
    surfacetopographysize TEXT,
    watersource TEXT,
    photo TEXT,
    exposure1 TEXT,
    exposure2 TEXT,
    sitedisturbance1 TEXT,
    sitedisturbance2 TEXT,
    sitedisturbance3 TEXT,
    substratedecwood NUMERIC,
    substratebedrock NUMERIC,
    substraterocks NUMERIC,
    substratemineralsoil NUMERIC,
    substrateorganicmatter NUMERIC,
    substratewater NUMERIC,
    sitenotes TEXT,
    soilsurveyor TEXT,
    bedrockgeology1 TEXT,
    bedrockgeology2 TEXT,
    bedrockgeology3 TEXT,
    coarsefraglith1 TEXT,
    coarsefraglith2 TEXT,
    coarsefraglith3 TEXT,
    terraintexturesurf TEXT,
    surficialmaterialsurf TEXT,
    surfaceexpsurf TEXT,
    geomorprosurf TEXT,
    terraintexturesubsurf TEXT,
    surficialmaterialsubsurf TEXT,
    surfaceexpsubsurf TEXT,
    geomorprosubsurf TEXT,
    floodingregimefreq TEXT,
    moistureregimesub TEXT,
    floodingregimedur TEXT,
    soildrainage TEXT,
    seepagedepth BIGINT,
    rootrestrictingtype TEXT,
    rootrestrictingdepth BIGINT,
    rootzoneparticlesize TEXT,
    rootingdepth BIGINT,
    soilclasssubgroup TEXT,
    soilclassgroup TEXT,
    humusform TEXT,
    humusformphase TEXT,
    phmethodcodemineral TEXT,
    phmethodcodeorganic TEXT,
    soilnotes TEXT,
    vegsurveyor TEXT,
    stratacovertree NUMERIC,
    stratacovershrub NUMERIC,
    stratacoverherb NUMERIC,
    stratacovermoss NUMERIC,
    vegnotes TEXT,
    hydrogeosystem TEXT,
    hydrogeosubsystem TEXT,
    specieslistcomplete BIGINT,
    _temporary TEXT,
    flag BIGINT,
    sv_polygonnumber TEXT,
    sv_floodplain BIGINT,
    sv_standageestmeas BIGINT,
    sv_standheight NUMERIC,
    sv_standheightestmeas BIGINT,
    sv_canopycomposition TEXT,
    sv_soildepth NUMERIC,
    sv_rootzonetexture TEXT,
    sv_percentcoarsefrags NUMERIC,
    sv_gleyingmottlingcm NUMERIC,
    sv_watertablecm NUMERIC,
    sv_fullcruisecard TEXT,
    sv_ahorizontype TEXT,
    sv_ahorizondepth NUMERIC,
    activelayerdepth NUMERIC,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_env_projectid ON core.env(projectid);
CREATE INDEX IF NOT EXISTS idx_core_env_modified ON core.env("lastModifiedUTC");

CREATE TRIGGER env_row_version
    BEFORE INSERT OR UPDATE ON core.env
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER env_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.env
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.humus: Humus/organic layer characterization data
CREATE TABLE IF NOT EXISTS core.humus (
    id BIGINT PRIMARY KEY,
    plotnumber TEXT,
    horizon TEXT,
    upperdepth NUMERIC,
    lowerdepth NUMERIC,
    humusstructuredegree TEXT,
    humusstructurekind TEXT,
    mycelabundance TEXT,
    fecalabundance TEXT,
    rootsabundance TEXT,
    rootssize TEXT,
    vonpost BIGINT,
    humusformph NUMERIC,
    consistence TEXT,
    character TEXT,
    fauna TEXT,
    _comment TEXT,
    flag BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_humus_plotnumber ON core.humus(plotnumber);
CREATE INDEX IF NOT EXISTS idx_core_humus_modified ON core.humus("lastModifiedUTC");

CREATE TRIGGER humus_row_version
    BEFORE INSERT OR UPDATE ON core.humus
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER humus_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.humus
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.mineral: Mineral soil layer characterization data
CREATE TABLE IF NOT EXISTS core.mineral (
    id BIGINT PRIMARY KEY,
    plotnumber TEXT,
    horizon TEXT,
    upperdepth NUMERIC,
    lowerdepth NUMERIC,
    pitdepthlimit TEXT,
    colour TEXT,
    asp BIGINT,
    texture TEXT,
    percentcoarsefragsgravel BIGINT,
    percentcoarsefragscobbles BIGINT,
    percentcoarsefragsstones BIGINT,
    percentcoarsefragstotal BIGINT,
    percentcoarsefragsshape TEXT,
    rootsabundance TEXT,
    rootssize TEXT,
    mineralstructureclass TEXT,
    mineralstructurekind TEXT,
    mineralformph TEXT,
    mottlesabundance TEXT,
    mottlessize TEXT,
    mottlescontrast TEXT,
    clayfilmsfreq TEXT,
    clayfilmthickness TEXT,
    effervescence TEXT,
    porosity TEXT,
    _comments TEXT,
    flag BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_mineral_plotnumber ON core.mineral(plotnumber);
CREATE INDEX IF NOT EXISTS idx_core_mineral_modified ON core.mineral("lastModifiedUTC");

CREATE TRIGGER mineral_row_version
    BEFORE INSERT OR UPDATE ON core.mineral
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER mineral_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.mineral
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.other: Miscellaneous plot data
CREATE TABLE IF NOT EXISTS core.other (
    id BIGINT PRIMARY KEY,
    plotnumber TEXT,
    dataname TEXT,
    dataitem TEXT,
    useritem1 TEXT,
    useritem2 TEXT,
    useritem3 TEXT,
    userflag1 BIGINT,
    userflag2 BIGINT,
    userflag3 BIGINT,
    flag BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_other_plotnumber ON core.other(plotnumber);
CREATE INDEX IF NOT EXISTS idx_core_other_modified ON core.other("lastModifiedUTC");

CREATE TRIGGER other_row_version
    BEFORE INSERT OR UPDATE ON core.other
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER other_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.other
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.veg: Vegetation species and layer composition with cover measurements
CREATE TABLE IF NOT EXISTS core.veg (
    id BIGINT PRIMARY KEY,
    plotnumber TEXT,
    species TEXT,
    layer TEXT,
    cover1 NUMERIC,
    height1 TEXT,
    cover2 NUMERIC,
    height2 TEXT,
    cover3 NUMERIC,
    height3 TEXT,
    totala NUMERIC,
    heighta TEXT,
    cover4 NUMERIC,
    height4 TEXT,
    cover5 NUMERIC,
    height5 TEXT,
    cover5a NUMERIC,
    height5a TEXT,
    cover5b NUMERIC,
    height5b TEXT,
    cover5c NUMERIC,
    height5c TEXT,
    totalb NUMERIC,
    heightb TEXT,
    cover6 NUMERIC,
    height6 NUMERIC,
    cover7 NUMERIC,
    cover8 NUMERIC,
    cover9 NUMERIC,
    cover10 TEXT,
    collected TEXT,
    flag BIGINT,
    ll BIGINT,
    af TEXT,
    dc BIGINT,
    ut BIGINT,
    vi BIGINT,
    pv BIGINT,
    pg BIGINT,
    ffa BIGINT,
    cultural1 TEXT,
    cultural2 TEXT,
    other1 TEXT,
    other2 TEXT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_veg_plotnumber ON core.veg(plotnumber);
CREATE INDEX IF NOT EXISTS idx_core_veg_species ON core.veg(species);
CREATE INDEX IF NOT EXISTS idx_core_veg_modified ON core.veg("lastModifiedUTC");

CREATE TRIGGER veg_row_version
    BEFORE INSERT OR UPDATE ON core.veg
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER veg_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.veg
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.herbarium: Herbarium specimen and photographic records
CREATE TABLE IF NOT EXISTS core.herbarium (
    recid BIGINT PRIMARY KEY,
    accessionnumber BIGINT,
    accessiondate TEXT,
    plotnumber TEXT,
    species TEXT,
    scientificnamerich TEXT,
    specimenpreviousname TEXT,
    identifier TEXT,
    habitat TEXT,
    countryoforigin TEXT,
    provinceoforigin TEXT,
    collectionnumber TEXT,
    locationdescription TEXT,
    collectors TEXT,
    dateofcollection TIMESTAMP,
    generalremarks TEXT,
    permanentstoragelocation TEXT,
    entryoperator TEXT,
    entryoperatordate TIMESTAMP,
    _comments TEXT,
    photo TEXT,
    flag01 BIGINT,
    flag02 BIGINT,
    longitudedegrees TEXT,
    longitudeminutes TEXT,
    longitudeseconds TEXT,
    latitudedegrees TEXT,
    latitudeminutes TEXT,
    latitudeseconds TEXT,
    duplicatesentto TEXT,
    onloanto TEXT,
    loandate TEXT,
    print BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_herbarium_plotnumber ON core.herbarium(plotnumber);
CREATE INDEX IF NOT EXISTS idx_core_herbarium_species ON core.herbarium(species);
CREATE INDEX IF NOT EXISTS idx_core_herbarium_modified ON core.herbarium("lastModifiedUTC");

CREATE TRIGGER herbarium_row_version
    BEFORE INSERT OR UPDATE ON core.herbarium
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER herbarium_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.herbarium
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.su: Site unit assignments for plots
CREATE TABLE IF NOT EXISTS core.su (
    plotnumber TEXT PRIMARY KEY,
    siteunit TEXT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_su_modified ON core.su("lastModifiedUTC");

CREATE TRIGGER su_row_version
    BEFORE INSERT OR UPDATE ON core.su
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER su_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.su
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.profile: Reference profiles for species and layers
CREATE TABLE IF NOT EXISTS core.profile (
    _order BIGINT,
    _table TEXT,
    field TEXT,
    _operator TEXT,
    layer TEXT,
    species TEXT PRIMARY KEY,
    criteria TEXT,
    operation TEXT,
    plotcount BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_profile_modified ON core.profile("lastModifiedUTC");

CREATE TRIGGER profile_row_version
    BEFORE INSERT OR UPDATE ON core.profile
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER profile_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.profile
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.veg_profile: Operational vegetation profile data
CREATE TABLE IF NOT EXISTS core.veg_profile (
    _order BIGINT,
    _table TEXT,
    field TEXT,
    _operator TEXT,
    layer TEXT,
    species TEXT,
    criteria BIGINT,
    operation TEXT,
    plotcount BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_veg_profile_modified ON core.veg_profile("lastModifiedUTC");

CREATE TRIGGER veg_profile_row_version
    BEFORE INSERT OR UPDATE ON core.veg_profile
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER veg_profile_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.veg_profile
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.lump: Species lumping/aggregation codes
CREATE TABLE IF NOT EXISTS core.lump (
    lumpcode TEXT PRIMARY KEY,
    sppcode TEXT,
    _use BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_lump_modified ON core.lump("lastModifiedUTC");

CREATE TRIGGER lump_row_version
    BEFORE INSERT OR UPDATE ON core.lump
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER lump_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.lump
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.theme: Species theme and classification with lumping codes
CREATE TABLE IF NOT EXISTS core.theme (
    sppcode TEXT PRIMARY KEY,
    lumpcode TEXT,
    scientificname TEXT,
    colourcode BIGINT,
    patterncode BIGINT,
    fontcolour BIGINT,
    _use BIGINT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_core_theme_modified ON core.theme("lastModifiedUTC");

CREATE TRIGGER theme_row_version
    BEFORE INSERT OR UPDATE ON core.theme
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER theme_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.theme
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.audit: Audit log of all edits across all tables
CREATE TABLE IF NOT EXISTS core.audit (
    id BIGINT PRIMARY KEY,
    project TEXT,
    _user TEXT,
    plotnumber TEXT,
    _table TEXT,
    editfield TEXT,
    editwhen TEXT,
    beforeedit TEXT,
    afteredit TEXT,
    restore BIGINT,
    flag BIGINT
);

CREATE INDEX IF NOT EXISTS idx_core_audit_plotnumber ON core.audit(plotnumber);
CREATE INDEX IF NOT EXISTS idx_core_audit_table ON core.audit(_table);

-- ============================================================================
-- STAGING SCHEMA - Mirrors of core tables with change tracking
-- ============================================================================

-- staging.admin
CREATE TABLE IF NOT EXISTS staging.admin (
    plot TEXT PRIMARY KEY,
    startdate BIGINT,
    plottype TEXT,
    plotsize NUMERIC,
    provincestateterritory TEXT,
    siteplotquality TEXT,
    vegplotquality TEXT,
    soilplotquality TEXT,
    updatedfromcards BIGINT,
    enteredby TEXT,
    usersiteunit TEXT,
    becsiteunit TEXT,
    siteunitshortname TEXT,
    siteunitlongname TEXT,
    officenotes TEXT,
    humusthickness NUMERIC,
    gis_bgc TEXT,
    gis_bgc_ver TEXT,
    bec_use NUMERIC,
    stratacovertotal TEXT,
    "baseRowVersion" INTEGER,
    "changeType" TEXT CHECK ("changeType" IN ('I','U','D')),
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

-- staging.env
CREATE TABLE IF NOT EXISTS staging.env (
    plotnumber TEXT PRIMARY KEY,
    fieldnumber TEXT,
    projectid TEXT,
    fsregiondistrict TEXT,
    date TEXT,
    sitesurveyor TEXT,
    plotrepresenting TEXT,
    _location TEXT,
    ecosection TEXT,
    ntsmapsheet TEXT,
    longitude NUMERIC,
    latitude NUMERIC,
    utmzone BIGINT,
    utmeasting NUMERIC,
    utmnorthing NUMERIC,
    locationaccuracy BIGINT,
    airphotonum TEXT,
    xcoord NUMERIC,
    ycoord NUMERIC,
    _zone TEXT,
    subzone TEXT,
    siteseries TEXT,
    sitemodifier1 TEXT,
    sitemodifier2 BOOLEAN,
    transdistrib BIGINT,
    realmclass TEXT,
    mapunit TEXT,
    snowcoverregime TEXT,
    moistureregime TEXT,
    nutrientregime TEXT,
    successionalstatus TEXT,
    structuralstage TEXT,
    structuralstagemod TEXT,
    standage BIGINT,
    elevation BIGINT,
    slopegradient NUMERIC,
    aspect BIGINT,
    mesoslopeposition TEXT,
    surfaceshape TEXT,
    surfacetopographytype TEXT,
    surfacetopographysize TEXT,
    watersource TEXT,
    photo TEXT,
    exposure1 TEXT,
    exposure2 TEXT,
    sitedisturbance1 TEXT,
    sitedisturbance2 TEXT,
    sitedisturbance3 TEXT,
    substratedecwood NUMERIC,
    substratebedrock NUMERIC,
    substraterocks NUMERIC,
    substratemineralsoil NUMERIC,
    substrateorganicmatter NUMERIC,
    substratewater NUMERIC,
    sitenotes TEXT,
    soilsurveyor TEXT,
    bedrockgeology1 TEXT,
    bedrockgeology2 TEXT,
    bedrockgeology3 TEXT,
    coarsefraglith1 TEXT,
    coarsefraglith2 TEXT,
    coarsefraglith3 TEXT,
    terraintexturesurf TEXT,
    surficialmaterialsurf TEXT,
    surfaceexpsurf TEXT,
    geomorprosurf TEXT,
    terraintexturesubsurf TEXT,
    surficialmaterialsubsurf TEXT,
    surfaceexpsubsurf TEXT,
    geomorprosubsurf TEXT,
    floodingregimefreq TEXT,
    moistureregimesub TEXT,
    floodingregimedur TEXT,
    soildrainage TEXT,
    seepagedepth BIGINT,
    rootrestrictingtype TEXT,
    rootrestrictingdepth BIGINT,
    rootzoneparticlesize TEXT,
    rootingdepth BIGINT,
    soilclasssubgroup TEXT,
    soilclassgroup TEXT,
    humusform TEXT,
    humusformphase TEXT,
    phmethodcodemineral TEXT,
    phmethodcodeorganic TEXT,
    soilnotes TEXT,
    vegsurveyor TEXT,
    stratacovertree NUMERIC,
    stratacovershrub NUMERIC,
    stratacoverherb NUMERIC,
    stratacovermoss NUMERIC,
    vegnotes TEXT,
    hydrogeosystem TEXT,
    hydrogeosubsystem TEXT,
    specieslistcomplete BIGINT,
    _temporary TEXT,
    flag BIGINT,
    sv_polygonnumber TEXT,
    sv_floodplain BIGINT,
    sv_standageestmeas BIGINT,
    sv_standheight NUMERIC,
    sv_standheightestmeas BIGINT,
    sv_canopycomposition TEXT,
    sv_soildepth NUMERIC,
    sv_rootzonetexture TEXT,
    sv_percentcoarsefrags NUMERIC,
    sv_gleyingmottlingcm NUMERIC,
    sv_watertablecm NUMERIC,
    sv_fullcruisecard TEXT,
    sv_ahorizontype TEXT,
    sv_ahorizondepth NUMERIC,
    activelayerdepth NUMERIC,
    "baseRowVersion" INTEGER,
    "changeType" TEXT CHECK ("changeType" IN ('I','U','D')),
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

-- staging.veg
CREATE TABLE IF NOT EXISTS staging.veg (
    id BIGINT PRIMARY KEY,
    plotnumber TEXT,
    species TEXT,
    layer TEXT,
    cover1 NUMERIC,
    height1 TEXT,
    cover2 NUMERIC,
    height2 TEXT,
    cover3 NUMERIC,
    height3 TEXT,
    totala NUMERIC,
    heighta TEXT,
    cover4 NUMERIC,
    height4 TEXT,
    cover5 NUMERIC,
    height5 TEXT,
    cover5a NUMERIC,
    height5a TEXT,
    cover5b NUMERIC,
    height5b TEXT,
    cover5c NUMERIC,
    height5c TEXT,
    totalb NUMERIC,
    heightb TEXT,
    cover6 NUMERIC,
    height6 NUMERIC,
    cover7 NUMERIC,
    cover8 NUMERIC,
    cover9 NUMERIC,
    cover10 TEXT,
    collected TEXT,
    flag BIGINT,
    ll BIGINT,
    af TEXT,
    dc BIGINT,
    ut BIGINT,
    vi BIGINT,
    pv BIGINT,
    pg BIGINT,
    ffa BIGINT,
    cultural1 TEXT,
    cultural2 TEXT,
    other1 TEXT,
    other2 TEXT,
    "baseRowVersion" INTEGER,
    "changeType" TEXT CHECK ("changeType" IN ('I','U','D')),
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

-- staging.su
CREATE TABLE IF NOT EXISTS staging.su (
    plotnumber TEXT PRIMARY KEY,
    siteunit TEXT,
    "baseRowVersion" INTEGER,
    "changeType" TEXT CHECK ("changeType" IN ('I','U','D')),
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT
);

-- ============================================================================
-- ADMIN SCHEMA - User & Role Management
-- ============================================================================

CREATE TABLE IF NOT EXISTS admin.users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    app_role TEXT NOT NULL DEFAULT 'guest' CHECK (app_role IN ('guest', 'admin')),
    password_hash TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    last_login_utc TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS admin.change_log (
    id SERIAL PRIMARY KEY,
    timestamp_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    username TEXT NOT NULL,
    table_name TEXT NOT NULL,
    operation TEXT CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    record_id INTEGER,
    old_values JSONB,
    new_values JSONB
);

CREATE INDEX IF NOT EXISTS idx_change_log_timestamp ON admin.change_log(timestamp_utc);
CREATE INDEX IF NOT EXISTS idx_change_log_user ON admin.change_log(username);

CREATE TABLE IF NOT EXISTS admin.merge_requests (
    id SERIAL PRIMARY KEY,
    project_id TEXT NOT NULL,
    submitter_user_id INTEGER REFERENCES admin.users(id),
    submitter_name TEXT NOT NULL,
    submitted_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    status TEXT NOT NULL DEFAULT 'pending_review'
        CHECK (status IN ('pending_review', 'approved', 'rejected', 'merged')),
    reviewer_user_id INTEGER REFERENCES admin.users(id),
    reviewer TEXT,
    review_notes TEXT,
    reviewed_utc TIMESTAMPTZ,
    env_record_count INTEGER NOT NULL DEFAULT 0,
    su_record_count  INTEGER NOT NULL DEFAULT 0,
    veg_record_count INTEGER NOT NULL DEFAULT 0,
    compliance_passed BOOLEAN,
    compliance_report TEXT
);

CREATE INDEX IF NOT EXISTS idx_merge_requests_status ON admin.merge_requests(status);
CREATE INDEX IF NOT EXISTS idx_merge_requests_submitted ON admin.merge_requests(submitted_utc);

CREATE TABLE IF NOT EXISTS admin.merge_conflicts (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    table_name TEXT NOT NULL,
    "PlotNumber" TEXT,
    "ProjectID" TEXT,
    "SpeciesCode" TEXT NOT NULL DEFAULT '',
    "LayerCode"   TEXT NOT NULL DEFAULT '',
    details JSONB,
    resolution TEXT CHECK (resolution IN ('keep_staged', 'keep_core', 'dismiss')),
    resolved_by TEXT,
    resolved_utc TIMESTAMPTZ,
    created_utc TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(merge_request_id, table_name, "PlotNumber", "ProjectID", "SpeciesCode", "LayerCode")
);

CREATE INDEX IF NOT EXISTS idx_merge_conflicts_request ON admin.merge_conflicts(merge_request_id);

CREATE TABLE IF NOT EXISTS admin.merge_history (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id),
    merged_utc TIMESTAMPTZ DEFAULT now(),
    approved_by_user_id INTEGER NOT NULL REFERENCES admin.users(id),
    record_count INTEGER,
    merge_summary JSONB
);

-- ============================================================================
-- PUBLIC_EXPORT SCHEMA - RDS Snapshots & Download Log
-- ============================================================================

CREATE TABLE IF NOT EXISTS public_export.rds_snapshots (
    id SERIAL PRIMARY KEY,
    version TEXT NOT NULL UNIQUE,
    "snapshotDate" DATE DEFAULT CURRENT_DATE,
    "createdUTC" TIMESTAMPTZ DEFAULT now(),
    "createdBy" TEXT NOT NULL,
    "rdsFilenameVeg" TEXT,
    "rdsFilenameEnv" TEXT,
    "vegRowCount" INTEGER,
    "envRowCount" INTEGER,
    "md5HashVeg" TEXT,
    "md5HashEnv" TEXT,
    "snapshotMetadata" JSONB
);

CREATE TABLE IF NOT EXISTS public_export.download_log (
    id SERIAL PRIMARY KEY,
    "userID" INTEGER REFERENCES admin.users(id),
    username TEXT DEFAULT 'anonymous',
    "timestampUTC" TIMESTAMPTZ DEFAULT now(),
    "datasetName" TEXT NOT NULL,
    format TEXT NOT NULL CHECK (format IN ('rds', 'csv', 'excel')),
    "filtersApplied" JSONB,
    "rowCount" INTEGER,
    "ipAddress" INET,
    "downloadStatus" TEXT DEFAULT 'success' CHECK ("downloadStatus" IN ('success', 'failed')),
    "errorMessage" TEXT
);

CREATE INDEX IF NOT EXISTS idx_download_log_timestamp ON public_export.download_log("timestampUTC");
CREATE INDEX IF NOT EXISTS idx_download_log_user ON public_export.download_log(username);

-- ============================================================================
-- SEED DATA
-- ============================================================================

INSERT INTO lists.spplist ("sppCode", "sppName", "sppScientific", "isActive") VALUES
    ('TSUGHET', 'western hemlock', 'Tsuga heterophylla', TRUE),
    ('PSEUMEN', 'Douglas-fir', 'Pseudotsuga menziesii', TRUE),
    ('ABIALAM', 'subalpine fir', 'Abies lasiocarpa', TRUE),
    ('PINUCON', 'lodgepole pine', 'Pinus contorta', TRUE),
    ('THUJOCC', 'western redcedar', 'Thuja plicata', TRUE),
    ('VACCOVER', 'oval-leaved blueberry', 'Vaccinium ovalifolium', TRUE),
    ('RUBUSPE', 'salmonberry', 'Rubus spectabilis', TRUE),
    ('RHYTLOR', 'lanky moss', 'Rhytidiadelphus loreus', TRUE),
    ('HYLOCOL', 'step moss', 'Hylocomium splendens', TRUE),
    ('PLEUSCH', 'Schreber''s feather moss', 'Pleurozium schreberi', TRUE)
ON CONFLICT ("sppCode") DO NOTHING;

INSERT INTO lists.layercode ("layerCode", "layerName", "sortOrder") VALUES
    ('T1', 'Tree canopy layer 1', 1),
    ('T2', 'Tree canopy layer 2', 2),
    ('S', 'Shrub layer', 3),
    ('H', 'Herb layer', 4),
    ('M', 'Moss layer', 5)
ON CONFLICT ("layerCode") DO NOTHING;

INSERT INTO lists.usyszonelist ("zoneCode", "zoneName", province) VALUES
    ('CDF', 'Coastal Douglas-fir', 'BC'),
    ('CWH', 'Coastal Western Hemlock', 'BC'),
    ('MH', 'Mountain Hemlock', 'BC'),
    ('ESSF', 'Engelmann Spruce - Subalpine Fir', 'BC'),
    ('ICH', 'Interior Cedar - Hemlock', 'BC'),
    ('IDF', 'Interior Douglas-fir', 'BC'),
    ('MS', 'Montane Spruce', 'BC')
ON CONFLICT ("zoneCode") DO NOTHING;

INSERT INTO lists.usyssubzonelist ("zoneCode", "subzoneCode", "subzoneName") VALUES
    ('CWH', 'dm', 'dry maritime'),
    ('CWH', 'vm', 'very dry maritime'),
    ('CWH', 'xm', 'very wet maritime'),
    ('ICH', 'mk', 'moist cool'),
    ('IDF', 'dk', 'dry cool'),
    ('ESSF', 'mk', 'moist cool'),
    ('MH', 'mm', 'moist maritime')
ON CONFLICT ("zoneCode", "subzoneCode") DO NOTHING;
