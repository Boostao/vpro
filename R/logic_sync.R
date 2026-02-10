# Sync engine helpers (local DuckDB <-> cloud PostgreSQL via DuckDB ATTACH).

sync_table_mappings <- function() {
  list(
    sample_env = list(
      local_table = "Sample_Env",
      cloud_table = "master.core.sample_env",
      staging_table = "master.staging.sample_env",
      key_cols = c("PlotNumber", "ProjectID"),
      local_cols = c("PlotNumber", "ProjectID", "Latitude", "Longitude", "Elevation", "Date", "SiteSurveyor", "SiteNotes"),
      cloud_cols = c("plot_number", "project_id", "latitude", "longitude", "elevation_m", "survey_date", "surveyor_name", "plot_notes")
    ),
    sample_su = list(
      local_table = "Sample_SU",
      cloud_table = "master.core.sample_su",
      staging_table = "master.staging.sample_su",
      key_cols = c("PlotNumber"),
      local_cols = c("PlotNumber", "SiteUnit"),
      cloud_cols = c("plot_number", "su_number")
    ),
    sample_veg = list(
      local_table = "Sample_Veg",
      cloud_table = "master.core.sample_veg",
      staging_table = "master.staging.sample_veg",
      key_cols = c("PlotNumber", "Species", "Layer"),
      local_cols = c("PlotNumber", "Species", "Layer", "Cover"),
      cloud_cols = c("plot_number", "species_code", "layer_code", "cover_percent")
    )
  )
}

sync_resolve_schema <- function(con) {
  attached <- tryCatch({
    DBI::dbGetQuery(con, "SELECT database_name FROM duckdb_databases()")$database_name
  }, error = function(e) character(0))
  if ("user" %in% attached) "user" else NULL
}

sync_ensure_state_tables <- function(con) {
  schema <- sync_resolve_schema(con)
  prefix <- if (is.null(schema)) "" else paste0(schema, ".")
  if (!is.null(schema)) {
    DBI::dbExecute(con, sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
  }
  DBI::dbExecute(con, sprintf(
    "CREATE TABLE IF NOT EXISTS %ssync_state (\n      scope TEXT NOT NULL,\n      value TEXT,\n      updated_utc TIMESTAMPTZ DEFAULT now(),\n      PRIMARY KEY (scope)\n    )",
    prefix
  ))
  DBI::dbExecute(con, sprintf(
    "CREATE TABLE IF NOT EXISTS %ssync_conflicts (\n      id INTEGER PRIMARY KEY,\n      table_name TEXT NOT NULL,\n      plot_number TEXT,\n      project_id TEXT,\n      local_seen_utc TIMESTAMPTZ,\n      cloud_seen_utc TIMESTAMPTZ,\n      details TEXT,\n      detected_utc TIMESTAMPTZ DEFAULT now()\n    )",
    prefix
  ))
}

sync_get_state <- function(con, scope) {
  schema <- sync_resolve_schema(con)
  table_id <- if (is.null(schema)) "sync_state" else DBI::Id(schema = schema, table = "sync_state")
  if (!DBI::dbExistsTable(con, table_id)) return(NULL)
  prefix <- if (is.null(schema)) "" else paste0(schema, ".")
  result <- DBI::dbGetQuery(
    con,
    sprintf("SELECT value FROM %ssync_state WHERE scope = ?", prefix),
    list(scope)
  )
  if (nrow(result) == 0) return(NULL)
  result$value[1]
}

sync_set_state <- function(con, scope, value) {
  schema <- sync_resolve_schema(con)
  prefix <- if (is.null(schema)) "" else paste0(schema, ".")
  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO %ssync_state (scope, value, updated_utc)\n       VALUES (?, ?, now())\n       ON CONFLICT (scope) DO UPDATE SET value = EXCLUDED.value, updated_utc = EXCLUDED.updated_utc",
      prefix
    ),
    list(scope, value)
  )
}

sync_cloud_connected <- function(con) {
  tryCatch({
    DBI::dbGetQuery(con, "SELECT 1 FROM master.information_schema.tables LIMIT 1")
    TRUE
  }, error = function(e) FALSE)
}

sync_require_cloud <- function(con, environment = NULL, allow_attach = TRUE) {
  if (sync_cloud_connected(con)) return(invisible(TRUE))
  if (!allow_attach) stop("Cloud database is not attached.")
  attach_cloud_db(con, environment = environment, read_only = FALSE, alias = "master")
  if (!sync_cloud_connected(con)) stop("Cloud database attach failed.")
  invisible(TRUE)
}

