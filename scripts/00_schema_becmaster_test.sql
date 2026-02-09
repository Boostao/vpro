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

-- ============================================================================
-- SCHEMA 1: audit - Append-only audit log with JSONB
-- Based on: https://exaspark.medium.com/the-ultimate-guide-to-postgresql-data-change-tracking-c3fa88779572
-- ============================================================================

CREATE SCHEMA audit;

-- Audit log table (append-only)
CREATE TABLE audit.logged_actions (
    id SERIAL PRIMARY KEY,
    schema_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    user_name TEXT,
    action_tstamp TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    action TEXT NOT NULL CHECK (action IN ('I','D','U')),
    original_data JSONB,
    new_data JSONB,
    query TEXT
);

CREATE INDEX idx_logged_actions_tstamp ON audit.logged_actions(action_tstamp);
CREATE INDEX idx_logged_actions_table ON audit.logged_actions(schema_name, table_name);

COMMENT ON TABLE audit.logged_actions IS 'Append-only audit log for all data changes in core and lists schemas';
COMMENT ON COLUMN audit.logged_actions.action IS 'I=insert, U=update, D=delete';

-- Generic audit trigger function
CREATE OR REPLACE FUNCTION audit.if_modified_func() 
RETURNS TRIGGER AS $$
DECLARE
    audit_row audit.logged_actions;
    excluded_cols text[] = ARRAY[]::text[];
