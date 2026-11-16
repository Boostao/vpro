# Idempotent PostgreSQL BECMaster, Staging & Standards DDL Builders ----------

vpro_pg_col_ddl <- function(spec) {
  q_names <- vpro_quote_ident(spec$name)
  defs <- paste0("  ", q_names, " ", spec$pg_type)
  bool_idx <- which(spec$is_bool)
  if (length(bool_idx) > 0L) {
    defs[bool_idx] <- paste0(defs[bool_idx], " CHECK (", q_names[bool_idx], " IN (-1, 0))")
  }
  defs
}

vpro_pg_master_table_ddl <- function(table, spec, pk_cols = character(), extra = character()) {
  defs <- vpro_pg_col_ddl(spec)
  if (length(pk_cols) > 0L) {
    defs <- c(defs, paste0("  PRIMARY KEY (", paste(vpro_quote_ident(pk_cols), collapse = ", "), ")"))
  }
  if (length(extra) > 0L) {
    defs <- c(defs, paste0("  ", extra))
  }
  paste0(
    "CREATE TABLE IF NOT EXISTS becmaster.",
    vpro_quote_ident(table),
    " (\n",
    paste(defs, collapse = ",\n"),
    "\n);"
  )
}

vpro_pg_staging_table_ddl <- function(table, spec, pk_cols = character(), fk_to_env = FALSE) {
  sub_col <- if (isTRUE(fk_to_env)) {
    "  submission_id UUID NOT NULL"
  } else {
    "  submission_id UUID NOT NULL REFERENCES staging.submissions(submission_id) ON DELETE CASCADE"
  }
  defs <- c(sub_col, vpro_pg_col_ddl(spec))
  if (length(pk_cols) > 0L) {
    defs <- c(
      defs,
      paste0("  PRIMARY KEY (submission_id, ", paste(vpro_quote_ident(pk_cols), collapse = ", "), ")")
    )
  }
  if (isTRUE(fk_to_env)) {
    plot_col <- if (identical(table, "admin")) "Plot" else "PlotNumber"
    defs <- c(
      defs,
      paste0(
        "  FOREIGN KEY (submission_id, ",
        vpro_quote_ident(plot_col),
        ') REFERENCES staging.env(submission_id, "PlotNumber") ON DELETE CASCADE'
      )
    )
  }
  paste0(
    "CREATE TABLE IF NOT EXISTS staging.",
    vpro_quote_ident(table),
    " (\n",
    paste(defs, collapse = ",\n"),
    "\n);"
  )
}

vpro_pg_standards_table_ddl <- function(table, spec) {
  defs <- c("  row_seq BIGSERIAL PRIMARY KEY", vpro_pg_col_ddl(spec))
  paste0(
    "CREATE TABLE IF NOT EXISTS standards.",
    vpro_quote_ident(table),
    " (\n",
    paste(defs, collapse = ",\n"),
    "\n);"
  )
}

vpro_pg_trigger_if_missing_ddl <- function(schema_name, table_name, trigger_name, fn_qualified) {
  paste0(
    "DO $$\nBEGIN\n",
    "  IF NOT EXISTS (\n",
    "    SELECT 1 FROM pg_trigger t\n",
    "    JOIN pg_class c ON c.oid = t.tgrelid\n",
    "    JOIN pg_namespace n ON n.oid = c.relnamespace\n",
    "    WHERE n.nspname = '",
    schema_name,
    "'\n",
    "      AND c.relname = '",
    table_name,
    "'\n",
    "      AND t.tgname = '",
    trigger_name,
    "'\n",
    "  ) THEN\n",
    "    CREATE TRIGGER ",
    vpro_quote_ident(trigger_name),
    "\n",
    "      BEFORE INSERT ON ",
    vpro_quote_ident(schema_name),
    ".",
    vpro_quote_ident(table_name),
    "\n",
    "      FOR EACH ROW EXECUTE FUNCTION ",
    fn_qualified,
    "();\n",
    "  END IF;\n",
    "END $$;"
  )
}