sync_pull <- function(con,
                      project_id = NULL,
                      tables = c("sample_env", "sample_su"),
                      environment = NULL,
                      allow_attach = TRUE) {
  sync_require_cloud(con, environment = environment, allow_attach = allow_attach)
  sync_ensure_state_tables(con)

  mappings <- sync_table_mappings()
  results <- list()

  for (table_key in tables) {
    mapping <- mappings[[table_key]]
    if (is.null(mapping)) {
      results[[table_key]] <- list(pulled = 0L, skipped = TRUE, reason = "unsupported")
      next
    }

    if (identical(table_key, "sample_veg")) {
      results[[table_key]] <- list(pulled = 0L, skipped = TRUE, reason = "pull_not_supported")
      next
    }

    if (!DBI::dbExistsTable(con, mapping$local_table)) {
      results[[table_key]] <- list(pulled = 0L, skipped = TRUE)
      next
    }

    scope <- paste("last_pull", table_key, project_id %||% "all", sep = ":")
    last_pull <- sync_get_state(con, scope)

    select_cols <- sprintf(
      "SELECT %s FROM %s",
      paste(sprintf("%s AS %s", mapping$cloud_cols, mapping$local_cols), collapse = ", "),
      mapping$cloud_table
    )

    filters <- character(0)
    params <- list()
    if (!is.null(project_id) && nzchar(project_id) && "project_id" %in% mapping$cloud_cols) {
      filters <- c(filters, "project_id = ?")
      params <- c(params, list(project_id))
    }
    if (!is.null(last_pull) && nzchar(last_pull) && DBI::dbExistsTable(con, "master.core.sample_env")) {
      filters <- c(filters, "last_modified_utc > ?")
      params <- c(params, list(last_pull))
    }

    where_clause <- if (length(filters) > 0) paste("WHERE", paste(filters, collapse = " AND ")) else ""
    sql <- paste(select_cols, where_clause)

    temp_name <- paste0("tmp_sync_pull_", table_key)
    DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", temp_name))
    DBI::dbExecute(con, sprintf("CREATE TEMP TABLE %s AS %s", temp_name, sql), params)

    pulled <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", temp_name))$n[1]
    if (pulled > 0) {
      key_col <- mapping$key_cols[1]
      DBI::dbExecute(
        con,
        sprintf("DELETE FROM %s WHERE %s IN (SELECT %s FROM %s)", mapping$local_table, key_col, key_col, temp_name)
      )
      DBI::dbExecute(
        con,
        sprintf("INSERT INTO %s (%s) SELECT %s FROM %s",
          mapping$local_table,
          paste(mapping$local_cols, collapse = ", "),
          paste(mapping$local_cols, collapse = ", "),
          temp_name
        )
      )
    }

    DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", temp_name))
    sync_set_state(con, scope, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
    results[[table_key]] <- list(pulled = pulled, skipped = FALSE)
  }

  results
}

sync_create_merge_request <- function(con, project_id, submitter) {
  result <- DBI::dbGetQuery(
    con,
    paste0(
      "INSERT INTO master.admin.merge_requests (project_id, submitter_user_id)",
      " VALUES (?, ?) RETURNING id"
    ),
    list(project_id, submitter)
  )
  if (nrow(result) == 0) stop("Failed to create merge request.")
  result$id[1]
}

sync_push <- function(con,
                      project_id = NULL,
                      tables = c("sample_env", "sample_su", "sample_veg"),
                      environment = NULL,
                      allow_attach = TRUE,
                      submitter = Sys.getenv("USER", "unknown")) {
  sync_require_cloud(con, environment = environment, allow_attach = allow_attach)
  sync_ensure_state_tables(con)

  if (is.null(project_id) || !nzchar(project_id)) {
    if (DBI::dbExistsTable(con, "Sample_Env")) {
      projects <- DBI::dbGetQuery(con, "SELECT DISTINCT ProjectID FROM Sample_Env")$ProjectID
      projects <- projects[!is.na(projects) & nzchar(projects)]
      if (length(projects) == 1) {
        project_id <- projects[1]
      } else {
        stop("Project ID is required for sync_push when multiple projects exist.")
      }
    } else {
      stop("Project ID is required for sync_push.")
    }
  }

  merge_request_id <- sync_create_merge_request(con, project_id, submitter)
  results <- list(merge_request_id = merge_request_id)

  if ("sample_env" %in% tables && DBI::dbExistsTable(con, "Sample_Env")) {
    DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_env_push")
    DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_env_delta")

    DBI::dbExecute(
      con,
      "CREATE TEMP TABLE tmp_env_push AS\n       SELECT\n         PlotNumber AS plot_number,\n         ProjectID AS project_id,\n         Latitude AS latitude,\n         Longitude AS longitude,\n         Elevation AS elevation_m,\n         Date AS survey_date,\n         SiteSurveyor AS surveyor_name,\n         SiteNotes AS plot_notes\n       FROM Sample_Env\n       WHERE ProjectID = ?",
      list(project_id)
    )

    DBI::dbExecute(
      con,
      "CREATE TEMP TABLE tmp_env_delta AS\n       SELECT t.*\n       FROM tmp_env_push t\n       LEFT JOIN master.core.sample_env c\n         ON c.plot_number = t.plot_number AND c.project_id = t.project_id\n       WHERE c.plot_number IS NULL\n          OR c.latitude IS DISTINCT FROM t.latitude\n          OR c.longitude IS DISTINCT FROM t.longitude\n          OR c.elevation_m IS DISTINCT FROM t.elevation_m\n          OR c.survey_date IS DISTINCT FROM t.survey_date\n          OR c.surveyor_name IS DISTINCT FROM t.surveyor_name\n          OR c.plot_notes IS DISTINCT FROM t.plot_notes"
    )

    env_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tmp_env_delta")$n[1]
    if (env_count > 0) {
      DBI::dbExecute(
        con,
        "INSERT INTO master.staging.sample_env\n         (plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes, merge_request_id, modified_by)\n         SELECT plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes, ?, ?\n         FROM tmp_env_delta",
        list(merge_request_id, submitter)
      )
    }

    DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_env_push")
    DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_env_delta")
    results$sample_env <- env_count
  }

  if ("sample_su" %in% tables && DBI::dbExistsTable(con, "Sample_SU")) {
    if (!DBI::dbExistsTable(con, "Sample_Env")) {
      results$sample_su <- 0L
    } else {
      DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_su_push")
      DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_su_delta")

      DBI::dbExecute(
        con,
        "CREATE TEMP TABLE tmp_su_push AS\n         SELECT\n           su.PlotNumber AS plot_number,\n           env.ProjectID AS project_id,\n           su.SiteUnit AS su_number,\n           env.Zone AS bec_zone,\n           env.SubZone AS bec_subzone,\n           env.SiteSeries AS site_series\n         FROM Sample_SU su\n         LEFT JOIN Sample_Env env ON env.PlotNumber = su.PlotNumber\n         WHERE env.ProjectID = ?",
        list(project_id)
      )

      DBI::dbExecute(
        con,
        "CREATE TEMP TABLE tmp_su_delta AS\n         SELECT t.*\n         FROM tmp_su_push t\n         LEFT JOIN master.core.sample_su c\n           ON c.plot_number = t.plot_number AND c.project_id = t.project_id\n         WHERE c.plot_number IS NULL\n            OR c.su_number IS DISTINCT FROM t.su_number\n            OR c.bec_zone IS DISTINCT FROM t.bec_zone\n            OR c.bec_subzone IS DISTINCT FROM t.bec_subzone\n            OR c.site_series IS DISTINCT FROM t.site_series"
      )

      su_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tmp_su_delta")$n[1]
      if (su_count > 0) {
        DBI::dbExecute(
          con,
          "INSERT INTO master.staging.sample_su\n           (plot_number, project_id, su_number, bec_zone, bec_subzone, site_series, merge_request_id, modified_by)\n           SELECT plot_number, project_id, su_number, bec_zone, bec_subzone, site_series, ?, ?\n           FROM tmp_su_delta",
          list(merge_request_id, submitter)
        )
      }

      DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_su_push")
      DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_su_delta")
      results$sample_su <- su_count
    }
  }

  if ("sample_veg" %in% tables && DBI::dbExistsTable(con, "Sample_Veg")) {
    if (!DBI::dbExistsTable(con, "Sample_Env") || !DBI::dbExistsTable(con, "Sample_Veg")) {
      results$sample_veg <- 0L
    } else {
      DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_veg_push")

      DBI::dbExecute(
        con,
        "CREATE TEMP TABLE tmp_veg_push AS\n         SELECT\n           v.PlotNumber AS plot_number,\n           env.ProjectID AS project_id,\n           TRIM(v.Species) AS species_code,\n           v.Layer AS layer_code,\n           v.Cover1 AS cover1,\n           v.Height1 AS height1,\n           v.Cover2 AS cover2,\n           v.Height2 AS height2,\n           v.Cover3 AS cover3,\n           v.Height3 AS height3,\n           v.TotalA AS totala,\n           v.HeightA AS heighta,\n           v.Cover4 AS cover4,\n           v.Height4 AS height4,\n           v.Cover5 AS cover5,\n           v.Height5 AS height5,\n           v.Cover5a AS cover5a,\n           v.Height5a AS height5a,\n           v.Cover5b AS cover5b,\n           v.Height5b AS height5b,\n           v.Cover5c AS cover5c,\n           v.Height5c AS height5c,\n           v.TotalB AS totalb,\n           v.HeightB AS heightb,\n           v.Cover6 AS cover6,\n           v.Height6 AS height6,\n           v.Cover7 AS cover7,\n           v.Cover8 AS cover8,\n           v.Cover9 AS cover9,\n           v.Cover10 AS cover10,\n           v.Collected AS collected,\n           v.Flag AS flag,\n           v.ID AS veg_id,\n           v.LL AS ll,\n           v.AF AS af,\n           v.DC AS dc,\n           v.UT AS ut,\n           v.VI AS vi,\n           v.PV AS pv,\n           v.PG AS pg,\n           v.FFA AS ffa,\n           v.Cultural1 AS cultural1,\n           v.Cultural2 AS cultural2,\n           v.Other1 AS other1,\n           v.Other2 AS other2\n         FROM Sample_Veg v\n         LEFT JOIN Sample_Env env ON env.PlotNumber = v.PlotNumber\n         WHERE env.ProjectID = ?",
        list(project_id)
      )

      veg_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM tmp_veg_push")$n[1]
      if (veg_count > 0) {
        DBI::dbExecute(
          con,
          "INSERT INTO master.staging.sample_veg\n           (plot_number, project_id, species_code, layer_code,\n            cover1, height1, cover2, height2, cover3, height3, totala, heighta, cover4, height4, cover5, height5, cover5a, height5a, cover5b, height5b, cover5c, height5c, totalb, heightb, cover6, height6, cover7, cover8, cover9, cover10, collected, flag, veg_id, ll, af, dc, ut, vi, pv, pg, ffa, cultural1, cultural2, other1, other2, merge_request_id, modified_by)\n           SELECT plot_number, project_id, species_code, layer_code,\n            cover1, height1, cover2, height2, cover3, height3, totala, heighta, cover4, height4, cover5, height5, cover5a, height5a, cover5b, height5b, cover5c, height5c, totalb, heightb, cover6, height6, cover7, cover8, cover9, cover10, collected, flag, veg_id, ll, af, dc, ut, vi, pv, pg, ffa, cultural1, cultural2, other1, other2, ?, ?\n           FROM tmp_veg_push",
          list(merge_request_id, submitter)
        )
      }

      DBI::dbExecute(con, "DROP TABLE IF EXISTS tmp_veg_push")
      results$sample_veg <- veg_count
    }
  }

  env_total <- results$sample_env %||% 0L
  veg_total <- results$sample_veg %||% 0L
  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_requests SET env_record_count = ?, veg_record_count = ? WHERE id = ?",
    list(env_total, veg_total, merge_request_id)
  )

  for (table_key in tables) {
    scope <- paste("last_push", table_key, project_id, sep = ":")
    sync_set_state(con, scope, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  }

  results
}

export_parquet_snapshot <- function(con,
                                   out_dir,
                                   tables = c("Sample_Env", "Sample_SU", "Sample_Veg"),
                                   views = c("vw_USysAllVeg"),
                                   overwrite = FALSE) {
  if (is.null(out_dir) || !nzchar(trimws(out_dir))) {
    stop("Output directory is required for parquet snapshot.")
  }

  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  export_items <- c(tables, views)
  files <- character(0)
  errors <- character(0)

  for (item in export_items) {
    if (!DBI::dbExistsTable(con, item)) {
      errors <- c(errors, paste("Missing table/view:", item))
      next
    }
    file_name <- paste0(gsub("[^A-Za-z0-9_]", "_", item), ".parquet")
    file_path <- file.path(out_dir, file_name)
    if (file.exists(file_path) && !isTRUE(overwrite)) {
      errors <- c(errors, paste("File exists:", file_name))
      next
    }
    sql <- sprintf("COPY (SELECT * FROM %s) TO '%s' (FORMAT PARQUET)", item, gsub("'", "''", file_path))
    tryCatch({
      DBI::dbExecute(con, sql)
      files <- c(files, file_path)
    }, error = function(e) {
      errors <<- c(errors, paste("Failed export", item, ":", e$message))
    })
  }

  manifest_path <- file.path(out_dir, "parquet_snapshot_manifest.csv")
  manifest_df <- data.frame(file = files, stringsAsFactors = FALSE)
  utils::write.csv(manifest_df, manifest_path, row.names = FALSE)

  list(files = files, errors = errors, manifest = manifest_path)
}

merge_request_compliance_ok <- function(con, merge_request_id) {
  compliance <- DBI::dbGetQuery(
    con,
    "SELECT compliance_passed FROM master.admin.merge_requests WHERE id = ?",
    list(merge_request_id)
  )
  if (nrow(compliance) == 0) return(FALSE)

  value <- compliance$compliance_passed[1]
  if (isTRUE(value)) return(TRUE)
  if (is.numeric(value)) return(!is.na(value) && value == 1)
  if (is.character(value)) return(tolower(value) %in% c("true", "t", "1"))
  FALSE
}

staging_compliance_checks <- function(con, merge_request_id, project_id = NULL) {
  if (is.null(merge_request_id)) return(NULL)

  DBI::dbExecute(con, "DROP TABLE IF EXISTS temp.Sample_Env")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS temp.Sample_Veg")

  DBI::dbExecute(
    con,
    "CREATE TEMP TABLE Sample_Env AS
     SELECT
       plot_number AS plotnumber,
       project_id AS projectid,
       latitude AS latitude,
       longitude AS longitude,
       elevation_m AS elevation
     FROM master.staging.sample_env
     WHERE merge_request_id = ?",
    list(merge_request_id)
  )

  DBI::dbExecute(
    con,
    "CREATE TEMP TABLE Sample_Veg AS
     SELECT
       plot_number AS plotnumber,
       project_id AS projectid,
       species_code AS species,
       layer_code AS layer
     FROM master.staging.sample_veg
     WHERE merge_request_id = ?",
    list(merge_request_id)
  )

  result <- run_compliance_checks(con, project_id)

  DBI::dbExecute(con, "DROP TABLE IF EXISTS temp.Sample_Env")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS temp.Sample_Veg")

  result
}

merge_apply_request <- function(con, merge_request_id, reviewer, review_notes = "") {
  DBI::dbExecute(
    con,
    "INSERT INTO master.core.sample_env
     (plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes, modified_by)
     SELECT plot_number, project_id, latitude, longitude, elevation_m, survey_date, surveyor_name, plot_notes, modified_by
     FROM master.staging.sample_env WHERE merge_request_id = ?
     ON CONFLICT (plot_number) DO UPDATE SET
       project_id = EXCLUDED.project_id,
       latitude = EXCLUDED.latitude,
       longitude = EXCLUDED.longitude,
       elevation_m = EXCLUDED.elevation_m,
       survey_date = EXCLUDED.survey_date,
       surveyor_name = EXCLUDED.surveyor_name,
       plot_notes = EXCLUDED.plot_notes,
       modified_by = EXCLUDED.modified_by,
       last_modified_utc = now(),
       row_version = coalesce(row_version, 0) + 1",
    list(merge_request_id)
  )

  DBI::dbExecute(
    con,
    "INSERT INTO master.core.sample_su
     (plot_number, project_id, su_number, bec_zone, bec_subzone, site_series, modified_by)
     SELECT plot_number, project_id, su_number, bec_zone, bec_subzone, site_series, modified_by
     FROM master.staging.sample_su WHERE merge_request_id = ?
     ON CONFLICT (plot_number) DO UPDATE SET
       project_id = EXCLUDED.project_id,
       su_number = EXCLUDED.su_number,
       bec_zone = EXCLUDED.bec_zone,
       bec_subzone = EXCLUDED.bec_subzone,
       site_series = EXCLUDED.site_series,
       modified_by = EXCLUDED.modified_by,
       last_modified_utc = now(),
       row_version = coalesce(row_version, 0) + 1",
    list(merge_request_id)
  )

  DBI::dbExecute(
    con,
    "INSERT INTO master.core.sample_veg
     (plot_number, species_code, layer_code, cover1, height1, cover2, height2, cover3, height3, totala, heighta,
      cover4, height4, cover5, height5, cover5a, height5a, cover5b, height5b, cover5c, height5c, totalb, heightb,
      cover6, height6, cover7, cover8, cover9, cover10, collected, flag, veg_id, ll, af, dc, ut, vi, pv, pg, ffa,
      cultural1, cultural2, other1, other2, project_id, modified_by)
     SELECT plot_number, species_code, layer_code, cover1, height1, cover2, height2, cover3, height3, totala, heighta,
      cover4, height4, cover5, height5, cover5a, height5a, cover5b, height5b, cover5c, height5c, totalb, heightb,
      cover6, height6, cover7, cover8, cover9, cover10, collected, flag, veg_id, ll, af, dc, ut, vi, pv, pg, ffa,
      cultural1, cultural2, other1, other2, project_id, modified_by
     FROM master.staging.sample_veg WHERE merge_request_id = ?
     ON CONFLICT (plot_number, species_code, layer_code, project_id) DO UPDATE SET
       cover1 = EXCLUDED.cover1,
       height1 = EXCLUDED.height1,
       cover2 = EXCLUDED.cover2,
       height2 = EXCLUDED.height2,
       cover3 = EXCLUDED.cover3,
       height3 = EXCLUDED.height3,
       totala = EXCLUDED.totala,
       heighta = EXCLUDED.heighta,
       cover4 = EXCLUDED.cover4,
       height4 = EXCLUDED.height4,
       cover5 = EXCLUDED.cover5,
       height5 = EXCLUDED.height5,
       cover5a = EXCLUDED.cover5a,
       height5a = EXCLUDED.height5a,
       cover5b = EXCLUDED.cover5b,
       height5b = EXCLUDED.height5b,
       cover5c = EXCLUDED.cover5c,
       height5c = EXCLUDED.height5c,
       totalb = EXCLUDED.totalb,
       heightb = EXCLUDED.heightb,
       cover6 = EXCLUDED.cover6,
       height6 = EXCLUDED.height6,
       cover7 = EXCLUDED.cover7,
       cover8 = EXCLUDED.cover8,
       cover9 = EXCLUDED.cover9,
       cover10 = EXCLUDED.cover10,
       collected = EXCLUDED.collected,
       flag = EXCLUDED.flag,
       veg_id = EXCLUDED.veg_id,
       ll = EXCLUDED.ll,
       af = EXCLUDED.af,
       dc = EXCLUDED.dc,
       ut = EXCLUDED.ut,
       vi = EXCLUDED.vi,
       pv = EXCLUDED.pv,
       pg = EXCLUDED.pg,
       ffa = EXCLUDED.ffa,
       cultural1 = EXCLUDED.cultural1,
       cultural2 = EXCLUDED.cultural2,
       other1 = EXCLUDED.other1,
       other2 = EXCLUDED.other2,
       modified_by = EXCLUDED.modified_by,
       last_modified_utc = now(),
       row_version = coalesce(row_version, 0) + 1",
    list(merge_request_id)
  )

  DBI::dbExecute(con, "DELETE FROM master.staging.sample_env WHERE merge_request_id = ?", list(merge_request_id))
  DBI::dbExecute(con, "DELETE FROM master.staging.sample_su WHERE merge_request_id = ?", list(merge_request_id))
  DBI::dbExecute(con, "DELETE FROM master.staging.sample_veg WHERE merge_request_id = ?", list(merge_request_id))

  DBI::dbExecute(
    con,
    "UPDATE master.admin.merge_requests
     SET status = 'merged', reviewer_user_id = ?, review_notes = ?, reviewed_utc = now()
     WHERE id = ?",
    list(reviewer, review_notes, merge_request_id)
  )
}

merge_approve_request <- function(con, merge_request_id, reviewer, review_notes = "") {
  if (!merge_request_compliance_ok(con, merge_request_id)) {
    stop(sprintf("Merge blocked: compliance failed for request %s", merge_request_id))
  }
  merge_apply_request(con, merge_request_id, reviewer, review_notes)
}