BEGIN
    IF TG_WHEN <> 'AFTER' THEN
        RAISE EXCEPTION 'audit.if_modified_func() may only run as an AFTER trigger';
    END IF;

    audit_row = ROW(
        nextval('audit.logged_actions_id_seq'),
        TG_TABLE_SCHEMA::text,
        TG_TABLE_NAME::text,
        session_user::text,
        current_timestamp,
        substring(TG_OP,1,1),
        NULL, NULL,
        current_query()
    );

    IF (TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW') THEN
        audit_row.original_data = to_jsonb(OLD.*);
        audit_row.new_data = to_jsonb(NEW.*);
        INSERT INTO audit.logged_actions VALUES (audit_row.*);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE' AND TG_LEVEL = 'ROW') THEN
        audit_row.original_data = to_jsonb(OLD.*);
        INSERT INTO audit.logged_actions VALUES (audit_row.*);
        RETURN OLD;
    ELSIF (TG_OP = 'INSERT' AND TG_LEVEL = 'ROW') THEN
        audit_row.new_data = to_jsonb(NEW.*);
        INSERT INTO audit.logged_actions VALUES (audit_row.*);
        RETURN NEW;
    ELSE
        RAISE WARNING '[audit.if_modified_func] - Other action occurred: %, at %',TG_OP,now();
        RETURN NULL;
    END IF;

EXCEPTION
    WHEN data_exception THEN
        RAISE WARNING '[audit.if_modified_func] - UDF ERROR [DATA EXCEPTION] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
    WHEN unique_violation THEN
        RAISE WARNING '[audit.if_modified_func] - UDF ERROR [UNIQUE] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE WARNING '[audit.if_modified_func] - UDF ERROR [OTHER] - SQLSTATE: %, SQLERRM: %',SQLSTATE,SQLERRM;
        RETURN NULL;
END;
$$
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, audit;

-- ============================================================================
-- SCHEMA 2: core - Approved/merged plot data (source of truth)
-- ============================================================================

CREATE SCHEMA core;

-- Helper function: auto-increment row_version and update last_modified_utc
CREATE OR REPLACE FUNCTION core.row_version_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        NEW.row_version = OLD.row_version + 1;
        NEW.last_modified_utc = now();
    ELSIF (TG_OP = 'INSERT') THEN
        NEW.row_version = 1;
        NEW.last_modified_utc = now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- core.sample_metadata: project-level information
CREATE TABLE core.sample_metadata (
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

CREATE INDEX idx_sample_metadata_modified ON core.sample_metadata(last_modified_utc);

CREATE TRIGGER sample_metadata_row_version
    BEFORE INSERT OR UPDATE ON core.sample_metadata
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER sample_metadata_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.sample_metadata
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.sample_env: environmental/site data
CREATE TABLE core.sample_env (
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

CREATE INDEX idx_sample_env_plot ON core.sample_env(plot_number);
CREATE INDEX idx_sample_env_project ON core.sample_env(project_id);
CREATE INDEX idx_sample_env_modified ON core.sample_env(last_modified_utc);

CREATE TRIGGER sample_env_row_version
    BEFORE INSERT OR UPDATE ON core.sample_env
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER sample_env_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.sample_env
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.sample_su: site unit (BEC zone/subzone/series)
CREATE TABLE core.sample_su (
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

CREATE INDEX idx_sample_su_plot ON core.sample_su(plot_number);
CREATE INDEX idx_sample_su_modified ON core.sample_su(last_modified_utc);

CREATE TRIGGER sample_su_row_version
    BEFORE INSERT OR UPDATE ON core.sample_su
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER sample_su_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.sample_su
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- core.sample_veg: vegetation observations
CREATE TABLE core.sample_veg (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL,
    species_code TEXT NOT NULL,
    layer_code TEXT NOT NULL,
    cover_percent INTEGER CHECK (cover_percent >= 0 AND cover_percent <= 100),
    height_cm INTEGER CHECK (height_cm >= 0),
    cover_code TEXT,
    project_id INTEGER NOT NULL,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    modified_by TEXT,
    UNIQUE(plot_number, species_code, layer_code, project_id)
);

CREATE INDEX idx_sample_veg_plot ON core.sample_veg(plot_number);
CREATE INDEX idx_sample_veg_project ON core.sample_veg(project_id);
CREATE INDEX idx_sample_veg_species ON core.sample_veg(species_code);
CREATE INDEX idx_sample_veg_modified ON core.sample_veg(last_modified_utc);

CREATE TRIGGER sample_veg_row_version
    BEFORE INSERT OR UPDATE ON core.sample_veg
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER sample_veg_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.sample_veg
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- ============================================================================
-- SCHEMA 3: lists - Reference/lookup tables (admin-managed, pull-only)
-- ============================================================================

CREATE SCHEMA lists;

-- lists.spplist: species master list
CREATE TABLE lists.spplist (
    spp_code TEXT PRIMARY KEY,
    spp_name TEXT,
    spp_scientific TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp
);

CREATE INDEX idx_spplist_modified ON lists.spplist(last_modified_utc);

CREATE TRIGGER spplist_row_version
    BEFORE INSERT OR UPDATE ON lists.spplist
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER spplist_audit
    AFTER INSERT OR UPDATE OR DELETE ON lists.spplist
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- lists.layercode: vegetation layers
CREATE TABLE lists.layercode (
    layer_code TEXT PRIMARY KEY,
    layer_name TEXT,
    sort_order INTEGER,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp
);

CREATE INDEX idx_layercode_modified ON lists.layercode(last_modified_utc);

CREATE TRIGGER layercode_row_version
    BEFORE INSERT OR UPDATE ON lists.layercode
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER layercode_audit
    AFTER INSERT OR UPDATE OR DELETE ON lists.layercode
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- lists.usyszonelist: BEC zones
CREATE TABLE lists.usyszonelist (
    zone_code TEXT PRIMARY KEY,
    zone_name TEXT,
    province TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp
);

CREATE INDEX idx_usyszonelist_modified ON lists.usyszonelist(last_modified_utc);

CREATE TRIGGER usyszonelist_row_version
    BEFORE INSERT OR UPDATE ON lists.usyszonelist
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER usyszonelist_audit
    AFTER INSERT OR UPDATE OR DELETE ON lists.usyszonelist
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- lists.usyssubzonelist: BEC subzones
CREATE TABLE lists.usyssubzonelist (
    zone_code TEXT NOT NULL,
    subzone_code TEXT NOT NULL,
    subzone_name TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    PRIMARY KEY (zone_code, subzone_code),
    FOREIGN KEY (zone_code) REFERENCES lists.usyszonelist(zone_code) ON DELETE CASCADE
);

CREATE INDEX idx_usyssubzonelist_modified ON lists.usyssubzonelist(last_modified_utc);

CREATE TRIGGER usyssubzonelist_row_version
    BEFORE INSERT OR UPDATE ON lists.usyssubzonelist
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER usyssubzonelist_audit
    AFTER INSERT OR UPDATE OR DELETE ON lists.usyssubzonelist
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- lists.usystableoflists: generic lookup lists
CREATE TABLE lists.usystableoflists (
    list_id TEXT NOT NULL,
    item_code TEXT NOT NULL,
    item_name TEXT,
    item_sort INTEGER,
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    PRIMARY KEY (list_id, item_code)
);

CREATE INDEX idx_usystableoflists_modified ON lists.usystableoflists(last_modified_utc);

CREATE TRIGGER usystableoflists_row_version
    BEFORE INSERT OR UPDATE ON lists.usystableoflists
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER usystableoflists_audit
    AFTER INSERT OR UPDATE OR DELETE ON lists.usystableoflists
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();

-- ============================================================================
-- SCHEMA 4: staging - Pending user submissions for review
-- ============================================================================

CREATE SCHEMA staging;

-- staging.merge_requests: tracks submission batches
CREATE TABLE staging.merge_requests (
    id SERIAL PRIMARY KEY,
    project_id INTEGER NOT NULL,
    submitter_name TEXT NOT NULL,
    submitter_email TEXT NOT NULL,
    submitted_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    status TEXT NOT NULL DEFAULT 'pending_review' 
        CHECK (status IN ('pending_review', 'approved', 'rejected', 'merged')),
    reviewer TEXT,
    review_notes TEXT,
    reviewed_utc TIMESTAMPTZ,
    record_counts JSONB
);

CREATE INDEX idx_merge_requests_status ON staging.merge_requests(status);
CREATE INDEX idx_merge_requests_submitted ON staging.merge_requests(submitted_utc);

-- staging.merge_conflicts: detected conflicts during review
CREATE TABLE staging.merge_conflicts (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES staging.merge_requests(id) ON DELETE CASCADE,
    table_name TEXT NOT NULL,
    plot_number TEXT,
    column_name TEXT,
    local_value TEXT,
    incoming_value TEXT,
    resolved BOOLEAN DEFAULT FALSE,
    resolution TEXT
);

CREATE INDEX idx_merge_conflicts_request ON staging.merge_conflicts(merge_request_id);

-- staging.sample_veg: pending veg changes
CREATE TABLE staging.sample_veg (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES staging.merge_requests(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL CHECK (change_type IN ('I','U','D')),
    plot_number TEXT NOT NULL,
    species_code TEXT NOT NULL,
    layer_code TEXT NOT NULL,
    cover_percent INTEGER,
    height_cm INTEGER,
    cover_code TEXT,
    project_id INTEGER NOT NULL,
    modified_by TEXT
);

CREATE INDEX idx_staging_sample_veg_request ON staging.sample_veg(merge_request_id);

-- staging.sample_env: pending env changes (no range constraints in staging)
CREATE TABLE staging.sample_env (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES staging.merge_requests(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL CHECK (change_type IN ('I','U','D')),
    plot_number TEXT NOT NULL,
    project_id INTEGER NOT NULL,
    latitude NUMERIC,
    longitude NUMERIC,
    elevation_m INTEGER,
    survey_date DATE,
    surveyor_name TEXT,
    plot_notes TEXT,
    modified_by TEXT
);

CREATE INDEX idx_staging_sample_env_request ON staging.sample_env(merge_request_id);

-- staging.sample_su: pending SU changes
CREATE TABLE staging.sample_su (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES staging.merge_requests(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL CHECK (change_type IN ('I','U','D')),
    plot_number TEXT NOT NULL,
    project_id INTEGER NOT NULL,
    su_number TEXT,
    bec_zone TEXT,
    bec_subzone TEXT,
    site_series TEXT,
    modified_by TEXT
);

CREATE INDEX idx_staging_sample_su_request ON staging.sample_su(merge_request_id);

-- ============================================================================
-- SCHEMA 5: admin - User and sync state management
-- ============================================================================

CREATE SCHEMA admin;

-- admin.users: simple user registry
CREATE TABLE admin.users (
    id SERIAL PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    role TEXT NOT NULL DEFAULT 'reader' CHECK (role IN ('reader', 'writer', 'admin')),
    is_active BOOLEAN DEFAULT TRUE,
    created_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp
);

-- admin.sync_state: tracks per-user, per-table sync watermarks
CREATE TABLE admin.sync_state (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES admin.users(id) ON DELETE CASCADE,
    table_name TEXT NOT NULL,
    last_pulled_utc TIMESTAMPTZ,
    last_pulled_row_version INTEGER,
    UNIQUE(user_id, table_name)
);

CREATE INDEX idx_sync_state_user ON admin.sync_state(user_id);

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
    ('PLEUSCH', 'Schreber''s feather moss', 'Pleurozium schreberi', TRUE);

-- Seed: layer codes (5 standard layers)
INSERT INTO lists.layercode (layer_code, layer_name, sort_order) VALUES
    ('T1', 'Tree canopy layer 1', 1),
    ('T2', 'Tree canopy layer 2', 2),
    ('S', 'Shrub layer', 3),
    ('H', 'Herb layer', 4),
    ('M', 'Moss layer', 5);

-- Seed: BEC zones (7 common zones)
INSERT INTO lists.usyszonelist (zone_code, zone_name, province) VALUES
    ('CDF', 'Coastal Douglas-fir', 'BC'),
    ('CWH', 'Coastal Western Hemlock', 'BC'),
    ('MH', 'Mountain Hemlock', 'BC'),
    ('ESSF', 'Engelmann Spruce - Subalpine Fir', 'BC'),
    ('ICH', 'Interior Cedar - Hemlock', 'BC'),
    ('IDF', 'Interior Douglas-fir', 'BC'),
    ('MS', 'Montane Spruce', 'BC');

-- Seed: BEC subzones (7 examples)
INSERT INTO lists.usyssubzonelist (zone_code, subzone_code, subzone_name) VALUES
    ('CWH', 'dm', 'dry maritime'),
    ('CWH', 'vm', 'very dry maritime'),
    ('CWH', 'xm', 'very wet maritime'),
    ('ICH', 'mk', 'moist cool'),
    ('IDF', 'dk', 'dry cool'),
    ('ESSF', 'mk', 'moist cool'),
    ('MH', 'mm', 'moist maritime');

-- Seed: generic list values
INSERT INTO lists.usystableoflists (list_id, item_code, item_name, item_sort) VALUES
    ('COVER_CLASS', '1', '0-1%', 1),
    ('COVER_CLASS', '2', '1-5%', 2),
    ('COVER_CLASS', '3', '5-25%', 3),
    ('COVER_CLASS', '4', '25-50%', 4),
    ('COVER_CLASS', '5', '50-75%', 5),
    ('COVER_CLASS', '6', '75-100%', 6);

-- Seed: users (3 test users)
INSERT INTO admin.users (username, email, full_name, role, is_active) VALUES
    ('reader_user', 'reader@vpro.test', 'Test Reader', 'reader', TRUE),
    ('writer_user', 'writer@vpro.test', 'Test Writer', 'writer', TRUE),
    ('admin_user', 'admin@vpro.test', 'Test Admin', 'admin', TRUE);

-- Seed: sample project
INSERT INTO core.sample_metadata (project_id, project_name, description, organization, contact_email, modified_by) VALUES
    (1, 'Test Project Alpha', 'Sample project for testing BEC data management', 'BC Ministry of Forests', 'test@vpro.test', 'admin_user');

-- Seed: sample plot environmental data
INSERT INTO core.sample_env (plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes, modified_by) VALUES
    ('PLOT001', 1, 49.2827, -123.1207, 150, '2024-06-15', 'John Doe', 'Typical CWH site near Vancouver', 'admin_user'),
    ('PLOT002', 1, 50.1163, -122.9574, 850, '2024-07-22', 'Jane Smith', 'High elevation ESSF site', 'admin_user');

-- Seed: sample plot site unit data
INSERT INTO core.sample_su (plot_number, project_id, su_number, bec_zone, bec_subzone, site_series, modified_by) VALUES
    ('PLOT001', 1, '01', 'CWH', 'dm', '05', 'admin_user'),
    ('PLOT002', 1, '01', 'ESSF', 'mk', '101', 'admin_user');

-- Seed: sample vegetation data (5 observations)
INSERT INTO core.sample_veg (plot_number, species_code, layer_code, cover_percent, height_cm, cover_code, project_id, modified_by) VALUES
    ('PLOT001', 'TSUGHET', 'T1', 45, 2500, '4', 1, 'admin_user'),
    ('PLOT001', 'THUJOCC', 'T1', 30, 2200, '3', 1, 'admin_user'),
    ('PLOT001', 'VACCOVER', 'S', 15, 80, '2', 1, 'admin_user'),
    ('PLOT002', 'ABIALAM', 'T1', 60, 1800, '5', 1, 'admin_user'),
    ('PLOT002', 'RHYTLOR', 'M', 25, 5, '3', 1, 'admin_user');

-- ============================================================================
-- REVOKE DELETE/UPDATE ON AUDIT (append-only enforcement)
-- Note: These will be executed by roles setup in db_roles.R
-- ============================================================================

-- REVOKE DELETE, UPDATE ON audit.logged_actions FROM PUBLIC;

-- ============================================================================
-- TEST VERIFICATION QUERIES
-- ============================================================================

-- Test 1: Verify seed data counts
SELECT 'Seed data verification:' as test;
SELECT 'Species count:' as metric, COUNT(*) as value FROM lists.spplist
UNION ALL
SELECT 'Layer count:', COUNT(*) FROM lists.layercode
UNION ALL
SELECT 'Zone count:', COUNT(*) FROM lists.usyszonelist
UNION ALL
SELECT 'Subzone count:', COUNT(*) FROM lists.usyssubzonelist
UNION ALL
SELECT 'User count:', COUNT(*) FROM admin.users
UNION ALL
SELECT 'Project count:', COUNT(*) FROM core.sample_metadata
UNION ALL
SELECT 'Plot env count:', COUNT(*) FROM core.sample_env
UNION ALL
SELECT 'Plot SU count:', COUNT(*) FROM core.sample_su
UNION ALL
SELECT 'Veg obs count:', COUNT(*) FROM core.sample_veg;

-- Test 2: Verify initial row_version and triggers
SELECT 'Row version check:' as test;
SELECT id, plot_number, species_code, row_version, last_modified_utc 
FROM core.sample_veg 
LIMIT 3;

-- Test 3: INSERT test → verify audit log
INSERT INTO core.sample_veg (plot_number, species_code, layer_code, cover_percent, height_cm, project_id, modified_by)
VALUES ('PLOT001', 'PINUCON', 'T2', 20, 1500, 1, 'test_user');

SELECT 'Audit log after INSERT:' as test;
SELECT id, schema_name, table_name, action, new_data->>'species_code' as species, new_data->>'cover_percent' as cover
FROM audit.logged_actions 
WHERE table_name = 'sample_veg' AND action = 'I'
ORDER BY id DESC LIMIT 1;

-- Test 4: UPDATE test → verify row_version increment and audit
UPDATE core.sample_veg 
SET cover_percent = 25, height_cm = 1600
WHERE plot_number = 'PLOT001' AND species_code = 'PINUCON';

SELECT 'Row after UPDATE:' as test;
SELECT id, plot_number, species_code, cover_percent, row_version, last_modified_utc
FROM core.sample_veg
WHERE plot_number = 'PLOT001' AND species_code = 'PINUCON';

SELECT 'Audit log after UPDATE:' as test;
SELECT id, action, 
       original_data->>'cover_percent' as old_cover,
       new_data->>'cover_percent' as new_cover,
       original_data->>'row_version' as old_version,
       new_data->>'row_version' as new_version
FROM audit.logged_actions 
WHERE table_name = 'sample_veg' AND action = 'U'
ORDER BY id DESC LIMIT 1;

-- Test 5: DELETE test → verify audit
DELETE FROM core.sample_veg 
WHERE plot_number = 'PLOT001' AND species_code = 'PINUCON';

SELECT 'Audit log after DELETE:' as test;
SELECT id, action, original_data->>'species_code' as species, original_data->>'cover_percent' as cover
FROM audit.logged_actions 
WHERE table_name = 'sample_veg' AND action = 'D'
ORDER BY id DESC LIMIT 1;

-- Final summary
SELECT 'Total audit entries:' as metric, COUNT(*) as value FROM audit.logged_actions;
