-- ============================================================================
-- PostgreSQL Schema for VPro BEC Data Management
-- Full rewrite with audit triggers, row versioning, and staging workflow
-- ============================================================================

-- Drop existing schemas (for clean rebuild)
DROP SCHEMA IF EXISTS audit CASCADE;
DROP SCHEMA IF EXISTS core CASCADE;
DROP SCHEMA IF EXISTS lists CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS admin CASCADE;
DROP SCHEMA IF EXISTS public_export CASCADE;

-- ============================================================================
-- CREATE ALL SCHEMAS
-- ============================================================================

CREATE SCHEMA audit;
CREATE SCHEMA core;
CREATE SCHEMA lists;
CREATE SCHEMA staging;
CREATE SCHEMA admin;
CREATE SCHEMA public_export;

-- ============================================================================
-- AUDIT SCHEMA - Change tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit.logged_actions (
    id SERIAL PRIMARY KEY,
    schema_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    user_name TEXT DEFAULT CURRENT_USER,
    action_tstamp_tx TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    action_tstamp_stm TIMESTAMPTZ NOT NULL,
    action_tstamp_clk TIMESTAMPTZ NOT NULL DEFAULT CLOCK_TIMESTAMP(),
    transaction_id BIGINT,
    application_name TEXT,
    client_addr INET,
    client_port INTEGER,
    client_query TEXT,
    action TEXT NOT NULL CHECK (action IN ('I','D','U')),
    row_data JSONB,
    changed_fields JSONB,
    statement_only BOOLEAN NOT NULL
);

CREATE INDEX IF NOT EXISTS logged_actions_schema_table_idx ON audit.logged_actions(schema_name, table_name);
CREATE INDEX IF NOT EXISTS logged_actions_action_tstamp_tx_idx ON audit.logged_actions(action_tstamp_tx);
CREATE INDEX IF NOT EXISTS logged_actions_action_idx ON audit.logged_actions(action);

-- ============================================================================
-- TRIGGER FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION core.row_version_trigger()
RETURNS TRIGGER AS $$
BEGIN
    NEW.row_version := COALESCE(OLD.row_version, 0) + 1;
    NEW.last_modified_utc := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION audit.if_modified_func()
