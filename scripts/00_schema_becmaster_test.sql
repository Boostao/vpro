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
-- TRIGGER FUNCTIONS
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
    -- Simple audit log: just record the action without detailed state tracking
    INSERT INTO audit.logged_actions ("schemaName", "tableName", "userName", "actionTstampSTM", 
        action, "statementOnly")
    VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, CURRENT_USER, NOW(), 
            CASE TG_OP WHEN 'INSERT' THEN 'I' WHEN 'UPDATE' THEN 'U' WHEN 'DELETE' THEN 'D' END, 
            FALSE);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

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
-- CORE SCHEMA - Main data tables
-- ============================================================================

CREATE TABLE IF NOT EXISTS core.metadata (
    id SERIAL PRIMARY KEY,
    "projectID" TEXT UNIQUE NOT NULL,
    "projectName" TEXT NOT NULL,
    description TEXT,
    organization TEXT,
    "contactEmail" TEXT,
    "createdUTC" TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    "rowVersion" INTEGER NOT NULL DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_metadata_modified ON core.metadata("lastModifiedUTC");

CREATE TRIGGER metadata_row_version
    BEFORE INSERT OR UPDATE ON core.metadata
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER metadata_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.metadata
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();


-- core.env: environmental/site data
CREATE TABLE IF NOT EXISTS core.env (
    id SERIAL PRIMARY KEY,
    "PlotNumber" TEXT NOT NULL UNIQUE,
    "ProjectID" TEXT NOT NULL,
    "Latitude" NUMERIC CHECK ("Latitude" >= 48 AND "Latitude" <= 60),
    "Longitude" NUMERIC CHECK ("Longitude" >= -140 AND "Longitude" <= -114),
    "Elevation" INTEGER CHECK ("Elevation" >= 0 AND "Elevation" <= 4000),
    "SurveyDate" DATE,
    "SurveyorName" TEXT,
    "PlotNotes" TEXT,
    "Zone" TEXT,
    "SubZone" TEXT,
    "SiteSeries" TEXT,
    "rowVersion" INTEGER NOT NULL DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_env_plot ON core.env("PlotNumber");
CREATE INDEX IF NOT EXISTS idx_env_project ON core.env("ProjectID");
CREATE INDEX IF NOT EXISTS idx_env_modified ON core.env("lastModifiedUTC");

CREATE TRIGGER env_row_version
    BEFORE INSERT OR UPDATE ON core.env
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER env_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.env
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();


-- core.veg: vegetation/species data
CREATE TABLE IF NOT EXISTS core.veg (
    id SERIAL PRIMARY KEY,
    "PlotNumber" TEXT NOT NULL,
    "SpeciesCode" TEXT NOT NULL,
    "LayerCode" TEXT,
    "Cover1" REAL,
    "Height1" TEXT,
    "Cover2" REAL,
    "Height2" TEXT,
    "Cover3" REAL,
    "Height3" TEXT,
    "TotalA" REAL,
    "HeightA" TEXT,
    "Cover4" REAL,
    "Height4" TEXT,
    "Cover5" REAL,
    "Height5" TEXT,
    "Cover5a" REAL,
    "Height5a" TEXT,
    "Cover5b" REAL,
    "Height5b" TEXT,
    "Cover5c" REAL,
    "Height5c" TEXT,
    "TotalB" REAL,
    "HeightB" TEXT,
    "Cover6" REAL,
    "Height6" REAL,
    "Cover7" REAL,
    "Cover8" REAL,
    "Cover9" REAL,
    "Cover10" TEXT,
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
    "Cultural1" TEXT,
    "Cultural2" TEXT,
    "Other1" TEXT,
    "Other2" TEXT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT NOT NULL,
    UNIQUE("PlotNumber", "SpeciesCode", "LayerCode")
);

CREATE INDEX IF NOT EXISTS idx_veg_plot ON core.veg("PlotNumber");
CREATE INDEX IF NOT EXISTS idx_veg_species ON core.veg("SpeciesCode");

CREATE TRIGGER veg_row_version
    BEFORE INSERT OR UPDATE ON core.veg
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();


CREATE TRIGGER veg_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.veg
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();


-- core.su: site unit (BEC zone/subzone/series)
CREATE TABLE IF NOT EXISTS core.su (
    id SERIAL PRIMARY KEY,
    "PlotNumber" TEXT NOT NULL UNIQUE,
    "SiteUnit" TEXT,
    "rowVersion" INTEGER NOT NULL DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_su_plot ON core.su("PlotNumber");
CREATE INDEX IF NOT EXISTS idx_su_modified ON core.su("lastModifiedUTC");

CREATE TRIGGER su_row_version
    BEFORE INSERT OR UPDATE ON core.su
    FOR EACH ROW EXECUTE FUNCTION core.row_version_trigger();

CREATE TRIGGER su_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.su
    FOR EACH ROW EXECUTE FUNCTION audit.if_modified_func();


-- core.admin: QA/review status per plot
CREATE TABLE IF NOT EXISTS core.admin (
    id SERIAL PRIMARY KEY,
    "PlotNumber" TEXT NOT NULL UNIQUE,
    "ProjectID" TEXT NOT NULL,
    "qaStatus" TEXT DEFAULT 'unreviewed' CHECK ("qaStatus" IN ('unreviewed', 'pending', 'approved', 'rejected')),
    "qaComments" TEXT,
    "qaBy" TEXT,
    "qaDate" TIMESTAMPTZ,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT NOT NULL
);

-- core.vw_usysallveg: view flattening multi-layer veg into single layer per row
CREATE OR REPLACE VIEW core.vw_usysallveg AS
SELECT "PlotNumber", '1' AS mylayer, "SpeciesCode" AS species, "Cover1" AS cover FROM core.veg WHERE "Cover1" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '2' AS mylayer, "SpeciesCode" AS species, "Cover2" AS cover FROM core.veg WHERE "Cover2" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '3' AS mylayer, "SpeciesCode" AS species, "Cover3" AS cover FROM core.veg WHERE "Cover3" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '4' AS mylayer, "SpeciesCode" AS species, "Cover4" AS cover FROM core.veg WHERE "Cover4" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '5' AS mylayer, "SpeciesCode" AS species, "Cover5" AS cover FROM core.veg WHERE "Cover5" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '5a' AS mylayer, "SpeciesCode" AS species, "Cover5a" AS cover FROM core.veg WHERE "Cover5a" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '5b' AS mylayer, "SpeciesCode" AS species, "Cover5b" AS cover FROM core.veg WHERE "Cover5b" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '5c' AS mylayer, "SpeciesCode" AS species, "Cover5c" AS cover FROM core.veg WHERE "Cover5c" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '6' AS mylayer, "SpeciesCode" AS species, "Cover6" AS cover FROM core.veg WHERE "Cover6" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '7' AS mylayer, "SpeciesCode" AS species, "Cover7" AS cover FROM core.veg WHERE "Cover7" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '8' AS mylayer, "SpeciesCode" AS species, "Cover8" AS cover FROM core.veg WHERE "Cover8" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '9' AS mylayer, "SpeciesCode" AS species, "Cover9" AS cover FROM core.veg WHERE "Cover9" IS NOT NULL
UNION ALL
SELECT "PlotNumber", '10' AS mylayer, "SpeciesCode" AS species, CAST("Cover10" AS REAL) AS cover FROM core.veg WHERE "Cover10" IS NOT NULL
UNION ALL
SELECT "PlotNumber", 'A' AS mylayer, "SpeciesCode" AS species, "TotalA" AS cover FROM core.veg WHERE "TotalA" IS NOT NULL
UNION ALL
SELECT "PlotNumber", 'B' AS mylayer, "SpeciesCode" AS species, "TotalB" AS cover FROM core.veg WHERE "TotalB" IS NOT NULL;


-- ============================================================================
-- ADMIN SCHEMA - User & Role Management (must come BEFORE STAGING)
-- ============================================================================



CREATE TABLE IF NOT EXISTS admin.users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
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
-- Conflict is detected when core.rowVersion > staging.baseRowVersion at review time.
CREATE TABLE IF NOT EXISTS admin.merge_conflicts (
    id SERIAL PRIMARY KEY,
    merge_request_id INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    table_name TEXT NOT NULL,
    "PlotNumber" TEXT,
    "ProjectID" TEXT,                -- stored as TEXT for cross-type comparison
    "SpeciesCode" TEXT NOT NULL DEFAULT '',   -- '' for env/su conflicts
    "LayerCode"   TEXT NOT NULL DEFAULT '',   -- '' for env/su conflicts
    details JSONB,                  -- {field: {staged: val, core: val}, rowVersion: {staged_base, core_current}}
    resolution TEXT CHECK (resolution IN ('keep_staged', 'keep_core', 'dismiss')),
    resolved_by TEXT,
    resolved_utc TIMESTAMPTZ,
    created_utc TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(merge_request_id, table_name, "PlotNumber", "ProjectID", "SpeciesCode", "LayerCode")
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
    "mergeRequestID" INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    "changeType" TEXT NOT NULL CHECK ("changeType" IN ('I','U','D')),
    -- baseRowVersion: the rowVersion in core at the time the user last synced.
    -- NULL means the row is new (did not exist in core at push time).
    -- Conflict = core.rowVersion > baseRowVersion at review time.
    "baseRowVersion" INTEGER,
    "PlotNumber" TEXT NOT NULL,
    "SpeciesCode" TEXT NOT NULL,
    "LayerCode" TEXT,
    "Cover1" REAL,
    "Height1" TEXT,
    "Cover2" REAL,
    "Height2" TEXT,
    "Cover3" REAL,
    "Height3" TEXT,
    "TotalA" REAL,
    "HeightA" TEXT,
    "Cover4" REAL,
    "Height4" TEXT,
    "Cover5" REAL,
    "Height5" TEXT,
    "Cover5a" REAL,
    "Height5a" TEXT,
    "Cover5b" REAL,
    "Height5b" TEXT,
    "Cover5c" REAL,
    "Height5c" TEXT,
    "TotalB" REAL,
    "HeightB" TEXT,
    "Cover6" REAL,
    "Height6" REAL,
    "Cover7" REAL,
    "Cover8" REAL,
    "Cover9" REAL,
    "Cover10" TEXT,
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
    "Cultural1" TEXT,
    "Cultural2" TEXT,
    "Other1" TEXT,
    "Other2" TEXT,
    "rowVersion" INTEGER DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ DEFAULT now(),
    "modifiedBy" TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_staging_veg_request ON staging.veg("mergeRequestID");
CREATE INDEX IF NOT EXISTS idx_staging_veg_plot ON staging.veg("PlotNumber");

-- staging.env: mirrors core.env with change tracking
CREATE TABLE IF NOT EXISTS staging.env (
    id SERIAL PRIMARY KEY,
    "mergeRequestID" INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    "changeType" TEXT NOT NULL CHECK ("changeType" IN ('I','U','D')),
    -- baseRowVersion: core.rowVersion captured at push time (NULL = new row).
    "baseRowVersion" INTEGER,
    "PlotNumber" TEXT NOT NULL,
    "ProjectID" TEXT NOT NULL,
    "Latitude" NUMERIC,
    "Longitude" NUMERIC,
    "Elevation" INTEGER,
    "SurveyDate" DATE,
    "SurveyorName" TEXT,
    "PlotNotes" TEXT,
    "Zone" TEXT,
    "SubZone" TEXT,
    "SiteSeries" TEXT,
    "rowVersion" INTEGER NOT NULL DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_staging_env_request ON staging.env("mergeRequestID");
CREATE INDEX IF NOT EXISTS idx_staging_env_plot ON staging.env("PlotNumber");
CREATE INDEX IF NOT EXISTS idx_staging_env_project ON staging.env("ProjectID");

-- staging.su: mirrors core.su with change tracking
CREATE TABLE IF NOT EXISTS staging.su (
    id SERIAL PRIMARY KEY,
    "mergeRequestID" INTEGER NOT NULL REFERENCES admin.merge_requests(id) ON DELETE CASCADE,
    "changeType" TEXT NOT NULL CHECK ("changeType" IN ('I','U','D')),
    -- baseRowVersion: core.rowVersion captured at push time (NULL = new row).
    "baseRowVersion" INTEGER,
    "PlotNumber" TEXT NOT NULL,
    "SiteUnit" TEXT,
    "rowVersion" INTEGER NOT NULL DEFAULT 1,
    "lastModifiedUTC" TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
    "modifiedBy" TEXT
);

CREATE INDEX IF NOT EXISTS idx_staging_su_request ON staging.su("mergeRequestID");
CREATE INDEX IF NOT EXISTS idx_staging_su_plot ON staging.su("PlotNumber");


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

-- Seed: species list (10 common BC species)
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

-- Seed: layer codes (5 standard layers)
INSERT INTO lists.layercode ("layerCode", "layerName", "sortOrder") VALUES
    ('T1', 'Tree canopy layer 1', 1),
    ('T2', 'Tree canopy layer 2', 2),
    ('S', 'Shrub layer', 3),
    ('H', 'Herb layer', 4),
    ('M', 'Moss layer', 5)
ON CONFLICT ("layerCode") DO NOTHING;

-- Seed: BEC zones (7 common zones)
INSERT INTO lists.usyszonelist ("zoneCode", "zoneName", province) VALUES
    ('CDF', 'Coastal Douglas-fir', 'BC'),
    ('CWH', 'Coastal Western Hemlock', 'BC'),
    ('MH', 'Mountain Hemlock', 'BC'),
    ('ESSF', 'Engelmann Spruce - Subalpine Fir', 'BC'),
    ('ICH', 'Interior Cedar - Hemlock', 'BC'),
    ('IDF', 'Interior Douglas-fir', 'BC'),
    ('MS', 'Montane Spruce', 'BC')
ON CONFLICT ("zoneCode") DO NOTHING;

-- Seed: BEC subzones (7 examples)
INSERT INTO lists.usyssubzonelist ("zoneCode", "subzoneCode", "subzoneName") VALUES
    ('CWH', 'dm', 'dry maritime'),
    ('CWH', 'vm', 'very dry maritime'),
    ('CWH', 'xm', 'very wet maritime'),
    ('ICH', 'mk', 'moist cool'),
    ('IDF', 'dk', 'dry cool'),
    ('ESSF', 'mk', 'moist cool'),
    ('MH', 'mm', 'moist maritime')
ON CONFLICT ("zoneCode", "subzoneCode") DO NOTHING;

-- Seed: generic list values
INSERT INTO lists.usystableoflists ("listID", "itemCode", "itemName", "itemSort") VALUES
    ('COVER_CLASS', '1', '0-1%', 1),
    ('COVER_CLASS', '2', '1-5%', 2),
    ('COVER_CLASS', '3', '5-25%', 3),
    ('COVER_CLASS', '4', '25-50%', 4),
    ('COVER_CLASS', '5', '50-75%', 5),
    ('COVER_CLASS', '6', '75-100%', 6)
ON CONFLICT ("listID", "itemCode") DO NOTHING;

-- Seed: test users (password: test)
-- Bcrypt hash for password "test" generated with bcrypt::hashpw()
INSERT INTO admin.users (email, full_name, app_role, password_hash, is_active) VALUES
    ('viewer@test.local',  'Test Viewer',       'guest', NULL, TRUE),
    ('field@test.local',   'Test Field User',   'guest', NULL, TRUE),
    ('lead@test.local',    'Test Project Lead', 'guest', NULL, TRUE),
    ('dba@test.local',     'Test DBA',          'admin', '$2a$12$f.Dzj8AKQvFFR1ecdFSK6.t9DQT7EMGNSt8Q81TPJLNQq1FygH3l6', TRUE),
    ('admin@test.local',   'Test Admin',        'admin', '$2a$12$f.Dzj8AKQvFFR1ecdFSK6.t9DQT7EMGNSt8Q81TPJLNQq1FygH3l6', TRUE),
    ('nicolas@boostao.ca', 'Nicolas Gauthier',  'admin', '$2a$12$f.Dzj8AKQvFFR1ecdFSK6.t9DQT7EMGNSt8Q81TPJLNQq1FygH3l6', TRUE),
    ('bruno@boostao.ca',   'Bruno Tremblay',    'admin', '$2a$12$f.Dzj8AKQvFFR1ecdFSK6.t9DQT7EMGNSt8Q81TPJLNQq1FygH3l6', TRUE),
    ('francois@boostao.ca','François Bornais',  'admin', '$2a$12$f.Dzj8AKQvFFR1ecdFSK6.t9DQT7EMGNSt8Q81TPJLNQq1FygH3l6', TRUE)
ON CONFLICT (email) DO NOTHING;

-- Seed: sample project
INSERT INTO core.metadata ("projectID", "projectName", description, organization, "contactEmail", "modifiedBy") VALUES
    ('DEMO_IDF_2023', 'Test Project Alpha', 'Initial test dataset for BECMaster', 'Test Organization', 'test@example.com', 'test_admin')
ON CONFLICT ("projectID") DO NOTHING;

