-- BECMaster PostgreSQL Schema & Test Data
-- This script creates the complete schema structure for cloud-based VPro data management

-- ============================================================================
-- SCHEMAS
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS lists;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS admin;
CREATE SCHEMA IF NOT EXISTS public_export;

-- ============================================================================
-- CORE SCHEMA - Approved Plot Data
-- ============================================================================

CREATE TABLE IF NOT EXISTS core.sample_veg (
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
SELECT plot_number AS plotnumber, '1' AS mylayer, species_code AS species, cover1 AS cover FROM core.sample_veg WHERE cover1 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '2' AS mylayer, species_code AS species, cover2 AS cover FROM core.sample_veg WHERE cover2 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '3' AS mylayer, species_code AS species, cover3 AS cover FROM core.sample_veg WHERE cover3 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '4' AS mylayer, species_code AS species, cover4 AS cover FROM core.sample_veg WHERE cover4 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '5' AS mylayer, species_code AS species, cover5 AS cover FROM core.sample_veg WHERE cover5 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '5a' AS mylayer, species_code AS species, cover5a AS cover FROM core.sample_veg WHERE cover5a IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '5b' AS mylayer, species_code AS species, cover5b AS cover FROM core.sample_veg WHERE cover5b IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '5c' AS mylayer, species_code AS species, cover5c AS cover FROM core.sample_veg WHERE cover5c IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '6' AS mylayer, species_code AS species, cover6 AS cover FROM core.sample_veg WHERE cover6 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '7' AS mylayer, species_code AS species, cover7 AS cover FROM core.sample_veg WHERE cover7 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '8' AS mylayer, species_code AS species, cover8 AS cover FROM core.sample_veg WHERE cover8 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '9' AS mylayer, species_code AS species, cover9 AS cover FROM core.sample_veg WHERE cover9 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, '10' AS mylayer, species_code AS species, cover10 AS cover FROM core.sample_veg WHERE cover10 IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, 'A' AS mylayer, species_code AS species, totala AS cover FROM core.sample_veg WHERE totala IS NOT NULL
UNION ALL
SELECT plot_number AS plotnumber, 'B' AS mylayer, species_code AS species, totalb AS cover FROM core.sample_veg WHERE totalb IS NOT NULL;

CREATE TABLE IF NOT EXISTS core.sample_env (
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

CREATE TABLE IF NOT EXISTS core.sample_su (
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

CREATE TABLE IF NOT EXISTS core.sample_admin (
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

CREATE TABLE IF NOT EXISTS core.sample_metadata (
    id SERIAL PRIMARY KEY,
    project_id INTEGER NOT NULL UNIQUE,
    project_name TEXT NOT NULL,
    description TEXT,
    organization TEXT,
    contact_email TEXT,
    created_utc TIMESTAMPTZ DEFAULT now(),
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL
);

-- ============================================================================
-- LISTS SCHEMA - Reference & Lookup Tables
-- ============================================================================

CREATE TABLE IF NOT EXISTS lists.spplist (
    spp_code TEXT PRIMARY KEY,
    spp_name TEXT NOT NULL,
    spp_scientific TEXT,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS lists.layercode (
    layer_code TEXT PRIMARY KEY,
    layer_name TEXT NOT NULL,
    sort_order INTEGER
);

CREATE TABLE IF NOT EXISTS lists.usyszonelist (
    zone_code TEXT PRIMARY KEY,
    zone_name TEXT NOT NULL,
    province TEXT
);

CREATE TABLE IF NOT EXISTS lists.usyssubzonelist (
    zone_code TEXT,
    subzone_code TEXT,
    subzone_name TEXT,
    PRIMARY KEY (zone_code, subzone_code),
    FOREIGN KEY (zone_code) REFERENCES lists.usyszonelist(zone_code)
);

CREATE TABLE IF NOT EXISTS lists.mastersiteunitlist (
    su_code TEXT PRIMARY KEY,
    su_name TEXT NOT NULL,
    zone_code TEXT,
    FOREIGN KEY (zone_code) REFERENCES lists.usyszonelist(zone_code)
);

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

CREATE TABLE IF NOT EXISTS staging.sample_veg (
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
    merge_request_id INTEGER NOT NULL,
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS staging.sample_env (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL,
    project_id INTEGER NOT NULL,
    latitude NUMERIC(9, 6),
    longitude NUMERIC(10, 6),
    elevation_m INTEGER,
    survey_date DATE,
    surveyor_name TEXT,
    plot_notes TEXT,
    merge_request_id INTEGER NOT NULL,
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS staging.sample_su (
    id SERIAL PRIMARY KEY,
    plot_number TEXT NOT NULL,
    project_id INTEGER NOT NULL,
    su_number TEXT,
    bec_zone TEXT,
    bec_subzone TEXT,
    site_series TEXT,
    merge_request_id INTEGER NOT NULL,
    row_version INTEGER DEFAULT 1,
    last_modified_utc TIMESTAMPTZ DEFAULT now(),
    modified_by TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS admin.merge_requests (
    id SERIAL PRIMARY KEY,
    project_id INTEGER NOT NULL,
    submitter_user_id TEXT NOT NULL,
    submitted_utc TIMESTAMPTZ DEFAULT now(),
    status TEXT DEFAULT 'pending_review' CHECK (status IN ('pending_review', 'approved', 'rejected', 'merged')),
    reviewer_user_id TEXT,
    review_notes TEXT,
    reviewed_utc TIMESTAMPTZ,
    veg_record_count INTEGER DEFAULT 0,
    env_record_count INTEGER DEFAULT 0,
    compliance_passed BOOLEAN DEFAULT FALSE,
    compliance_report JSONB
);

CREATE TABLE IF NOT EXISTS staging.merge_conflicts (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL,
    table_name TEXT NOT NULL,
    plot_number TEXT NOT NULL,
    column_name TEXT NOT NULL,
    local_value TEXT,
    incoming_value TEXT,
    resolved BOOLEAN DEFAULT FALSE,
    resolution TEXT,
    FOREIGN KEY (merge_request_id) REFERENCES admin.merge_requests(id)
);

-- ============================================================================
-- ADMIN SCHEMA - Users, Roles, Audit & Change Tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS admin.users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    full_name TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_utc TIMESTAMPTZ DEFAULT now(),
    last_login_utc TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS admin.roles (
    id SERIAL PRIMARY KEY,
    role_name TEXT NOT NULL UNIQUE,
    description TEXT,
    permissions TEXT[] DEFAULT ARRAY[]::TEXT[]
);

CREATE TABLE IF NOT EXISTS admin.user_roles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    role_id INTEGER NOT NULL,
    assigned_utc TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (user_id) REFERENCES admin.users(id),
    FOREIGN KEY (role_id) REFERENCES admin.roles(id),
    UNIQUE(user_id, role_id)
);

CREATE TABLE IF NOT EXISTS admin.user_restrictions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    project_id INTEGER,
    bec_zone TEXT,
    restriction_type TEXT NOT NULL CHECK (restriction_type IN ('project', 'zone', 'tag')),
    created_utc TIMESTAMPTZ DEFAULT now(),
    FOREIGN KEY (user_id) REFERENCES admin.users(id)
);

CREATE TABLE IF NOT EXISTS admin.change_log (
    id SERIAL PRIMARY KEY,
    sync_id TEXT,
    user_id INTEGER,
    username TEXT NOT NULL,
    timestamp_utc TIMESTAMPTZ DEFAULT now(),
    operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'MERGE', 'SYNC_PULL', 'SYNC_PUSH')),
    table_name TEXT NOT NULL,
    record_id TEXT,
    plot_number TEXT,
    field_name TEXT,
    old_value TEXT,
    new_value TEXT,
    change_reason TEXT,
    FOREIGN KEY (user_id) REFERENCES admin.users(id)
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

CREATE INDEX IF NOT EXISTS idx_sample_veg_plot ON core.sample_veg(plot_number);
CREATE INDEX IF NOT EXISTS idx_sample_veg_project ON core.sample_veg(project_id);
CREATE INDEX IF NOT EXISTS idx_sample_veg_species ON core.sample_veg(species_code);
CREATE INDEX IF NOT EXISTS idx_sample_env_plot ON core.sample_env(plot_number);
CREATE INDEX IF NOT EXISTS idx_sample_env_project ON core.sample_env(project_id);
CREATE INDEX IF NOT EXISTS idx_change_log_timestamp ON admin.change_log(timestamp_utc);
CREATE INDEX IF NOT EXISTS idx_change_log_user ON admin.change_log(username);
CREATE INDEX IF NOT EXISTS idx_download_log_timestamp ON public_export.download_log(timestamp_utc);
CREATE INDEX IF NOT EXISTS idx_download_log_user ON public_export.download_log(username);

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Reference species
INSERT INTO lists.spplist (spp_code, spp_name, spp_scientific, is_active) VALUES
('AB', 'Abies lasiocarpa', 'Subalpine Fir', TRUE),
('AT', 'Athyrium filix-femina', 'Lady Fern', TRUE),
('DR', 'Dryas integrifolia', 'Entire-leaved Avens', TRUE),
('FD', 'Pseudotsuga menziesii', 'Douglas-fir', TRUE),
('HW', 'Tsuga heterophylla', 'Western Hemlock', TRUE),
('PA', 'Pinus albicaulis', 'Whitebark Pine', TRUE),
('PW', 'Pinus ponderosa', 'Ponderosa Pine', TRUE),
('SX', 'Picea sitchensis', 'Sitka Spruce', TRUE),
('SW', 'Pinus strobus', 'Eastern White Pine', TRUE),
('YC', 'Thuja plicata', 'Western Redcedar', TRUE)
ON CONFLICT DO NOTHING;

-- Layer codes
INSERT INTO lists.layercode (layer_code, layer_name, sort_order) VALUES
('T', 'Tree', 1),
('S', 'Shrub', 2),
('H', 'Herb', 3),
('M', 'Moss', 4),
('L', 'Lichen', 5)
ON CONFLICT DO NOTHING;

-- BEC zones
INSERT INTO lists.usyszonelist (zone_code, zone_name, province) VALUES
('AT', 'Alpine Tundra', 'BC'),
('BWBS', 'Boreal White and Black Spruce', 'BC'),
('CDF', 'Coastal Douglas-fir', 'BC'),
('ICH', 'Interior Cedar-Hemlock', 'BC'),
('IDF', 'Interior Douglas-fir', 'BC'),
('MH', 'Mountain Hemlock', 'BC'),
('SBPS', 'Sub-Boreal Pine-Spruce', 'BC')
ON CONFLICT DO NOTHING;

-- Sub-zones
INSERT INTO lists.usyssubzonelist (zone_code, subzone_code, subzone_name) VALUES
('AT', 'a', 'Alpine Tundra - a'),
('CDF', 'mm', 'Moist Maritime'),
('CDF', 'xm', 'Xeric Maritime'),
('ICH', 'dw', 'Dry Warm'),
('ICH', 'mw', 'Moist Warm'),
('IDF', 'dw', 'Dry Warm'),
('MH', 'mm', 'Moist Maritime')
ON CONFLICT DO NOTHING;

-- Generic list values
INSERT INTO lists.usystableoflists (list_id, item_code, item_name, item_sort) VALUES
('COVER_CODE', '+', 'Trace', 1),
('COVER_CODE', 'r', 'Rare', 2),
('COVER_CODE', 'P', 'Present', 3),
('QA_STATUS', 'unreviewed', 'Unreviewed', 1),
('QA_STATUS', 'pending', 'Pending Review', 2),
('QA_STATUS', 'approved', 'Approved', 3),
('QA_STATUS', 'rejected', 'Rejected', 4),
('SURVEY_TYPE', 'field', 'Field Survey', 1),
('SURVEY_TYPE', 'desktop', 'Desktop Review', 2)
ON CONFLICT DO NOTHING;

-- Species attributes
INSERT INTO lists.usyssppattributes (spp_code, tree_shrub_herb, native_introduced) VALUES
('AB', 'Tree', 'Native'),
('AT', 'Herb', 'Native'),
('DR', 'Herb', 'Native'),
('FD', 'Tree', 'Native'),
('HW', 'Tree', 'Native'),
('PA', 'Tree', 'Native'),
('PW', 'Tree', 'Native'),
('SX', 'Tree', 'Native'),
('SW', 'Tree', 'Native'),
('YC', 'Tree', 'Native')
ON CONFLICT DO NOTHING;

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
INSERT INTO core.sample_metadata (project_id, project_name, description, organization, contact_email, modified_by) VALUES
(1, 'Test Project Alpha', 'Initial test dataset for BECMaster', 'Test Organization', 'test@example.com', 'test_admin')
ON CONFLICT DO NOTHING;