RETURNS TRIGGER AS $$
BEGIN
    -- Simple audit log: just record the action without detailed state tracking
    INSERT INTO audit.logged_actions (
        schema_name, table_name, user_name, action_tstamp_stm, 
        action_tstamp_clk, action, statement_only
    ) VALUES (
        TG_TABLE_SCHEMA, TG_TABLE_NAME, CURRENT_USER, CURRENT_TIMESTAMP,
        CLOCK_TIMESTAMP(), SUBSTRING(TG_OP FOR 1), false
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- LISTS SCHEMA - Reference tables for codes and lookups
-- ============================================================================

CREATE TABLE IF NOT EXISTS lists.spplist (
    id SERIAL PRIMARY KEY,
    spp_code TEXT UNIQUE NOT NULL,
    spp_name TEXT NOT NULL,
    spp_scientific TEXT,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS lists.layercode (
    id SERIAL PRIMARY KEY,
    layer_code TEXT UNIQUE NOT NULL,
    layer_name TEXT NOT NULL,
    sort_order INTEGER
);

CREATE TABLE IF NOT EXISTS lists.usyszonelist (
    id SERIAL PRIMARY KEY,
    zone_code TEXT UNIQUE NOT NULL,
    zone_name TEXT NOT NULL,
    province TEXT
);

CREATE TABLE IF NOT EXISTS lists.usyssubzonelist (
    id SERIAL PRIMARY KEY,
    zone_code TEXT NOT NULL,
    subzone_code TEXT NOT NULL,
    subzone_name TEXT NOT NULL,
    UNIQUE(zone_code, subzone_code)
);

CREATE TABLE IF NOT EXISTS lists.usystableoflists (
    id SERIAL PRIMARY KEY,
    list_id TEXT NOT NULL,
    item_code TEXT NOT NULL,
    item_name TEXT NOT NULL,
    item_sort INTEGER,
    UNIQUE(list_id, item_code)
);

CREATE TABLE IF NOT EXISTS lists.usyssppattributes (
    id SERIAL PRIMARY KEY,
    spp_code TEXT UNIQUE NOT NULL,
    tree_shrub_herb TEXT,
    native_introduced TEXT,
    FOREIGN KEY (spp_code) REFERENCES lists.spplist(spp_code)
);

-- ============================================================================
-- CORE SCHEMA - Main data tables
-- ============================================================================

CREATE TABLE IF NOT EXISTS core.metadata (
    id SERIAL PRIMARY KEY,
    project_id INTEGER UNIQUE NOT NULL,
    project_name TEXT NOT NULL,
    description TEXT,
    organization TEXT,
    contact_email TEXT,
    created_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    modified_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_metadata_modified ON core.metadata(last_modified_utc);

CREATE TRIGGER metadata_row_version
    BEFORE INSERT OR UPDATE ON core.metadata
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER metadata_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.metadata
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();


-- core.env: environmental/site data
CREATE TABLE IF NOT EXISTS core.env (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL UNIQUE,
    project_id INTEGER NOT NULL,
    latitude NUMERIC CHECK (latitude >= 48 AND latitude <= 60),
    longitude NUMERIC CHECK (longitude >= -140 AND longitude <= -114),
    elevation_m INTEGER CHECK (elevation_m >= 0 AND elevation_m <= 4000),
    survey_date DATE,
    surveyor_name TEXT,
    plot_notes TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    modified_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_env_plot ON core.env(plot_number);
CREATE INDEX IF NOT EXISTS idx_env_project ON core.env(project_id);
CREATE INDEX IF NOT EXISTS idx_env_modified ON core.env(last_modified_utc);

CREATE TRIGGER env_row_version
    BEFORE INSERT OR UPDATE ON core.env
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER env_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.env
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();


-- core.veg: vegetation/species data
CREATE TABLE IF NOT EXISTS core.veg (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL,
    species_code TEXT NOT NULL,
    layer_code TEXT,
    cover1 REAL,
    height1 REAL,
    cover2 REAL,
    height2 REAL,
    cover3 REAL,
    height3 REAL,
    totala REAL,
    heighta REAL,
    cover4 REAL,
    height4 REAL,
    cover5 REAL,
    height5 REAL,
    cover5a REAL,
    height5a REAL,
    cover5b REAL,
    height5b REAL,
    cover5c REAL,
    height5c REAL,
    totalb REAL,
    heightb TEXT,
    cover6 REAL,
    height6 REAL,
    cover7 REAL,
    cover8 REAL,
    cover9 REAL,
    cover10 REAL,
    collected TEXT,
    flag BOOLEAN,
    veg_id INTEGER,
    ll INTEGER,
    af INTEGER,
    dc INTEGER,
    ut INTEGER,
    vi INTEGER,
    pv INTEGER,
    pg INTEGER,
    ffa INTEGER,
    cultural1 INTEGER,
    cultural2 INTEGER,
    other1 INTEGER,
    other2 INTEGER,
    project_id INTEGER NOT NULL,
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL,
    UNIQUE(plot_number, species_code, layer_code, project_id)
);

CREATE INDEX IF NOT EXISTS idx_veg_plot ON core.veg(plot_number);
CREATE INDEX IF NOT EXISTS idx_veg_project ON core.veg(project_id);
CREATE INDEX IF NOT EXISTS idx_veg_species ON core.veg(species_code);

CREATE TRIGGER veg_row_version
    BEFORE INSERT OR UPDATE ON core.veg
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();


CREATE TRIGGER veg_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.veg
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();


-- core.su: site unit (BEC zone/subzone/series)
CREATE TABLE IF NOT EXISTS core.su (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL UNIQUE,
    project_id INTEGER NOT NULL,
    su_number TEXT,
    bec_zone TEXT,
    bec_subzone TEXT,
    site_series TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    modified_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_su_plot ON core.su(plot_number);
CREATE INDEX IF NOT EXISTS idx_su_modified ON core.su(last_modified_utc);

CREATE TRIGGER su_row_version
    BEFORE INSERT OR UPDATE ON core.su
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER su_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.su
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();


-- core.admin: QA/review status per plot
CREATE TABLE IF NOT EXISTS core.admin (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL UNIQUE,
    project_id INTEGER NOT NULL,
    qa_status TEXT DEFAULT 'unreviewed' CHECK (qa_status IN ('unreviewed', 'pending', 'approved', 'rejected')),
    qa_comments TEXT,
    qa_by TEXT,
    qa_date TIMESTAMPTZ,
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL
);

-- core.vw_usysallveg: view flattening multi-layer veg into single layer per row
CREATE OR REPLACE VIEW core.vw_usysallveg AS
SELECT plot_number AS plotnumber, '1' AS mylayer, species_code AS species, cover1 AS cover FROM core.veg WHERE cover1 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '2' AS mylayer, species_code AS species, cover2 AS cover FROM core.veg WHERE cover2 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '3' AS mylayer, species_code AS species, cover3 AS cover FROM core.veg WHERE cover3 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '4' AS mylayer, species_code AS species, cover4 AS cover FROM core.veg WHERE cover4 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '5' AS mylayer, species_code AS species, cover5 AS cover FROM core.veg WHERE cover5 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '5a' AS mylayer, species_code AS species, cover5a AS cover FROM core.veg WHERE cover5a IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '5b' AS mylayer, species_code AS species, cover5b AS cover FROM core.veg WHERE cover5b IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '5c' AS mylayer, species_code AS species, cover5c AS cover FROM core.veg WHERE cover5c IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '6' AS mylayer, species_code AS species, cover6 AS cover FROM core.veg WHERE cover6 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '7' AS mylayer, species_code AS species, cover7 AS cover FROM core.veg WHERE cover7 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '8' AS mylayer, species_code AS species, cover8 AS cover FROM core.veg WHERE cover8 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '9' AS mylayer, species_code AS species, cover9 AS cover FROM core.veg WHERE cover9 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '10' AS mylayer, species_code AS species, cover10 AS cover FROM core.veg WHERE cover10 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, 'A' AS mylayer, species_code AS species, totala AS cover FROM core.veg WHERE totala IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, 'B' AS mylayer, species_code AS species, totalb AS cover FROM core.veg WHERE totalb IS NOT NULL;


-- ============================================================================
-- ADMIN SCHEMA - User & Role Management (must come BEFORE STAGING)
-- ============================================================================



CREATE TABLE IF NOT EXISTS admin.users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    app_role TEXT NOT NULL DEFAULT 'guest' CHECK (app_role IN ('guest', 'admin')),
    password_hash TEXT,                                 -- NULL for guests; bcrypt hash for admins
    is_active BOOLEAN DEFAULT TRUE,
    created_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    last_login_utc TIMESTAMPTZ
);


-- admin.change_log: audit log for all changes
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

-- admin.merge_requests: merge request lifecycle governance
CREATE TABLE IF NOT EXISTS admin.merge_requests (
    id SERIAL PRIMARY KEY,
    project_id INTEGER NOT NULL,
    submitter_name TEXT NOT NULL,
    submitter_email TEXT,                               -- optional
    submitted_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    status TEXT NOT NULL DEFAULT 'pending_review'
        CHECK (status IN ('pending_review', 'approved', 'rejected', 'merged')),
    reviewer TEXT,
    review_notes TEXT,
    reviewed_utc TIMESTAMPTZ,
    -- per-table record counts populated by sync_push()
    env_record_count INTEGER NOT NULL DEFAULT 0,
    su_record_count  INTEGER NOT NULL DEFAULT 0,
    veg_record_count INTEGER NOT NULL DEFAULT 0,
    -- compliance gate (populated by staging_compliance_checks if loaded)
    compliance_passed BOOLEAN,
    compliance_report TEXT
);

CREATE INDEX IF NOT EXISTS idx_merge_requests_status ON admin.merge_requests(status);
CREATE INDEX IF NOT EXISTS idx_merge_requests_submitted ON admin.merge_requests(submitted_utc);

-- admin.merge_conflicts: row-level conflicts detected during admin review.
-- One row per conflicted record (not per column); field-level diff stored in `details` JSONB.
-- Conflict is detected when core.row_version > staging.base_row_version at review time.
CREATE TABLE IF NOT EXISTS admin.merge_conflicts (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    table_name TEXT NOT NULL,
    plot_number TEXT,
    project_id TEXT,                -- stored as TEXT for cross-type comparison
    species_code TEXT NOT NULL DEFAULT '',   -- '' for env/su conflicts
    layer_code   TEXT NOT NULL DEFAULT '',   -- '' for env/su conflicts
    details JSONB,                  -- {field: {staged: val, core: val}, row_version: {staged_base, core_current}}
    resolution TEXT CHECK (resolution IN ('keep_staged', 'keep_core', 'dismiss')),
    resolved_by TEXT,
    resolved_utc TIMESTAMPTZ,
    created_utc TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(merge_request_id, table_name, plot_number, project_id, species_code, layer_code)
);

CREATE INDEX IF NOT EXISTS idx_merge_conflicts_request ON admin.merge_conflicts(merge_request_id);

-- admin.merge_history: approved merge outcomes
CREATE TABLE IF NOT EXISTS admin.merge_history (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id),
    merged_utc TIMESTAMPTZ DEFAULT now(),
    approved_by_user_id INTEGER NOT NULL REFERENCES admin.users(id),
    record_count INTEGER,
    merge_summary JSONB
);


-- ============================================================================
-- STAGING SCHEMA - Pending Uploads
-- ============================================================================

-- staging.veg: mirrors core.veg with change tracking
CREATE TABLE IF NOT EXISTS staging.veg (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL CHECK (change_type IN ('I','U','D')),
    -- base_row_version: the row_version in core at the time the user last synced.
    -- NULL means the row is new (did not exist in core at push time).
    -- Conflict = core.row_version > base_row_version at review time.
    base_row_version INTEGER,
    plot_number TEXT NOT NULL,
    species_code TEXT NOT NULL,
    layer_code TEXT,
    cover1 REAL,
    height1 REAL,
    cover2 REAL,
    height2 REAL,
    cover3 REAL,
    height3 REAL,
    totala REAL,
    heighta REAL,
    cover4 REAL,
    height4 REAL,
    cover5 REAL,
    height5 REAL,
    cover5a REAL,
    height5a REAL,
    cover5b REAL,
    height5b REAL,
    cover5c REAL,
    height5c REAL,
    totalb REAL,
    heightb TEXT,
    cover6 REAL,
    height6 REAL,
    cover7 REAL,
    cover8 REAL,
    cover9 REAL,
    cover10 REAL,
    collected TEXT,
    flag BOOLEAN,
    veg_id INTEGER,
    ll INTEGER,
    af INTEGER,
    dc INTEGER,
    ut INTEGER,
    vi INTEGER,
    pv INTEGER,
    pg INTEGER,
    ffa INTEGER,
    cultural1 INTEGER,
    cultural2 INTEGER,
    other1 INTEGER,
    other2 INTEGER,
    project_id INTEGER NOT NULL,
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_staging_veg_request ON staging.veg(merge_request_id);
CREATE INDEX IF NOT EXISTS idx_staging_veg_plot ON staging.veg(plot_number);
CREATE INDEX IF NOT EXISTS idx_staging_veg_project ON staging.veg(project_id);

-- staging.env: mirrors core.env with change tracking
CREATE TABLE IF NOT EXISTS staging.env (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL CHECK (change_type IN ('I','U','D')),
    -- base_row_version: core.row_version captured at push time (NULL = new row).
    base_row_version INTEGER,
    plot_number TEXT NOT NULL,
    project_id INTEGER NOT NULL,
    latitude NUMERIC,
    longitude NUMERIC,
    elevation_m INTEGER,
    survey_date DATE,
    surveyor_name TEXT,
    plot_notes TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    modified_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_staging_env_request ON staging.env(merge_request_id);
CREATE INDEX IF NOT EXISTS idx_staging_env_plot ON staging.env(plot_number);
CREATE INDEX IF NOT EXISTS idx_staging_env_project ON staging.env(project_id);

-- staging.su: mirrors core.su with change tracking
CREATE TABLE IF NOT EXISTS staging.su (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL CHECK (change_type IN ('I','U','D')),
    -- base_row_version: core.row_version captured at push time (NULL = new row).
    base_row_version INTEGER,
    plot_number TEXT NOT NULL,
    project_id INTEGER NOT NULL,
    su_number TEXT,
    bec_zone TEXT,
    bec_subzone TEXT,
    site_series TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    modified_by TEXT
);

CREATE INDEX IF NOT EXISTS idx_staging_su_request ON staging.su(merge_request_id);
CREATE INDEX IF NOT EXISTS idx_staging_su_plot ON staging.su(plot_number);


-- ============================================================================
-- PUBLIC_EXPORT SCHEMA - RDS Snapshots & Download Log
-- ============================================================================

CREATE TABLE IF NOT EXISTS public_export.rds_snapshots (
    id SERIAL PRIMARY KEY,
    version TEXT NOT NULL UNIQUE,
    snapshot_date DATE DEFAULT CURRENT_DATE,
    created_utc TIMESTAMPTZ DEFAULT now(),
    created_by TEXT NOT NULL,
    rds_filename_veg TEXT,
    rds_filename_env TEXT,
    veg_row_count INTEGER,
    env_row_count INTEGER,
    md5_hash_veg TEXT,
    md5_hash_env TEXT,
    snapshot_metadata JSONB
);

CREATE TABLE IF NOT EXISTS public_export.download_log (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES admin.users(id),
    username TEXT DEFAULT 'anonymous',
    timestamp_utc TIMESTAMPTZ DEFAULT now(),
    dataset_name TEXT NOT NULL,
    format TEXT NOT NULL CHECK (format IN ('rds', 'csv', 'excel')),
    filters_applied JSONB,
    row_count INTEGER,
    ip_address INET,
    download_status TEXT DEFAULT 'success' CHECK (download_status IN ('success', 'failed')),
    error_message TEXT
);

CREATE INDEX IF NOT EXISTS idx_download_log_timestamp ON public_export.download_log(timestamp_utc);
CREATE INDEX IF NOT EXISTS idx_download_log_user ON public_export.download_log(username);


-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Seed: species list (10 common BC species)
INSERT INTO lists.spplist (spp_code, spp_name, spp_scientific, is_active) VALUES
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
ON CONFLICT (spp_code) DO NOTHING;

-- Seed: layer codes (5 standard layers)
INSERT INTO lists.layercode (layer_code, layer_name, sort_order) VALUES
    ('T1', 'Tree canopy layer 1', 1),
    ('T2', 'Tree canopy layer 2', 2),
    ('S', 'Shrub layer', 3),
    ('H', 'Herb layer', 4),
    ('M', 'Moss layer', 5)
ON CONFLICT (layer_code) DO NOTHING;

-- Seed: BEC zones (7 common zones)
INSERT INTO lists.usyszonelist (zone_code, zone_name, province) VALUES
    ('CDF', 'Coastal Douglas-fir', 'BC'),
    ('CWH', 'Coastal Western Hemlock', 'BC'),
    ('MH', 'Mountain Hemlock', 'BC'),
    ('ESSF', 'Engelmann Spruce - Subalpine Fir', 'BC'),
    ('ICH', 'Interior Cedar - Hemlock', 'BC'),
    ('IDF', 'Interior Douglas-fir', 'BC'),
    ('MS', 'Montane Spruce', 'BC')
ON CONFLICT (zone_code) DO NOTHING;

-- Seed: BEC subzones (7 examples)
INSERT INTO lists.usyssubzonelist (zone_code, subzone_code, subzone_name) VALUES
    ('CWH', 'dm', 'dry maritime'),
    ('CWH', 'vm', 'very dry maritime'),
    ('CWH', 'xm', 'very wet maritime'),
    ('ICH', 'mk', 'moist cool'),
    ('IDF', 'dk', 'dry cool'),
    ('ESSF', 'mk', 'moist cool'),
    ('MH', 'mm', 'moist maritime')
ON CONFLICT (zone_code, subzone_code) DO NOTHING;

-- Seed: generic list values
INSERT INTO lists.usystableoflists (list_id, item_code, item_name, item_sort) VALUES
    ('COVER_CLASS', '1', '0-1%', 1),
    ('COVER_CLASS', '2', '1-5%', 2),
    ('COVER_CLASS', '3', '5-25%', 3),
    ('COVER_CLASS', '4', '25-50%', 4),
    ('COVER_CLASS', '5', '50-75%', 5),
    ('COVER_CLASS', '6', '75-100%', 6)
ON CONFLICT (list_id, item_code) DO NOTHING;

-- Seed: test users (admin accounts need password set via auth_grant_admin before first use)
INSERT INTO admin.users (email, full_name, app_role, is_active) VALUES
    ('viewer@test.local',  'Test Viewer',       'guest', TRUE),
    ('field@test.local',   'Test Field User',   'guest', TRUE),
    ('lead@test.local',    'Test Project Lead', 'guest', TRUE),
    ('dba@test.local',     'Test DBA',          'admin', TRUE),
    ('admin@test.local',   'Test Admin',        'admin', TRUE)
ON CONFLICT (email) DO NOTHING;

-- Seed: sample project
INSERT INTO core.metadata (project_id, project_name, description, organization, contact_email, modified_by) VALUES
    (1, 'Test Project Alpha', 'Initial test dataset for BECMaster', 'Test Organization', 'test@example.com', 'test_admin')
ON CONFLICT (project_id) DO NOTHING;