vpro_pg_build_v1_migration_stmts <- function(has_postgis = FALSE, postgis_schema = "public") {
  stmts <- c(
    vpro_pg_master_table_ddl("env", .vpro_pg_vp08_spec_map$Env, "PlotNumber"),
    'CREATE INDEX IF NOT EXISTS idx_becmaster_env_zone ON becmaster.env ("Zone");',
    'CREATE INDEX IF NOT EXISTS idx_becmaster_env_subzone ON becmaster.env ("SubZone");',
    'CREATE INDEX IF NOT EXISTS idx_becmaster_env_projectid ON becmaster.env ("ProjectID");',
    'CREATE INDEX IF NOT EXISTS idx_becmaster_env_coords ON becmaster.env ("Longitude", "Latitude");'
  )

  if (isTRUE(has_postgis)) {
    q_pgis <- vpro_quote_ident(postgis_schema)
    stmts <- c(
      stmts,
      paste0(
        "ALTER TABLE becmaster.env ADD COLUMN IF NOT EXISTS geom ",
        q_pgis,
        ".geometry(Point, 4326) GENERATED ALWAYS AS (\n",
        "  CASE\n",
        '    WHEN "Longitude" IS NOT NULL AND "Latitude" IS NOT NULL\n',
        '         AND "Longitude" >= -180.0 AND "Longitude" <= 180.0\n',
        '         AND "Latitude" >= -90.0 AND "Latitude" <= 90.0\n',
        "    THEN ",
        q_pgis,
        ".ST_SetSRID(",
        q_pgis,
        '.ST_MakePoint("Longitude", "Latitude"), 4326)\n',
        "    ELSE NULL\n",
        "  END\n",
        ") STORED;"
      ),
      "CREATE INDEX IF NOT EXISTS idx_becmaster_env_geom ON becmaster.env USING GIST (geom);"
    )
  }

  audit_master_defs <- c(
    "  audit_seq BIGSERIAL PRIMARY KEY",
    vpro_pg_col_ddl(.vpro_pg_vp08_spec_map$Audit),
    "  merge_tx_id UUID",
    "  prev_hash TEXT NOT NULL",
    "  row_hash TEXT NOT NULL"
  )

  stmts <- c(
    stmts,
    vpro_pg_master_table_ddl(
      "admin",
      .vpro_pg_vp08_spec_map$Admin,
      "Plot",
      'FOREIGN KEY ("Plot") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    vpro_pg_master_table_ddl(
      "veg",
      .vpro_pg_vp08_spec_map$Veg,
      c("PlotNumber", "ID"),
      'FOREIGN KEY ("PlotNumber") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    'CREATE INDEX IF NOT EXISTS idx_becmaster_veg_species ON becmaster.veg ("Species");',
    vpro_pg_master_table_ddl(
      "humus",
      .vpro_pg_vp08_spec_map$Humus,
      c("PlotNumber", "ID"),
      'FOREIGN KEY ("PlotNumber") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    vpro_pg_master_table_ddl(
      "mineral",
      .vpro_pg_vp08_spec_map$Mineral,
      c("PlotNumber", "ID"),
      'FOREIGN KEY ("PlotNumber") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    vpro_pg_master_table_ddl(
      "other",
      .vpro_pg_vp08_spec_map$Other,
      c("PlotNumber", "ID"),
      'FOREIGN KEY ("PlotNumber") REFERENCES becmaster.env("PlotNumber") ON DELETE CASCADE'
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.child_identity (",
      "  child_table TEXT NOT NULL,",
      "  id BIGINT NOT NULL,",
      "  PRIMARY KEY (child_table, id)",
      ");",
      sep = "\n"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.child_identity_watermark (",
      "  child_table TEXT PRIMARY KEY,",
      "  max_id BIGINT NOT NULL",
      ");",
      sep = "\n"
    ),
    vpro_pg_master_table_ddl("metadata", .vpro_pg_vp08_spec_map$Metadata, "ProjectID"),
    paste0("CREATE TABLE IF NOT EXISTS becmaster.audit (\n", paste(audit_master_defs, collapse = ",\n"), "\n);"),
    'CREATE INDEX IF NOT EXISTS idx_becmaster_audit_plot ON becmaster.audit ("PlotNumber");',
    "CREATE INDEX IF NOT EXISTS idx_becmaster_audit_mergetx ON becmaster.audit (merge_tx_id);",
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.merge_ledger (",
      "  merge_tx_id UUID PRIMARY KEY,",
      "  submission_id UUID,",
      "  actor TEXT NOT NULL,",
      "  merged_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  source_sha256 TEXT NOT NULL,",
      "  added_plots INT NOT NULL,",
      "  updated_plots INT NOT NULL,",
      "  summary_json JSONB NOT NULL",
      ");",
      sep = "\n"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.snapshots (",
      "  snapshot_tag TEXT PRIMARY KEY,",
      "  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  created_by TEXT NOT NULL,",
      "  plot_count INT NOT NULL,",
      "  veg_count BIGINT NOT NULL,",
      "  bec_version TEXT NOT NULL,",
      "  taxonomy_version TEXT NOT NULL,",
      "  manifest_sha256 TEXT NOT NULL,",
      "  notes TEXT",
      ");",
      sep = "\n"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.download_log (",
      "  id BIGSERIAL PRIMARY KEY,",
      "  downloaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  actor TEXT NOT NULL,",
      "  role_tier TEXT NOT NULL,",
      "  filter_json JSONB NOT NULL,",
      "  format TEXT NOT NULL,",
      "  plot_count INT NOT NULL",
      ");",
      sep = "\n"
    ),
    paste(
      "CREATE OR REPLACE FUNCTION becmaster.enforce_download_log_insert() RETURNS trigger LANGUAGE plpgsql AS $$",
      "BEGIN",
      "  NEW.downloaded_at := COALESCE(NEW.downloaded_at, now());",
      "  IF NEW.actor IS NULL OR btrim(NEW.actor) = '' THEN",
      "    NEW.actor := current_user;",
      "  END IF;",
      "  RETURN NEW;",
      "END;",
      "$$;",
      sep = "\n"
    ),
    vpro_pg_trigger_if_missing_ddl(
      "becmaster",
      "download_log",
      "trg_becmaster_download_log_insert",
      "becmaster.enforce_download_log_insert"
    )
  )

  stg_audit_defs <- c(
    "  audit_seq BIGSERIAL PRIMARY KEY",
    "  submission_id UUID NOT NULL REFERENCES staging.submissions(submission_id) ON DELETE CASCADE",
    vpro_pg_col_ddl(.vpro_pg_vp08_spec_map$Audit)
  )

  stmts <- c(
    stmts,
    paste(
      "CREATE TABLE IF NOT EXISTS staging.submissions (",
      "  submission_id UUID PRIMARY KEY,",
      "  project_name TEXT NOT NULL,",
      "  project_id TEXT,",
      "  submitted_by TEXT NOT NULL,",
      "  db_role TEXT NOT NULL,",
      "  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'merged')),",
      "  plot_count INT NOT NULL DEFAULT 0,",
      "  veg_row_count INT NOT NULL DEFAULT 0,",
      "  source_db_sha256 TEXT NOT NULL,",
      "  compliance_passed BOOLEAN NOT NULL,",
      "  compliance_report JSONB NOT NULL,",
      "  user_species_manifest JSONB NOT NULL,",
      "  lump_rows JSONB NOT NULL DEFAULT '[]'::jsonb,",
      "  su_rows JSONB NOT NULL DEFAULT '[]'::jsonb,",
      "  submitter_notes TEXT,",
      "  base_snapshot_tag TEXT,",
      "  reviewer_notes TEXT,",
      "  reviewed_by TEXT,",
      "  reviewed_at TIMESTAMPTZ,",
      "  merged_tx_id UUID",
      ");",
      sep = "\n"
    ),
    "CREATE INDEX IF NOT EXISTS idx_staging_submissions_status ON staging.submissions (status, submitted_at DESC);",
    vpro_pg_staging_table_ddl("env", .vpro_pg_vp08_spec_map$Env, "PlotNumber", fk_to_env = FALSE),
    vpro_pg_staging_table_ddl("admin", .vpro_pg_vp08_spec_map$Admin, "Plot", fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("veg", .vpro_pg_vp08_spec_map$Veg, c("PlotNumber", "ID"), fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("humus", .vpro_pg_vp08_spec_map$Humus, c("PlotNumber", "ID"), fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("mineral", .vpro_pg_vp08_spec_map$Mineral, c("PlotNumber", "ID"), fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("other", .vpro_pg_vp08_spec_map$Other, c("PlotNumber", "ID"), fk_to_env = TRUE),
    vpro_pg_staging_table_ddl("metadata", .vpro_pg_vp08_spec_map$Metadata, "ProjectID", fk_to_env = FALSE),
    paste0("CREATE TABLE IF NOT EXISTS staging.audit (\n", paste(stg_audit_defs, collapse = ",\n"), "\n);"),
    "CREATE INDEX IF NOT EXISTS idx_staging_audit_sub ON staging.audit (submission_id);",
    paste(
      "CREATE OR REPLACE FUNCTION staging.enforce_submission_insert() RETURNS trigger LANGUAGE plpgsql AS $$",
      "DECLARE",
      "  is_table_owner BOOLEAN;",
      "BEGIN",
      "  NEW.db_role := current_user;",
      "  NEW.submitted_at := COALESCE(NEW.submitted_at, now());",
      "  SELECT pg_has_role(current_user, c.relowner, 'USAGE')",
      "  INTO is_table_owner",
      "  FROM pg_class c",
      "  JOIN pg_namespace n ON n.oid = c.relnamespace",
      "  WHERE n.nspname = 'staging' AND c.relname = 'submissions';",
      "",
      "  IF NOT COALESCE(is_table_owner, FALSE) THEN",
      "    IF NEW.status <> 'pending' THEN",
      "      RAISE EXCEPTION 'contributor submissions must start with status = pending' USING ERRCODE = '42501';",
      "    END IF;",
      "    IF NEW.compliance_passed IS NOT TRUE THEN",
      "      RAISE EXCEPTION 'contributor submissions require compliance_passed = TRUE' USING ERRCODE = '42501';",
      "    END IF;",
      "    NEW.reviewed_by := NULL;",
      "    NEW.reviewed_at := NULL;",
      "    NEW.merged_tx_id := NULL;",
      "  END IF;",
      "  RETURN NEW;",
      "END;",
      "$$;",
      sep = "\n"
    ),
    vpro_pg_trigger_if_missing_ddl(
      "staging",
      "submissions",
      "trg_staging_submission_insert",
      "staging.enforce_submission_insert"
    ),
    paste(
      "CREATE OR REPLACE FUNCTION staging.enforce_staging_child_insert() RETURNS trigger LANGUAGE plpgsql AS $$",
      "DECLARE",
      "  is_table_owner BOOLEAN;",
      "  sub_ok BOOLEAN;",
      "BEGIN",
      "  SELECT pg_has_role(current_user, c.relowner, 'USAGE')",
      "  INTO is_table_owner",
      "  FROM pg_class c",
      "  JOIN pg_namespace n ON n.oid = c.relnamespace",
      "  WHERE n.nspname = 'staging' AND c.relname = 'submissions';",
      "",
      "  IF NOT COALESCE(is_table_owner, FALSE) THEN",
      "    SELECT EXISTS (",
      "      SELECT 1 FROM staging.submissions s",
      "      WHERE s.submission_id = NEW.submission_id",
      "        AND s.status = 'pending'",
      "        AND s.db_role = current_user",
      "    ) INTO sub_ok;",
      "    IF NOT COALESCE(sub_ok, FALSE) THEN",
      "      RAISE EXCEPTION 'contributor child row insert requires owned pending submission_id' USING ERRCODE = '42501';",
      "    END IF;",
      "  END IF;",
      "  RETURN NEW;",
      "END;",
      "$$;",
      sep = "\n"
    )
  )

  for (child_tbl in c("env", "admin", "veg", "humus", "mineral", "other", "metadata", "audit")) {
    stmts <- c(
      stmts,
      vpro_pg_trigger_if_missing_ddl(
        "staging",
        child_tbl,
        paste0("trg_staging_", child_tbl, "_insert"),
        "staging.enforce_staging_child_insert"
      )
    )
  }

  stmts <- c(
    stmts,
    paste(
      "CREATE TABLE IF NOT EXISTS standards.library_releases (",
      "  release_id TEXT PRIMARY KEY,",
      "  published_at TIMESTAMPTZ NOT NULL DEFAULT now(),",
      "  published_by TEXT NOT NULL,",
      "  bec_version TEXT NOT NULL,",
      "  taxonomy_version TEXT NOT NULL,",
      "  vlists_sha256 TEXT NOT NULL,",
      "  bec_db_sha256 TEXT,",
      "  vmetadata_sha256 TEXT,",
      "  notes TEXT,",
      "  is_current BOOLEAN NOT NULL DEFAULT FALSE,",
      "  vlists_gzip BYTEA",
      ");",
      sep = "\n"
    ),
    vpro_pg_standards_table_ddl("usys_all_specs", .vpro_pg_standards_spec_map$usys_all_specs),
    'CREATE INDEX IF NOT EXISTS idx_standards_specs_code ON standards.usys_all_specs ("Code");',
    'CREATE INDEX IF NOT EXISTS idx_standards_specs_oldcode ON standards.usys_all_specs ("OldCode");',
    vpro_pg_standards_table_ddl("usys_table_of_lists", .vpro_pg_standards_spec_map$usys_table_of_lists),
    'CREATE INDEX IF NOT EXISTS idx_standards_lists_name ON standards.usys_table_of_lists ("ListName");',
    vpro_pg_standards_table_ddl("bec_site_series", .vpro_pg_standards_spec_map$bec_site_series),
    'CREATE INDEX IF NOT EXISTS idx_standards_bec_zone ON standards.bec_site_series ("Zone", "SubZone");',
    vpro_pg_standards_table_ddl("master_site_unit_list", .vpro_pg_standards_spec_map$master_site_unit_list),
    vpro_pg_standards_table_ddl("usys_zone_list", .vpro_pg_standards_spec_map$usys_zone_list),
    vpro_pg_standards_table_ddl("project_metadata", .vpro_pg_standards_spec_map$project_metadata)
  )

  stmts
}

# Public Exported API ----------------------------------------------------------
