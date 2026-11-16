# PostgreSQL BECMaster Schema Bootstrap, Status Inspection & Role Grants -----

#' Inspect PostgreSQL `BECMaster` server health, RBAC privileges, and counts
#'
#' Probes round-trip latency, PostgreSQL and PostGIS versions, `becmaster` /
#' `staging` / `standards` schema bootstrap status, table-level RBAC
#' capabilities, master plot and vegetation row counts, snapshot tags, active
#' 2026 standards release metadata, and pending contributor submissions.
#'
#' @param pg An active `vpro_pg_conn` connection object.
#' @return An S3 object of class `vpro_pg_status` with `print()` and
#'   `as_tibble()` methods.
#' @export
vpro_master_status <- function(pg) {
  vpro_assert_pg_conn(pg)
  .vpro_register_pg_s3()

  t0 <- proc.time()[["elapsed"]]
  ver_df <- vpro_pg_query(pg, "SHOW server_version", action = "Probe PostgreSQL version")
  elapsed_ms <- max(1L, as.integer(round((proc.time()[["elapsed"]] - t0) * 1000)))
  server_version <- if (nrow(ver_df) >= 1L && ncol(ver_df) >= 1L) {
    trimws(as.character(ver_df[[1L]][[1L]]))
  } else {
    NA_character_
  }

  ext_df <- tryCatch(
    vpro_pg_query(
      pg,
      "SELECT extversion FROM pg_extension WHERE extname = 'postgis' LIMIT 1",
      action = "Inspect PostGIS extension"
    ),
    error = function(e) data.frame()
  )
  postgis_version <- if (nrow(ext_df) >= 1L && !is.na(ext_df[[1L]][[1L]]) && nzchar(ext_df[[1L]][[1L]])) {
    as.character(ext_df[[1L]][[1L]])
  } else {
    NA_character_
  }

  can_bootstrap_schema <- tryCatch(
    {
      b_df <- vpro_pg_query(
        pg,
        "SELECT has_database_privilege(current_user, current_database(), 'CREATE') AS ok",
        action = "Check database CREATE privilege"
      )
      nrow(b_df) >= 1L && isTRUE(as.logical(b_df$ok[[1L]]))
    },
    error = function(e) FALSE
  )

  sch_df <- vpro_pg_query(
    pg,
    "SELECT COUNT(*) AS n FROM information_schema.schemata WHERE schema_name IN ('becmaster', 'staging', 'standards')",
    action = "Inspect VPro PostgreSQL schemas"
  )
  schema_count <- if (nrow(sch_df) >= 1L) as.integer(sch_df$n[[1L]]) else 0L

  has_env_table <- FALSE
  if (schema_count == 3L) {
    env_tbl_df <- tryCatch(
      vpro_pg_query(
        pg,
        paste(
          "SELECT EXISTS (",
          "  SELECT 1 FROM pg_class c",
          "  JOIN pg_namespace n ON n.oid = c.relnamespace",
          "  WHERE n.nspname = 'becmaster' AND c.relname = 'env'",
          ") AS ok"
        ),
        action = "Check becmaster.env existence"
      ),
      error = function(e) data.frame(ok = FALSE)
    )
    has_env_table <- nrow(env_tbl_df) >= 1L && isTRUE(as.logical(env_tbl_df$ok[[1L]]))
  }
  schemas_bootstrapped <- (schema_count == 3L) && has_env_table

  can_read_master <- FALSE
  can_submit_staging <- FALSE
  can_merge_master <- FALSE
  can_read_staging <- FALSE

  if (schemas_bootstrapped) {
    priv_sql <- paste(
      "SELECT",
      "  CASE WHEN has_schema_privilege(current_user, 'becmaster', 'USAGE')",
      "            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'becmaster' AND c.relname = 'env')",
      "       THEN has_table_privilege(current_user, 'becmaster.env', 'SELECT')",
      "       ELSE FALSE END AS can_read_master,",
      "  CASE WHEN has_schema_privilege(current_user, 'staging', 'USAGE')",
      "            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'staging' AND c.relname = 'submissions')",
      "       THEN has_table_privilege(current_user, 'staging.submissions', 'INSERT')",
      "       ELSE FALSE END AS can_submit_staging,",
      "  CASE WHEN has_schema_privilege(current_user, 'becmaster', 'USAGE')",
      "            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'becmaster' AND c.relname = 'env')",
      "       THEN (has_table_privilege(current_user, 'becmaster.env', 'INSERT') AND has_table_privilege(current_user, 'becmaster.env', 'UPDATE'))",
      "       ELSE FALSE END AS can_merge_master,",
      "  CASE WHEN has_schema_privilege(current_user, 'staging', 'USAGE')",
      "            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'staging' AND c.relname = 'submissions')",
      "       THEN has_table_privilege(current_user, 'staging.submissions', 'SELECT')",
      "       ELSE FALSE END AS can_read_staging"
    )
    priv_df <- tryCatch(
      vpro_pg_query(pg, priv_sql, action = "Check PostgreSQL table privileges"),
      error = function(e) data.frame()
    )
    if (nrow(priv_df) >= 1L) {
      can_read_master <- isTRUE(as.logical(priv_df$can_read_master[[1L]]))
      can_submit_staging <- isTRUE(as.logical(priv_df$can_submit_staging[[1L]]))
      can_merge_master <- isTRUE(as.logical(priv_df$can_merge_master[[1L]]))
      can_read_staging <- isTRUE(as.logical(priv_df$can_read_staging[[1L]]))
    }
    if (can_merge_master) {
      can_bootstrap_schema <- TRUE
    }
  }

  becmaster_plots <- 0L
  becmaster_veg <- 0L
  snapshot_count <- 0L
  latest_snapshot_tag <- NA_character_
  standards_release <- NA_character_
  bec_version <- NA_character_
  taxonomy_version <- NA_character_
  vlists_sha256 <- NA_character_
  pending_submissions <- 0L

  if (schemas_bootstrapped && can_read_master) {
    becmaster_plots <- tryCatch(
      {
        d <- vpro_pg_query(pg, "SELECT COUNT(*) AS n FROM becmaster.env")
        if (nrow(d) >= 1L) as.integer(d$n[[1L]]) else 0L
      },
      error = function(e) 0L
    )

    becmaster_veg <- tryCatch(
      {
        d <- vpro_pg_query(pg, "SELECT COUNT(*) AS n FROM becmaster.veg")
        if (nrow(d) >= 1L) as.integer(d$n[[1L]]) else 0L
      },
      error = function(e) 0L
    )

    snapshot_count <- tryCatch(
      {
        d <- vpro_pg_query(pg, "SELECT COUNT(*) AS n FROM becmaster.snapshots")
        if (nrow(d) >= 1L) as.integer(d$n[[1L]]) else 0L
      },
      error = function(e) 0L
    )

    latest_snapshot_tag <- tryCatch(
      {
        d <- vpro_pg_query(
          pg,
          "SELECT snapshot_tag FROM becmaster.snapshots ORDER BY created_at DESC LIMIT 1"
        )
        if (nrow(d) >= 1L && !is.na(d$snapshot_tag[[1L]]) && nzchar(d$snapshot_tag[[1L]])) {
          as.character(d$snapshot_tag[[1L]])
        } else {
          NA_character_
        }
      },
      error = function(e) NA_character_
    )

    rel_df <- tryCatch(
      vpro_pg_query(
        pg,
        paste(
          "SELECT release_id, bec_version, taxonomy_version, vlists_sha256",
          "FROM standards.library_releases",
          "WHERE is_current = TRUE",
          "ORDER BY published_at DESC",
          "LIMIT 1"
        )
      ),
      error = function(e) data.frame()
    )
    if (nrow(rel_df) >= 1L) {
      standards_release <- as.character(rel_df$release_id[[1L]])
      bec_version <- as.character(rel_df$bec_version[[1L]])
      taxonomy_version <- as.character(rel_df$taxonomy_version[[1L]])
      vlists_sha256 <- as.character(rel_df$vlists_sha256[[1L]])
    }
  }

  if (schemas_bootstrapped && can_read_staging) {
    pending_submissions <- tryCatch(
      {
        d <- vpro_pg_query(
          pg,
          "SELECT COUNT(*) AS n FROM staging.submissions WHERE status = 'pending'"
        )
        if (nrow(d) >= 1L) as.integer(d$n[[1L]]) else 0L
      },
      error = function(e) 0L
    )
  }

  structure(
    list(
      connected = TRUE,
      role = as.character(pg$role),
      config_source = as.character(pg$config_source),
      dbname = as.character(pg$dbname),
      sslmode = as.character(pg$sslmode),
      latency_ms = elapsed_ms,
      server_version = server_version,
      postgis_version = postgis_version,
      schemas_bootstrapped = schemas_bootstrapped,
      can_read_master = can_read_master,
      can_submit_staging = can_submit_staging,
      can_merge_master = can_merge_master,
      can_bootstrap_schema = can_bootstrap_schema,
      becmaster_plots = becmaster_plots,
      becmaster_veg = becmaster_veg,
      pending_submissions = pending_submissions,
      snapshot_count = snapshot_count,
      latest_snapshot_tag = latest_snapshot_tag,
      standards_release = standards_release,
      bec_version = bec_version,
      taxonomy_version = taxonomy_version,
      vlists_sha256 = vlists_sha256,
      checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    class = "vpro_pg_status"
  )
}

#' @export
print.vpro_pg_status <- function(x, ...) {
  pgis_lbl <- if (!is.na(x$postgis_version) && nzchar(x$postgis_version)) {
    paste0("PostGIS ", x$postgis_version)
  } else {
    "PostGIS absent"
  }
  std_lbl <- if (!is.na(x$standards_release) && nzchar(x$standards_release)) {
    paste0(x$standards_release, " (BEC ", x$bec_version, ", Taxonomy ", x$taxonomy_version, ")")
  } else {
    "<none>"
  }
  snap_lbl <- if (!is.na(x$latest_snapshot_tag) && nzchar(x$latest_snapshot_tag)) {
    paste0(x$snapshot_count, " (latest: ", x$latest_snapshot_tag, ")")
  } else {
    as.character(x$snapshot_count)
  }

  cli::cli_h3("vpro_pg_status ({x$role} on {.val {x$dbname}}, TLS {.val {x$sslmode}})")
  cli::cli_bullets(c(
    "*" = "Server: PostgreSQL {x$server_version} ({pgis_lbl}, {x$latency_ms} ms)",
    "*" = "Capabilities: bootstrapped={x$schemas_bootstrapped}, read={x$can_read_master}, stage={x$can_submit_staging}, merge={x$can_merge_master}",
    "*" = "BECMaster: {x$becmaster_plots} plots, {x$becmaster_veg} veg rows | Snapshots: {snap_lbl}",
    "*" = "Standards: {std_lbl} | Pending staging: {x$pending_submissions}"
  ))
  invisible(x)
}

#' @export
as_tibble.vpro_pg_status <- function(x, ...) {
  tibble::tibble(
    connected = as.logical(x$connected),
    role = as.character(x$role),
    config_source = as.character(x$config_source),
    dbname = as.character(x$dbname),
    sslmode = as.character(x$sslmode),
    latency_ms = as.integer(x$latency_ms),
    server_version = as.character(x$server_version),
    postgis_version = as.character(x$postgis_version),
    schemas_bootstrapped = as.logical(x$schemas_bootstrapped),
    can_read_master = as.logical(x$can_read_master),
    can_submit_staging = as.logical(x$can_submit_staging),
    can_merge_master = as.logical(x$can_merge_master),
    can_bootstrap_schema = as.logical(x$can_bootstrap_schema),
    becmaster_plots = as.integer(x$becmaster_plots),
    becmaster_veg = as.integer(x$becmaster_veg),
    pending_submissions = as.integer(x$pending_submissions),
    snapshot_count = as.integer(x$snapshot_count),
    latest_snapshot_tag = as.character(x$latest_snapshot_tag),
    standards_release = as.character(x$standards_release),
    bec_version = as.character(x$bec_version),
    taxonomy_version = as.character(x$taxonomy_version),
    vlists_sha256 = as.character(x$vlists_sha256),
    checked_at = as.character(x$checked_at)
  )
}

#' Bootstrap `becmaster`, `staging`, and `standards` PostgreSQL schemas
#'
#' Non-destructively inspects `information_schema.schemata` and
#' `information_schema.tables`, then executes idempotent `CREATE SCHEMA IF NOT
#' EXISTS`, `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, trigger,
#' PostGIS `geom` column (when `postgis` is installed), and optional least-privilege
#' role grants / RLS policies matching VPro Desktop.
#' Never modifies `public` or drops existing data.
#'
#' @param pg A custodian `vpro_pg_conn` connection (`role == "custodian"`).
#' @param contributor_role Optional PostgreSQL role name to receive contributor
#'   `SELECT` / `staging` `INSERT` grants and RLS policies when present in
#'   `pg_roles`.
#' @param custodian_role Optional PostgreSQL role name to receive explicit
#'   custodian `ALL PRIVILEGES` grants on the three VPro schemas when present
#'   in `pg_roles`.
#' @return A list summarizing pre-existing and newly created schemas/tables,
#'   applied migrations, extension flags, and role grant status.
#' @export
vpro_master_bootstrap <- function(pg, contributor_role = NULL, custodian_role = NULL) {
  vpro_assert_pg_conn(pg, require_custodian = TRUE)

  norm_role <- function(r, arg_nm) {
    if (is.null(r)) {
      return("")
    }
    if (!is.character(r) || length(r) != 1L || is.na(r)) {
      cli::cli_abort("{.arg {arg_nm}} must be {.code NULL} or a single character string.")
    }
    trimws(r)
  }
  contrib_r <- norm_role(contributor_role, "contributor_role")
  custod_r <- norm_role(custodian_role, "custodian_role")
  if (nzchar(contrib_r) && nzchar(custod_r) && identical(contrib_r, custod_r)) {
    cli::cli_abort(
      "{.arg contributor_role} and {.arg custodian_role} must be distinct PostgreSQL roles."
    )
  }

  target_schemas <- c("becmaster", "staging", "standards")

  existing_sch_df <- vpro_pg_query(
    pg,
    "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('becmaster', 'staging', 'standards')",
    action = "Inspect existing PostgreSQL schemas"
  )
  existing_schemas <- if (nrow(existing_sch_df) > 0L) {
    as.character(existing_sch_df$schema_name)
  } else {
    character(0L)
  }

  existing_tbl_df <- vpro_pg_query(
    pg,
    paste(
      "SELECT table_schema, table_name FROM information_schema.tables",
      "WHERE table_schema IN ('becmaster', 'staging', 'standards') AND table_type = 'BASE TABLE'",
      "ORDER BY table_schema, table_name"
    ),
    action = "Inspect existing PostgreSQL tables"
  )
  existing_tables <- if (nrow(existing_tbl_df) > 0L) {
    paste0(existing_tbl_df$table_schema, ".", existing_tbl_df$table_name)
  } else {
    character(0L)
  }

  created_schemas <- character(0L)
  for (s_name in target_schemas) {
    if (s_name %in% existing_schemas) {
      priv <- vpro_pg_query(
        pg,
        "SELECT has_schema_privilege(current_user, $1, 'CREATE') AS ok",
        params = list(s_name),
        action = "Check schema CREATE privilege"
      )
      if (nrow(priv) == 0L || !isTRUE(as.logical(priv$ok[[1L]]))) {
        cli::cli_abort(
          "Custodian role lacks CREATE privilege on existing PostgreSQL schema {.val {s_name}}."
        )
      }
    } else {
      db_priv <- vpro_pg_query(
        pg,
        "SELECT has_database_privilege(current_user, current_database(), 'CREATE') AS ok",
        action = "Check database CREATE privilege"
      )
      if (nrow(db_priv) == 0L || !isTRUE(as.logical(db_priv$ok[[1L]]))) {
        cli::cli_abort(c(
          "Custodian role lacks CREATE privilege on database to initialize schema {.val {s_name}}.",
          "i" = "Ask a PostgreSQL DBA/superuser to run GRANT CREATE ON DATABASE <db> TO <custodian_role>."
        ))
      }
      vpro_pg_execute(
        pg,
        paste0("CREATE SCHEMA IF NOT EXISTS ", vpro_quote_ident(s_name)),
        action = paste0("Create schema ", s_name)
      )
      created_schemas <- c(created_schemas, s_name)
    }
  }

  ext_df <- vpro_pg_query(
    pg,
    paste(
      "SELECT e.extname, n.nspname AS schema_name",
      "FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace",
      "WHERE e.extname IN ('postgis', 'pgcrypto')"
    ),
    action = "Inspect PostgreSQL extensions"
  )
  has_postgis <- nrow(ext_df) > 0L && ("postgis" %in% ext_df$extname)
  has_pgcrypto <- nrow(ext_df) > 0L && ("pgcrypto" %in% ext_df$extname)
  postgis_schema <- if (has_postgis) {
    as.character(ext_df$schema_name[ext_df$extname == "postgis"][[1L]])
  } else {
    "public"
  }

  vpro_pg_execute(
    pg,
    paste(
      "CREATE TABLE IF NOT EXISTS becmaster.schema_migrations (",
      "  version INT PRIMARY KEY,",
      "  name TEXT NOT NULL,",
      "  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()",
      ");",
      sep = "\n"
    ),
    action = "Ensure becmaster.schema_migrations"
  )

  mig_df <- vpro_pg_query(
    pg,
    "SELECT EXISTS (SELECT 1 FROM becmaster.schema_migrations WHERE version = 1) AS ok",
    action = "Check schema_migrations version 1"
  )
  v1_already_applied <- nrow(mig_df) >= 1L && isTRUE(as.logical(mig_df$ok[[1L]]))

  stmts <- vpro_pg_build_v1_migration_stmts(
    has_postgis = has_postgis,
    postgis_schema = postgis_schema
  )

  applied_migrations <- character(0L)
  vpro_pg_exec_safe(
    function() {
      DBI::dbWithTransaction(pg$conn, {
        for (stmt in stmts) {
          DBI::dbExecute(pg$conn, stmt)
        }
        if (!v1_already_applied) {
          DBI::dbExecute(
            pg$conn,
            "INSERT INTO becmaster.schema_migrations (version, name) VALUES (1, 'v1_becmaster_staging_standards') ON CONFLICT (version) DO NOTHING"
          )
          applied_migrations <<- "1:v1_becmaster_staging_standards"
        }
      })
    },
    action = "Bootstrap PostgreSQL BECMaster schemas"
  )

  role_exists <- function(r_name) {
    if (!nzchar(r_name)) {
      return(FALSE)
    }
    d <- vpro_pg_query(
      pg,
      "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = $1) AS ok",
      params = list(r_name),
      action = "Check PostgreSQL pg_roles"
    )
    nrow(d) >= 1L && isTRUE(as.logical(d$ok[[1L]]))
  }

  has_contrib_role <- role_exists(contrib_r)
  has_custod_role <- role_exists(custod_r)
  role_grants_applied <- FALSE
  contributor_role_set <- FALSE

  if (has_contrib_role || has_custod_role) {
    grant_stmts <- character(0L)
    for (sch in target_schemas) {
      q_sch <- vpro_quote_ident(sch)
      grant_stmts <- c(
        grant_stmts,
        paste0("REVOKE ALL ON SCHEMA ", q_sch, " FROM PUBLIC"),
        paste0("REVOKE ALL ON ALL TABLES IN SCHEMA ", q_sch, " FROM PUBLIC"),
        paste0("REVOKE ALL ON ALL SEQUENCES IN SCHEMA ", q_sch, " FROM PUBLIC")
      )
    }

    if (has_custod_role) {
      q_admin <- vpro_quote_ident(custod_r)
      for (sch in target_schemas) {
        q_sch <- vpro_quote_ident(sch)
        grant_stmts <- c(
          grant_stmts,
          paste0("GRANT ALL PRIVILEGES ON SCHEMA ", q_sch, " TO ", q_admin),
          paste0("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ", q_sch, " TO ", q_admin),
          paste0("GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ", q_sch, " TO ", q_admin)
        )
      }
    }

    if (has_contrib_role) {
      q_user <- vpro_quote_ident(contrib_r)
      grant_stmts <- c(
        grant_stmts,
        paste0("REVOKE ALL ON ALL TABLES IN SCHEMA becmaster FROM ", q_user),
        paste0("REVOKE ALL ON ALL SEQUENCES IN SCHEMA becmaster FROM ", q_user),
        paste0("REVOKE ALL ON ALL TABLES IN SCHEMA staging FROM ", q_user),
        paste0("REVOKE ALL ON ALL SEQUENCES IN SCHEMA staging FROM ", q_user),
        paste0("REVOKE ALL ON ALL TABLES IN SCHEMA standards FROM ", q_user),
        paste0("REVOKE ALL ON ALL SEQUENCES IN SCHEMA standards FROM ", q_user),
        paste0("GRANT USAGE ON SCHEMA becmaster, staging, standards TO ", q_user),
        paste0("GRANT SELECT ON ALL TABLES IN SCHEMA becmaster TO ", q_user),
        paste0("GRANT SELECT ON ALL TABLES IN SCHEMA standards TO ", q_user),
        paste0("GRANT INSERT ON TABLE becmaster.download_log TO ", q_user),
        paste0("GRANT USAGE, SELECT ON SEQUENCE becmaster.download_log_id_seq TO ", q_user),
        paste0("GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA staging TO ", q_user),
        paste0("GRANT USAGE, SELECT ON SEQUENCE staging.audit_audit_seq_seq TO ", q_user),
        "ALTER TABLE staging.submissions ENABLE ROW LEVEL SECURITY",
        "DROP POLICY IF EXISTS submissions_contributor_select ON staging.submissions",
        paste0("CREATE POLICY submissions_contributor_select ON staging.submissions FOR SELECT TO ", q_user, " USING (true)"),
        "DROP POLICY IF EXISTS submissions_contributor_insert ON staging.submissions",
        paste0(
          "CREATE POLICY submissions_contributor_insert ON staging.submissions FOR INSERT TO ",
          q_user,
          " WITH CHECK (status = 'pending' AND compliance_passed = TRUE AND db_role = current_user AND reviewed_by IS NULL AND merged_tx_id IS NULL)"
        )
      )
      for (stg_tbl in c("env", "admin", "veg", "humus", "mineral", "other", "metadata", "audit")) {
        q_tbl <- vpro_quote_ident(stg_tbl)
        grant_stmts <- c(
          grant_stmts,
          paste0("DROP POLICY IF EXISTS ", vpro_quote_ident(paste0(stg_tbl, "_contributor_select")), " ON staging.", q_tbl),
          paste0("DROP POLICY IF EXISTS ", vpro_quote_ident(paste0(stg_tbl, "_contributor_insert")), " ON staging.", q_tbl),
          paste0("ALTER TABLE staging.", q_tbl, " DISABLE ROW LEVEL SECURITY")
        )
      }
    }

    vpro_pg_exec_safe(
      function() {
        DBI::dbWithTransaction(pg$conn, {
          for (g_stmt in grant_stmts) {
            DBI::dbExecute(pg$conn, g_stmt)
          }
        })
      },
      action = "Apply PostgreSQL role grants and RLS policies"
    )
    role_grants_applied <- TRUE
    contributor_role_set <- has_contrib_role
  }

  after_tbl_df <- vpro_pg_query(
    pg,
    paste(
      "SELECT table_schema, table_name FROM information_schema.tables",
      "WHERE table_schema IN ('becmaster', 'staging', 'standards') AND table_type = 'BASE TABLE'",
      "ORDER BY table_schema, table_name"
    ),
    action = "Verify bootstrapped PostgreSQL tables"
  )
  all_tables <- if (nrow(after_tbl_df) > 0L) {
    paste0(after_tbl_df$table_schema, ".", after_tbl_df$table_name)
  } else {
    character(0L)
  }
  created_tables <- setdiff(all_tables, existing_tables)

  list(
    schema_version = 1L,
    schemas_verified = target_schemas,
    existing_schemas = existing_schemas,
    created_schemas = created_schemas,
    existing_tables = existing_tables,
    created_tables = created_tables,
    applied_migrations = applied_migrations,
    postgis_enabled = has_postgis,
    pgcrypto_enabled = has_pgcrypto,
    role_grants_applied = role_grants_applied,
    contributor_role_set = contributor_role_set,
    bootstrapped_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}
