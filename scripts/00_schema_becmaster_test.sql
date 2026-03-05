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

CREATE TABLE IF NOT EXISTS core.env (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL UNIQUE,
    project_id INTEGER NOT NULL,
    latitude NUMERIC(9, 6) CHECK (latitude >= 48 AND latitude <= 60),
    longitude NUMERIC(10, 6) CHECK (longitude >= -140 AND longitude <= -114),
    elevation_m INTEGER CHECK (elevation_m >= 0 AND elevation_m <= 4000),
    survey_date DATE,
    surveyor_name TEXT,
    plot_notes TEXT,
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS core.su (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL UNIQUE,
    project_id INTEGER NOT NULL,
    su_number TEXT,
    bec_zone TEXT,
    bec_subzone TEXT,
    site_series TEXT,
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL
);

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

CREATE TABLE IF NOT EXISTS lists.usystableoflists (
    list_id TEXT,
    item_code TEXT,
    item_name TEXT NOT NULL,
    item_sort INTEGER,
    PRIMARY KEY (list_id, item_code)
);

CREATE TABLE IF NOT EXISTS lists.usyssppattributes (
    spp_code TEXT PRIMARY KEY,
    tree_shrub_herb TEXT,
    native_introduced TEXT,
    FOREIGN KEY (spp_code) REFERENCES lists.spplist(spp_code)
);

-- ============================================================================
-- STAGING SCHEMA - Pending Uploads & Merge Requests
-- ============================================================================

CREATE TABLE IF NOT EXISTS staging.veg (
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
    row_version INTEGER NOT NULL DEFAULT 1,
    last_modified_utc TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    modified_by TEXT,
    UNIQUE(plot_number, species_code, layer_code, project_id)
);

CREATE TABLE IF NOT EXISTS staging.env (
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

CREATE TABLE IF NOT EXISTS staging.su (
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

CREATE TABLE IF NOT EXISTS admin.merge_history (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL,
    merged_utc TIMESTAMPTZ DEFAULT now(),
    approved_by_user_id INTEGER NOT NULL,
    record_count INTEGER,
    merge_summary JSONB,
    FOREIGN KEY (merge_request_id) REFERENCES admin.merge_requests(id),
    FOREIGN KEY (approved_by_user_id) REFERENCES admin.users(id)
);

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
    user_id INTEGER,
    username TEXT DEFAULT 'anonymous',
    timestamp_utc TIMESTAMPTZ DEFAULT now(),
    dataset_name TEXT NOT NULL,
    format TEXT NOT NULL CHECK (format IN ('rds', 'csv', 'excel')),
    filters_applied JSONB,
    row_count INTEGER,
    ip_address INET,
    download_status TEXT DEFAULT 'success' CHECK (download_status IN ('success', 'failed')),
    error_message TEXT,
    FOREIGN KEY (user_id) REFERENCES admin.users(id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_veg_plot ON core.veg(plot_number);
CREATE INDEX IF NOT EXISTS idx_veg_project ON core.veg(project_id);
CREATE INDEX IF NOT EXISTS idx_veg_species ON core.veg(species_code);
CREATE INDEX IF NOT EXISTS idx_env_plot ON core.env(plot_number);
CREATE INDEX IF NOT EXISTS idx_env_project ON core.env(project_id);
CREATE INDEX IF NOT EXISTS idx_change_log_timestamp ON admin.change_log(timestamp_utc);
CREATE INDEX IF NOT EXISTS idx_change_log_user ON admin.change_log(username);
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

-- Default roles
INSERT INTO admin.roles (role_name, description, permissions) VALUES
('viewer', 'Read-only access to public/exported data', ARRAY['read:public']),
('field_user', 'Enter/edit own plots, upload datasets', ARRAY['read:own_projects', 'write:own_plots', 'create:merge_requests']),
('project_lead', 'Manage project plots, approve uploads', ARRAY['read:project', 'write:project_plots', 'approve:merge_requests']),
('db_manager', 'Review merges, edit all data, manage codes', ARRAY['read:all', 'write:all', 'merge:all', 'manage:codes', 'publish_rds', 'view_download_logs']),
('admin', 'Full system access', ARRAY['*', 'publish_rds', 'view_download_logs'])
ON CONFLICT (role_name) DO NOTHING;

-- Test users
INSERT INTO admin.users (username, email, password_hash, full_name, is_active) VALUES
('test_viewer', 'viewer@test.local', '$2a$10$test_hash_viewer', 'Test Viewer', TRUE),
('test_field', 'field@test.local', '$2a$10$test_hash_field', 'Test Field User', TRUE),
('test_lead', 'lead@test.local', '$2a$10$test_hash_lead', 'Test Project Lead', TRUE),
('test_dba', 'dba@test.local', '$2a$10$test_hash_dba', 'Test DBA', TRUE),
('test_admin', 'admin@test.local', '$2a$10$test_hash_admin', 'Test Admin', TRUE)
ON CONFLICT (username) DO NOTHING;

-- Assign roles to test users
INSERT INTO admin.user_roles (user_id, role_id)
SELECT u.id, r.id FROM admin.users u, admin.roles r
WHERE u.username = 'test_viewer' AND r.role_name = 'viewer'
ON CONFLICT DO NOTHING;

INSERT INTO admin.user_roles (user_id, role_id)
SELECT u.id, r.id FROM admin.users u, admin.roles r
WHERE u.username = 'test_field' AND r.role_name = 'field_user'
ON CONFLICT DO NOTHING;

INSERT INTO admin.user_roles (user_id, role_id)
SELECT u.id, r.id FROM admin.users u, admin.roles r
WHERE u.username = 'test_lead' AND r.role_name = 'project_lead'
ON CONFLICT DO NOTHING;

INSERT INTO admin.user_roles (user_id, role_id)
SELECT u.id, r.id FROM admin.users u, admin.roles r
WHERE u.username = 'test_dba' AND r.role_name = 'db_manager'
ON CONFLICT DO NOTHING;

INSERT INTO admin.user_roles (user_id, role_id)
SELECT u.id, r.id FROM admin.users u, admin.roles r
WHERE u.username = 'test_admin' AND r.role_name = 'admin'
ON CONFLICT DO NOTHING;

-- Sample project
INSERT INTO core.metadata (project_id, project_name, description, organization, contact_email, modified_by) VALUES
(1, 'Test Project Alpha', 'Initial test dataset for BECMaster', 'Test Organization', 'test@example.com', 'test_admin')
ON CONFLICT DO NOTHING;
