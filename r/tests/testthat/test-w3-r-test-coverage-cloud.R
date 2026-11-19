# Wave 3 (ENG-R-008): Offline unit & mock-DBI test coverage across all cloud_*.R modules

if (!methods::isClass("VproMockPgConn", where = .GlobalEnv)) {
  methods::setClass(
    "VproMockPgConn",
    slots = c(sqlite = "ANY", state = "environment"),
    contains = "DBIConnection",
    where = .GlobalEnv
  )
}

pg_array_literal_to_json <- function(lit) {
  s <- trimws(as.character(lit[[1L]]))
  if (!startsWith(s, "{") || !endsWith(s, "}")) {
    return(as.character(jsonlite::toJSON(s, auto_unbox = FALSE)))
  }
  inner <- substr(s, 2L, nchar(s) - 1L)
  if (!nzchar(inner)) {
    return("[]")
  }
  chars <- strsplit(inner, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  elems <- character()
  cur <- character()
  in_quotes <- FALSE
  was_quoted <- FALSE
  i <- 1L
  while (i <= n) {
    ch <- chars[[i]]
    if (in_quotes) {
      if (identical(ch, "\\") && i < n) {
        i <- i + 1L
        cur <- c(cur, chars[[i]])
      } else if (identical(ch, '"')) {
        in_quotes <- FALSE
      } else {
        cur <- c(cur, ch)
      }
    } else {
      if (identical(ch, '"')) {
        in_quotes <- TRUE
        was_quoted <- TRUE
      } else if (identical(ch, ",")) {
        tok <- paste0(cur, collapse = "")
        if (!was_quoted && identical(toupper(trimws(tok)), "NULL")) {
          elems <- c(elems, NA_character_)
        } else {
          elems <- c(elems, if (was_quoted) tok else trimws(tok))
        }
        cur <- character()
        was_quoted <- FALSE
      } else {
        cur <- c(cur, ch)
      }
    }
    i <- i + 1L
  }
  tok <- paste0(cur, collapse = "")
  if (!was_quoted && identical(toupper(trimws(tok)), "NULL")) {
    elems <- c(elems, NA_character_)
  } else {
    elems <- c(elems, if (was_quoted) tok else trimws(tok))
  }
  as.character(jsonlite::toJSON(elems, auto_unbox = FALSE, na = "null"))
}

mock_pg_list_tables <- function(conn) {
  st <- conn@state
  schemas <- intersect(st$schemas, c("becmaster", "staging", "standards"))
  if (length(schemas) == 0L) {
    return(data.frame(table_schema = character(), table_name = character(), stringsAsFactors = FALSE))
  }
  parts <- lapply(schemas, function(sch) {
    df <- DBI::dbGetQuery(
      conn@sqlite,
      sprintf("SELECT name FROM %s.sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%%' ORDER BY name", sch)
    )
    if (nrow(df) == 0L) {
      data.frame(table_schema = character(), table_name = character(), stringsAsFactors = FALSE)
    } else {
      data.frame(table_schema = rep(sch, nrow(df)), table_name = as.character(df$name), stringsAsFactors = FALSE)
    }
  })
  out <- do.call(rbind, parts)
  if (nrow(out) > 0L) {
    out <- out[order(out$table_schema, out$table_name), , drop = FALSE]
    rownames(out) <- NULL
  }
  out
}

mock_pg_translate <- function(sql, params, st) {
  s <- sql
  p_out <- if (is.null(params)) NULL else as.list(params)

  # Convert = ANY($k::text[]) and = ANY($k::bigint[]) using SQLite json_each($k)
  any_pat <- '(UPPER\\(TRIM\\(CAST\\("[^"]+" AS TEXT\\)\\)\\)|UPPER\\("[^"]+"\\)|[A-Za-z0-9_."]+(?:::text)?)\\s*=\\s*ANY\\(\\$([0-9]+)::(text|bigint)\\[\\]\\)'
  m <- gregexpr(any_pat, s, perl = TRUE)[[1L]]
  if (m[[1L]] > 0L && !is.null(p_out)) {
    matches <- regmatches(s, gregexpr(any_pat, s, perl = TRUE))[[1L]]
    idxs <- unique(as.integer(sub('^.*\\$([0-9]+)::(?:text|bigint)\\[\\]\\)$', "\\1", matches, perl = TRUE)))
    for (k in idxs) {
      if (k >= 1L && k <= length(p_out)) {
        p_out[[k]] <- pg_array_literal_to_json(p_out[[k]])
      }
    }
    s <- gsub(any_pat, "\\1 IN (SELECT value FROM json_each($\\2))", s, perl = TRUE)
  }

  # Strip PostGIS spatial index operator predicate (keep exact BETWEEN bounds)
  s <- gsub('[A-Za-z0-9_.]*geom\\s*&&\\s*"[^"]+"\\.ST_MakeEnvelope\\([^)]+\\)\\s*AND\\s*', "1=1 AND ", s, perl = TRUE)

  # JSON / bytea / date / scalar functions
  s <- gsub("\\(user_species_manifest->>'rowCount'\\)::int", "CAST(json_extract(user_species_manifest, '$.rowCount') AS INTEGER)", s, perl = TRUE)
  s <- gsub("jsonb_array_length\\(", "json_array_length(", s, perl = TRUE)
  s <- gsub("octet_length\\(", "length(", s, perl = TRUE)
  s <- gsub(
    "to_char\\(now\\(\\) AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS'\\)",
    "strftime('%Y-%m-%d %H:%M:%S', 'now')",
    s,
    perl = TRUE
  )
  s <- gsub(
    'to_char\\(now\\(\\) AT TIME ZONE \'UTC\', \'YYYY-MM-DD"T"HH24:MI:SS"Z"\'\\)',
    "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')",
    s,
    perl = TRUE
  )
  s <- gsub(
    'to_char\\(([A-Za-z0-9_."]+) AT TIME ZONE \'UTC\', \'YYYY-MM-DD"T"HH24:MI:SS"Z"\'\\)',
    "CAST(\\1 AS TEXT)",
    s,
    perl = TRUE
  )
  s <- gsub("\\bnow\\(\\)", "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')", s, perl = TRUE)
  s <- gsub("\\bcurrent_user\\b", paste0("'", st$current_user, "'"), s, perl = TRUE)
  s <- gsub("\\bGREATEST\\(", "MAX(", s, perl = TRUE)
  s <- gsub("\\bbecmaster\\.child_identity_watermark\\.max_id\\b", "child_identity_watermark.max_id", s, perl = TRUE)
  s <- gsub("\\s+FOR UPDATE\\s*$", "", s, perl = TRUE)

  # Strip PostgreSQL parameter & expression casts, then map $k -> SQLite 1-based ?k
  s <- gsub("\\$([0-9]+)::(?:double precision|[a-zA-Z0-9_]+)", "$\\1", s, perl = TRUE)
  s <- gsub("'\\[\\]'::jsonb", "'[]'", s, perl = TRUE)
  s <- gsub('([A-Za-z0-9_."\\)]+)::text', "CAST(\\1 AS TEXT)", s, perl = TRUE)
  s <- gsub('([A-Za-z0-9_."\\)]+)::(?:bigint|int|smallint)', "CAST(\\1 AS INTEGER)", s, perl = TRUE)
  s <- gsub('([A-Za-z0-9_."\\)]+)::uuid', "CAST(\\1 AS TEXT)", s, perl = TRUE)
  s <- gsub("\\$([0-9]+)", "?\\1", s, perl = TRUE)

  if (!is.null(p_out) && length(p_out) > 0L) {
    p_out <- lapply(p_out, function(v) {
      if (is.logical(v)) as.integer(v) else v
    })
  }
  list(sql = s, params = p_out)
}

methods::setMethod(DBI::dbIsValid, "VproMockPgConn", function(dbObj, ...) {
  isTRUE(dbObj@state$valid) && DBI::dbIsValid(dbObj@sqlite)
}, where = .GlobalEnv)

methods::setMethod(DBI::dbDisconnect, "VproMockPgConn", function(conn, ...) {
  conn@state$valid <- FALSE
  if (DBI::dbIsValid(conn@sqlite)) {
    DBI::dbDisconnect(conn@sqlite)
  }
  invisible(TRUE)
}, where = .GlobalEnv)

methods::setMethod(
  DBI::dbAppendTable,
  signature(conn = "VproMockPgConn", name = "ANY", value = "data.frame"),
  function(conn, name, value, ..., row.names = NULL) {
    DBI::dbAppendTable(conn@sqlite, name, value, ..., row.names = row.names)
  },
  where = .GlobalEnv
)

methods::setMethod(
  DBI::dbWithTransaction,
  signature(conn = "VproMockPgConn", code = "ANY"),
  function(conn, code, ...) {
    DBI::dbWithTransaction(conn@sqlite, code)
  },
  where = .GlobalEnv
)

methods::setMethod(
  DBI::dbExecute,
  signature(conn = "VproMockPgConn", statement = "character"),
  function(conn, statement, params = NULL, ...) {
    st <- conn@state
    sql_trim <- trimws(statement)
    st$ddl_log <- c(st$ddl_log, sql_trim)

    if (grepl('^CREATE SCHEMA IF NOT EXISTS ', sql_trim, ignore.case = TRUE)) {
      sch <- gsub('^CREATE SCHEMA IF NOT EXISTS "?([a-zA-Z0-9_]+)"?.*$', "\\1", sql_trim)
      st$schemas <- unique(c(st$schemas, tolower(sch)))
      return(0L)
    }
    if (
      grepl("^(DO \\$\\$|CREATE OR REPLACE FUNCTION|REVOKE |GRANT |DROP POLICY |CREATE POLICY )", sql_trim, ignore.case = TRUE) ||
        grepl("ROW LEVEL SECURITY|USING GIST", sql_trim, ignore.case = TRUE)
    ) {
      return(0L)
    }
    if (grepl("^ALTER TABLE becmaster\\.env ADD COLUMN IF NOT EXISTS geom", sql_trim, ignore.case = TRUE)) {
      st$has_geom_col <- TRUE
      tryCatch(DBI::dbExecute(conn@sqlite, 'ALTER TABLE becmaster."env" ADD COLUMN "geom" TEXT'), error = function(e) NULL)
      return(0L)
    }
    if (grepl("^BEGIN\\b", sql_trim, ignore.case = TRUE)) {
      return(DBI::dbExecute(conn@sqlite, "BEGIN"))
    }
    if (grepl("^(COMMIT|ROLLBACK)\\b", sql_trim, ignore.case = TRUE)) {
      return(DBI::dbExecute(conn@sqlite, sql_trim))
    }
    if (grepl("^CREATE (?:UNIQUE )?INDEX IF NOT EXISTS ", sql_trim, ignore.case = TRUE)) {
      idx_sql <- sub(
        "^CREATE (UNIQUE )?INDEX IF NOT EXISTS ([A-Za-z0-9_\"]+) ON (becmaster|staging|standards)\\.([A-Za-z0-9_\"]+)",
        "CREATE \\1INDEX IF NOT EXISTS \\3.\\2 ON \\4",
        sql_trim,
        ignore.case = TRUE
      )
      return(DBI::dbExecute(conn@sqlite, idx_sql))
    }
    if (grepl("^CREATE TABLE IF NOT EXISTS ", sql_trim, ignore.case = TRUE)) {
      ddl <- sql_trim
      ddl <- gsub("\\bBIGSERIAL PRIMARY KEY\\b", "INTEGER PRIMARY KEY AUTOINCREMENT", ddl)
      ddl <- gsub("REFERENCES (?:becmaster|staging|standards)\\.", "REFERENCES ", ddl)
      ddl <- gsub("DEFAULT '\\[\\]'::jsonb", "DEFAULT '[]'", ddl)
      ddl <- gsub("TIMESTAMPTZ NOT NULL DEFAULT now\\(\\)", "TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP", ddl)
      ddl <- gsub("\\bTIMESTAMPTZ\\b", "TEXT", ddl)
      ddl <- gsub("\\bJSONB\\b", "TEXT", ddl)
      ddl <- gsub("\\bUUID\\b", "TEXT", ddl)
      ddl <- gsub("\\bBYTEA\\b", "BLOB", ddl)
      ddl <- gsub("\\bDOUBLE PRECISION\\b", "REAL", ddl)
      return(DBI::dbExecute(conn@sqlite, ddl))
    }

    tr <- mock_pg_translate(sql_trim, params, st)
    if (is.null(tr$params) || length(tr$params) == 0L) {
      DBI::dbExecute(conn@sqlite, tr$sql)
    } else {
      DBI::dbExecute(conn@sqlite, tr$sql, params = unname(tr$params))
    }
  },
  where = .GlobalEnv
)

methods::setMethod(
  DBI::dbGetQuery,
  signature(conn = "VproMockPgConn", statement = "character"),
  function(conn, statement, params = NULL, ...) {
    st <- conn@state
    sql_trim <- trimws(statement)

    if (grepl("^SHOW server_version", sql_trim, ignore.case = TRUE)) {
      return(data.frame(server_version = "16.4 (MockPg)", stringsAsFactors = FALSE))
    }
    if (grepl("has_geom", sql_trim, fixed = TRUE) && grepl("pg_extension", sql_trim, fixed = TRUE)) {
      return(data.frame(
        postgis_schema = if (isTRUE(st$has_postgis)) st$postgis_schema else "",
        has_geom = isTRUE(st$has_postgis) && isTRUE(st$has_geom_col),
        stringsAsFactors = FALSE
      ))
    }
    if (grepl("SELECT extversion FROM pg_extension", sql_trim, ignore.case = TRUE)) {
      if (isTRUE(st$has_postgis)) {
        return(data.frame(extversion = "3.4.2", stringsAsFactors = FALSE))
      }
      return(data.frame(extversion = character(), stringsAsFactors = FALSE))
    }
    if (grepl("FROM pg_extension", sql_trim, ignore.case = TRUE)) {
      exts <- character()
      schs <- character()
      if (isTRUE(st$has_postgis)) {
        exts <- c(exts, "postgis")
        schs <- c(schs, st$postgis_schema)
      }
      if (isTRUE(st$has_pgcrypto)) {
        exts <- c(exts, "pgcrypto")
        schs <- c(schs, "public")
      }
      return(data.frame(extname = exts, schema_name = schs, stringsAsFactors = FALSE))
    }
    if (grepl("has_database_privilege", sql_trim, fixed = TRUE)) {
      return(data.frame(ok = isTRUE(st$can_create_db), stringsAsFactors = FALSE))
    }
    if (grepl("can_read_master", sql_trim, fixed = TRUE)) {
      return(data.frame(
        can_read_master = TRUE,
        can_submit_staging = TRUE,
        can_merge_master = identical(st$role, "custodian"),
        can_read_staging = TRUE,
        stringsAsFactors = FALSE
      ))
    }
    if (grepl("has_schema_privilege", sql_trim, fixed = TRUE)) {
      return(data.frame(ok = isTRUE(st$can_create_schema), stringsAsFactors = FALSE))
    }
    if (grepl("FROM information_schema\\.schemata", sql_trim, ignore.case = TRUE)) {
      hit <- intersect(st$schemas, c("becmaster", "staging", "standards"))
      if (grepl("COUNT\\(\\*\\)", sql_trim, ignore.case = TRUE)) {
        return(data.frame(n = length(hit), stringsAsFactors = FALSE))
      }
      return(data.frame(schema_name = hit, stringsAsFactors = FALSE))
    }
    if (grepl("FROM pg_class", sql_trim, ignore.case = TRUE) && grepl("becmaster", sql_trim, fixed = TRUE)) {
      tbls <- mock_pg_list_tables(conn)
      has_env <- any(tbls$table_schema == "becmaster" & tbls$table_name == "env")
      return(data.frame(ok = has_env, stringsAsFactors = FALSE))
    }
    if (grepl("FROM information_schema\\.tables", sql_trim, ignore.case = TRUE)) {
      tbls <- mock_pg_list_tables(conn)
      if (grepl("usys_spp_attributes", sql_trim, fixed = TRUE)) {
        ok <- any(tbls$table_schema == "standards" & tbls$table_name == "usys_spp_attributes")
        return(data.frame(ok = ok, stringsAsFactors = FALSE))
      }
      return(tbls)
    }
    if (grepl("to_regclass\\(\\$1\\)", sql_trim, ignore.case = TRUE)) {
      target <- as.character(params[[1L]])
      sp <- strsplit(target, ".", fixed = TRUE)[[1L]]
      tbls <- mock_pg_list_tables(conn)
      ok <- length(sp) == 2L && any(tbls$table_schema == sp[[1L]] & tbls$table_name == sp[[2L]])
      return(data.frame(ok = ok, stringsAsFactors = FALSE))
    }
    if (grepl("FROM pg_roles", sql_trim, ignore.case = TRUE)) {
      r_nm <- as.character(params[[1L]])
      return(data.frame(ok = r_nm %in% st$roles, stringsAsFactors = FALSE))
    }
    if (grepl("^SELECT current_user AS db_role", sql_trim, ignore.case = TRUE)) {
      return(data.frame(
        db_role = st$current_user,
        now_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
        stringsAsFactors = FALSE
      ))
    }
    if (grepl("^SELECT current_user AS usr", sql_trim, ignore.case = TRUE)) {
      return(data.frame(usr = st$current_user, stringsAsFactors = FALSE))
    }

    tr <- mock_pg_translate(sql_trim, params, st)
    if (is.null(tr$params) || length(tr$params) == 0L) {
      DBI::dbGetQuery(conn@sqlite, tr$sql)
    } else {
      DBI::dbGetQuery(conn@sqlite, tr$sql, params = unname(tr$params))
    }
  },
  where = .GlobalEnv
)

new_mock_pg_cluster <- function(has_postgis = TRUE) {
  sq <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbExecute(sq, "ATTACH DATABASE ':memory:' AS becmaster")
  DBI::dbExecute(sq, "ATTACH DATABASE ':memory:' AS staging")
  DBI::dbExecute(sq, "ATTACH DATABASE ':memory:' AS standards")

  make_handle <- function(role = c("custodian", "contributor"), shared_state = NULL) {
    role <- match.arg(role)
    st <- if (is.null(shared_state)) {
      e <- new.env(parent = emptyenv())
      e$valid <- TRUE
      e$schemas <- character(0L)
      e$has_postgis <- has_postgis
      e$postgis_schema <- "public"
      e$has_pgcrypto <- TRUE
      e$has_geom_col <- FALSE
      e$can_create_db <- TRUE
      e$can_create_schema <- TRUE
      e$roles <- c("bec_contributor", "bec_custodian")
      e$ddl_log <- character(0L)
      e
    } else {
      shared_state
    }
    handle_state <- new.env(parent = st)
    handle_state$valid <- TRUE
    handle_state$role <- role
    handle_state$current_user <- if (identical(role, "custodian")) "bec_custodian" else "bec_contributor"
    # Forward mutable cluster state reads/writes to shared root state
    makeActiveBinding("schemas", function(v) if (missing(v)) st$schemas else { st$schemas <- v }, handle_state)
    makeActiveBinding("has_postgis", function(v) if (missing(v)) st$has_postgis else { st$has_postgis <- v }, handle_state)
    makeActiveBinding("postgis_schema", function(v) if (missing(v)) st$postgis_schema else { st$postgis_schema <- v }, handle_state)
    makeActiveBinding("has_pgcrypto", function(v) if (missing(v)) st$has_pgcrypto else { st$has_pgcrypto <- v }, handle_state)
    makeActiveBinding("has_geom_col", function(v) if (missing(v)) st$has_geom_col else { st$has_geom_col <- v }, handle_state)
    makeActiveBinding("can_create_db", function(v) if (missing(v)) st$can_create_db else { st$can_create_db <- v }, handle_state)
    makeActiveBinding("can_create_schema", function(v) if (missing(v)) st$can_create_schema else { st$can_create_schema <- v }, handle_state)
    makeActiveBinding("roles", function(v) if (missing(v)) st$roles else { st$roles <- v }, handle_state)
    makeActiveBinding("ddl_log", function(v) if (missing(v)) st$ddl_log else { st$ddl_log <- v }, handle_state)

    mock_s4 <- methods::new("VproMockPgConn", sqlite = sq, state = handle_state)
    list(
      pg = structure(
        list(
          conn = mock_s4,
          role = role,
          host = "mock-pg.internal.gov.bc.ca",
          port = 5432L,
          dbname = "becmaster_test",
          user = handle_state$current_user,
          sslmode = "verify-full",
          config_source = "args",
          connected_at = "2026-11-19T12:00:00Z",
          status = NULL
        ),
        class = "vpro_pg_conn"
      ),
      shared = st
    )
  }

  cust <- make_handle("custodian")
  contrib <- make_handle("contributor", shared_state = cust$shared)
  list(
    sqlite = sq,
    shared = cust$shared,
    custodian = cust$pg,
    contributor = contrib$pg,
    close = function() {
      if (DBI::dbIsValid(sq)) DBI::dbDisconnect(sq)
    }
  )
}

seed_mock_becmaster <- function(sq) {
  # 1. Seed standards.* tables
  vlists_path <- vpro:::vpro_bundled_db("VLists.db")
  vlists_sha <- vpro:::vpro_sha256_file(vlists_path)
  vlists_raw <- readBin(vlists_path, what = "raw", n = file.info(vlists_path)$size)
  vlists_gz <- memCompress(vlists_raw, type = "gzip")

  DBI::dbExecute(
    sq,
    paste(
      "INSERT INTO standards.library_releases (",
      "  release_id, published_at, published_by, bec_version, taxonomy_version,",
      "  vlists_sha256, bec_db_sha256, vmetadata_sha256, notes, is_current, vlists_gzip",
      ") VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 1, $10)"
    ),
    params = list(
      "STD_2026_11",
      "2026-11-01T00:00:00Z",
      "bec_custodian",
      "BECdb_v13_2026",
      "BCPlantTaxa_v19_2025",
      vlists_sha,
      "becsha",
      "metasha",
      "2026 standards release",
      I(list(vlists_gz))
    )
  )

  # Copy small representative slices from bundled VLists.db into standards.*
  vl_ro <- DBI::dbConnect(RSQLite::SQLite(), vlists_path, flags = RSQLite::SQLITE_RO)
  on.exit(if (DBI::dbIsValid(vl_ro)) DBI::dbDisconnect(vl_ro), add = TRUE)

  specs_sub <- DBI::dbGetQuery(
    vl_ro,
    'SELECT * FROM "USysAllSpecs" WHERE UPPER("Code") IN (\'PINUCON\', \'TSUGHET\', \'THUJPLI\', \'ABIELAS\', \'ABIEAMA\', \'POA PRA2\', \'POA SEC\', \'POASPP\') OR UPPER("OldCode") IN (\'THUIABI\') LIMIT 25'
  )
  specs_pg <- vpro:::vpro_pg_canonicalize_to_pg(specs_sub, vpro:::vpro_pg_standards_specs("usys_all_specs"))
  DBI::dbAppendTable(sq, DBI::Id(schema = "standards", table = "usys_all_specs"), specs_pg)

  lists_sub <- DBI::dbGetQuery(vl_ro, 'SELECT * FROM "USysTableOfLists" WHERE "ListName" IN (\'DataQuality\', \'MoistureRegime\') LIMIT 30')
  lists_pg <- vpro:::vpro_pg_canonicalize_to_pg(lists_sub, vpro:::vpro_pg_standards_specs("usys_table_of_lists"))
  DBI::dbAppendTable(sq, DBI::Id(schema = "standards", table = "usys_table_of_lists"), lists_pg)

  msu_sub <- DBI::dbGetQuery(vl_ro, 'SELECT * FROM "MasterSiteUnitList" LIMIT 10')
  msu_pg <- vpro:::vpro_pg_canonicalize_to_pg(msu_sub, vpro:::vpro_pg_standards_specs("master_site_unit_list"))
  DBI::dbAppendTable(sq, DBI::Id(schema = "standards", table = "master_site_unit_list"), msu_pg)

  zl_sub <- DBI::dbGetQuery(vl_ro, 'SELECT * FROM "USysZoneList" LIMIT 10')
  zl_pg <- vpro:::vpro_pg_canonicalize_to_pg(zl_sub, vpro:::vpro_pg_standards_specs("usys_zone_list"))
  DBI::dbAppendTable(sq, DBI::Id(schema = "standards", table = "usys_zone_list"), zl_pg)

  if (DBI::dbExistsTable(vl_ro, "USysSppAttributes")) {
    attr_sub <- DBI::dbGetQuery(vl_ro, 'SELECT * FROM "USysSppAttributes" LIMIT 5')
  } else {
    attr_sub <- data.frame(Code = character(), Codetype = character(), RedBlueList = character(), stringsAsFactors = FALSE)
  }
  attr_red <- data.frame(Flag = 0L, Code = "RQASPP1", Codetype = "U", RedBlueList = "R", ID = 901L, stringsAsFactors = FALSE)
  attr_pg <- vpro:::vpro_pg_canonicalize_to_pg(attr_red, vpro:::vpro_pg_standards_specs("usys_spp_attributes"))
  DBI::dbAppendTable(sq, DBI::Id(schema = "standards", table = "usys_spp_attributes"), attr_pg)

  bec_ss <- data.frame(Zone = "SBS", SubZone = "dk", SiteSeries = "01", SiteSeriesName = "Sxw - Spirea - Purple peavine", ID = 1L, stringsAsFactors = FALSE)
  DBI::dbAppendTable(
    sq,
    DBI::Id(schema = "standards", table = "bec_site_series"),
    vpro:::vpro_pg_canonicalize_to_pg(bec_ss, vpro:::vpro_pg_standards_specs("bec_site_series"))
  )

  pmeta <- data.frame(ProjectID = "BEC_CORE", ProjectTitle = "Provincial Core Plots", stringsAsFactors = FALSE)
  DBI::dbAppendTable(
    sq,
    DBI::Id(schema = "standards", table = "project_metadata"),
    vpro:::vpro_pg_canonicalize_to_pg(pmeta, vpro:::vpro_pg_standards_specs("project_metadata"))
  )
  DBI::dbDisconnect(vl_ro)

  # 2. Seed becmaster.* plots:
  # - '00337': non-sensitive SBSdk plot
  # - '01001': sensitive CWHvm1 plot containing Red-listed species 'RQASPP1'
  # - '01002': CWHvm1 plot for 3-way conflict & child row delete testing
  env_in <- data.frame(
    PlotNumber = c("00337", "01001", "01002"),
    ProjectID = c("BEC_CORE", "BEC_CORE", "BEC_CORE"),
    Zone = c("SBS", "CWH", "CWH"),
    SubZone = c("dk", "vm", "vm"),
    SiteSeries = c("01", "01", "05"),
    MoistureRegime = c("4", "7", "6"),
    NutrientRegime = c("C", "C", "D"),
    Elevation = c(520L, 185L, 210L),
    SlopeGradient = c(15.0, 10.0, 5.0),
    Aspect = c(180L, 220L, 90L),
    Latitude = c(54.7804, 49.6543, 49.7123),
    Longitude = c(-127.1743, -125.4321, -125.5123),
    UTMZone = c("9", "10", "10"),
    UTMEasting = c(617420.0, 324567.0, 318900.0),
    UTMNorthing = c(6071890.0, 5502345.0, 5508900.0),
    XCoord = c(-127.1743, -125.4321, -125.5123),
    YCoord = c(54.7804, 49.6543, 49.7123),
    SiteNotes = c("Initial SBSdk note", "Sensitive rare plant plot", "Base plot 01002"),
    SpeciesListComplete = c(-1L, -1L, 0L),
    Flag = c(0L, -1L, 0L),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(
    sq,
    DBI::Id(schema = "becmaster", table = "env"),
    vpro:::vpro_pg_canonicalize_to_pg(env_in, vpro:::vpro_pg_vp08_specs("Env"))
  )

  adm_in <- data.frame(
    Plot = c("00337", "01001", "01002"),
    PlotType = c("FS882", "FS882", "FS882"),
    SitePlotQuality = c("Good", "Excellent", "Good"),
    VegPlotQuality = c("Good", "Excellent", "Good"),
    SoilPlotQuality = c("Good", "Good", "Good"),
    UpdatedFromCards = c(-1L, 0L, 0L),
    UserSiteUnit = c("SBSdk/01", "CWHvm1/01", "CWHvm1/05"),
    BECSiteUnit = c("SBSdk/01", "CWHvm1/01", "CWHvm1/05"),
    BEC_Use = c("1", "1", "1"),
    StrataCoverTree = c(45.0, 60.0, 55.0),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(
    sq,
    DBI::Id(schema = "becmaster", table = "admin"),
    vpro:::vpro_pg_canonicalize_to_pg(adm_in, vpro:::vpro_pg_vp08_specs("Admin"))
  )

  veg_in <- data.frame(
    PlotNumber = c("00337", "00337", "00337", "01001", "01001", "01002", "01002"),
    Species = c("PINUCON", "POA PRA2", "POA SEC", "TSUGHET", "RQASPP1", "THUJPLI", "ABIELAS"),
    Layer = c("1", "6", "6", "1", "6", "1", "4"),
    Cover1 = c(42.0, NA, NA, 55.0, NA, 48.0, NA),
    Cover4 = c(NA, NA, NA, NA, NA, NA, 18.0),
    Cover6 = c(NA, 60.0, 55.0, NA, 5.5, NA, NA),
    TotalA = c(42.0, NA, NA, 55.0, NA, 48.0, NA),
    Flag = c(0L, 0L, 0L, 0L, 0L, 0L, 0L),
    ID = c(101L, 102L, 103L, 104L, 105L, 106L, 107L),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(
    sq,
    DBI::Id(schema = "becmaster", table = "veg"),
    vpro:::vpro_pg_canonicalize_to_pg(veg_in, vpro:::vpro_pg_vp08_specs("Veg"))
  )

  hum_in <- data.frame(
    PlotNumber = c("00337", "00337", "01001"),
    Horizon = c("L", "Fm", "Of"),
    UpperDepth = c(8.0, 5.0, 0.0),
    LowerDepth = c(5.0, 0.0, 15.0),
    HumusFormpH = c(4.8, 4.5, 5.1),
    Flag = c(0L, 0L, 0L),
    ID = c(201L, 202L, 203L),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(
    sq,
    DBI::Id(schema = "becmaster", table = "humus"),
    vpro:::vpro_pg_canonicalize_to_pg(hum_in, vpro:::vpro_pg_vp08_specs("Humus"))
  )

  min_in <- data.frame(
    PlotNumber = c("00337", "01001"),
    Horizon = c("Bm1", "Bg"),
    UpperDepth = c(0.0, 15.0),
    LowerDepth = c(30.0, 45.0),
    Texture = c("SL", "L"),
    PercentCoarseFragsTotal = c(25L, 10L),
    Flag = c(0L, 0L),
    ID = c(301L, 302L),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(
    sq,
    DBI::Id(schema = "becmaster", table = "mineral"),
    vpro:::vpro_pg_canonicalize_to_pg(min_in, vpro:::vpro_pg_vp08_specs("Mineral"))
  )

  meta_in <- data.frame(
    ProjectID = "BEC_CORE",
    ProjectTitle = "Provincial BECMaster Core",
    ID = 1L,
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(
    sq,
    DBI::Id(schema = "becmaster", table = "metadata"),
    vpro:::vpro_pg_canonicalize_to_pg(meta_in, vpro:::vpro_pg_vp08_specs("Metadata"))
  )

  # Seed 2 valid genesis-anchored hash-chained rows in becmaster.audit
  tx0 <- "00000000-1111-4222-8333-444444444444"
  v1 <- list("BECMaster", "bec_custodian", "00337", "_Env", "Zone", "2026-11-01 09:00:00", NA_character_, "SBS", 0L, 0L, NA_integer_)
  h1 <- vpro:::vpro_compute_audit_row_hash(vpro:::.vpro_genesis_audit_hash, tx0, v1)
  v2 <- list("BECMaster", "bec_custodian", "01001", "_Env", "Zone", "2026-11-01 09:00:01", NA_character_, "CWH", 0L, 0L, NA_integer_)
  h2 <- vpro:::vpro_compute_audit_row_hash(h1, tx0, v2)
  aud_in <- data.frame(
    Project = c("BECMaster", "BECMaster"),
    User = c("bec_custodian", "bec_custodian"),
    PlotNumber = c("00337", "01001"),
    Table = c("_Env", "_Env"),
    EditField = c("Zone", "Zone"),
    EditWhen = c("2026-11-01 09:00:00", "2026-11-01 09:00:01"),
    BeforeEdit = c(NA_character_, NA_character_),
    AfterEdit = c("SBS", "CWH"),
    Restore = c(0L, 0L),
    Flag = c(0L, 0L),
    ID = c(NA_integer_, NA_integer_),
    merge_tx_id = c(tx0, tx0),
    prev_hash = c(vpro:::.vpro_genesis_audit_hash, h1),
    row_hash = c(h1, h2),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(sq, DBI::Id(schema = "becmaster", table = "audit"), aud_in)
  invisible(vlists_sha)
}

test_that("DDL builders, column specs, canonicalizers, and merge cell/horizon validators enforce all VP08 rules", {
  # Direct spec constructors & all 8 VP08 specs + all 7 standards specs
  mini_spec <- vpro:::vpro_pg_build_spec_df(list(
    vpro:::vpro_pg_tcol("PlotNumber", "VARCHAR", 7L),
    vpro:::vpro_pg_icol("Elevation", "SMALLINT"),
    vpro:::vpro_pg_fcol("Cover1", "REAL", TRUE),
    vpro:::vpro_pg_bcol("Flag")
  ))
  expect_equal(nrow(mini_spec), 4L)
  expect_equal(mini_spec$pg_type, c("TEXT", "BIGINT", "DOUBLE PRECISION", "SMALLINT"))

  for (sfx in c("Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Audit", "Metadata")) {
    sp <- vpro:::vpro_pg_vp08_specs(sfx)
    expect_gt(nrow(sp), 3L)
  }
  expect_error(vpro:::vpro_pg_vp08_specs(""), "suffix")
  expect_error(vpro:::vpro_pg_vp08_specs("BadSuffix"), "Unknown VP08")

  for (stbl in c(
    "usys_all_specs", "usys_table_of_lists", "bec_site_series",
    "master_site_unit_list", "usys_zone_list", "usys_spp_attributes", "project_metadata"
  )) {
    sp <- vpro:::vpro_pg_standards_specs(stbl)
    expect_gt(nrow(sp), 2L)
  }
  expect_error(vpro:::vpro_pg_standards_specs(""), "table")
  expect_error(vpro:::vpro_pg_standards_specs("bad_std"), "Unknown standards")

  # DDL builders with and without PostGIS
  stmts_plain <- vpro:::vpro_pg_build_v1_migration_stmts(has_postgis = FALSE)
  stmts_pgis <- vpro:::vpro_pg_build_v1_migration_stmts(has_postgis = TRUE, postgis_schema = "postgis")
  expect_gt(length(stmts_pgis), length(stmts_plain))
  expect_true(any(grepl('"postgis"\\.ST_MakePoint', stmts_pgis)))
  expect_true(any(grepl("CREATE TABLE IF NOT EXISTS becmaster\\.\"env\"", stmts_plain)))
  expect_true(any(grepl("CREATE TABLE IF NOT EXISTS staging\\.submissions", stmts_plain)))
  expect_true(any(grepl("CREATE TABLE IF NOT EXISTS standards\\.\"usys_all_specs\"", stmts_plain)))

  # Bidirectional canonicalizers & edge cases
  ts_vec <- as.POSIXct(c("2026-07-01 00:00:00", "2026-07-01 14:30:05"), tz = "UTC")
  expect_equal(
    vpro:::vpro_pg_format_utc_text(ts_vec, "Date"),
    c("2026-07-01", "2026-07-01 14:30:05")
  )
  expect_equal(
    vpro:::vpro_pg_format_utc_text(as.Date(c("2026-07-01", NA)), "Date"),
    c("2026-07-01", NA_character_)
  )
  expect_equal(
    vpro:::vpro_pg_format_utc_text(list(charToRaw("ABC"), NULL, "XYZ"), "Notes"),
    c("ABC", NA_character_, "XYZ")
  )
  expect_error(
    vpro:::vpro_pg_format_utc_text(list(as.raw(c(65L, 0L, 66L))), "Notes"),
    "NUL"
  )

  veg_spec <- vpro:::vpro_pg_vp08_specs("Veg")
  env_spec <- vpro:::vpro_pg_vp08_specs("Env")
  expect_error(
    vpro:::vpro_pg_canonicalize_to_pg(data.frame(PlotNumber = "12345678"), env_spec),
    "maximum length of 7"
  )
  expect_error(
    vpro:::vpro_pg_canonicalize_to_pg(data.frame(PlotNumber = "00337", Elevation = 5e9), env_spec),
    "32-bit R integer"
  )
  expect_error(
    vpro:::vpro_pg_canonicalize_to_pg(data.frame(PlotNumber = "00337", Flag = "not_bool"), env_spec),
    "boolean"
  )
  expect_error(
    vpro:::vpro_pg_canonicalize_to_pg(data.frame(PlotNumber = "00337", Species = "PINUCON", Cover1 = 99.999999), veg_spec),
    "strictly under 100%"
  )
  expect_error(
    vpro:::vpro_pg_canonicalize_to_pg(data.frame(PlotNumber = "00337", Species = "PINUCON", Cover1 = -1), veg_spec),
    ">= 0"
  )

  # Merge cell & LMH25 horizon validators
  sp_col <- veg_spec[veg_spec$name == "Species", , drop = FALSE]
  c1_col <- veg_spec[veg_spec$name == "Cover1", , drop = FALSE]
  expect_silent(vpro:::vpro_validate_merge_cell_value("Veg", sp_col, "PINUCON", plot = "00337"))
  expect_error(vpro:::vpro_validate_merge_cell_value("Veg", sp_col, "TOOLONGSPP", plot = "00337"), "exceeds 8")
  expect_silent(vpro:::vpro_validate_merge_cell_value("Veg", c1_col, 99.999996, plot = "00337"))
  expect_error(vpro:::vpro_validate_merge_cell_value("Veg", c1_col, 99.999999, plot = "00337"), "strictly under 100%")

  expect_silent(vpro:::vpro_validate_lmh25_merge_horizon("Humus", "Fm", 6, 0, plot = "00337"))
  expect_error(vpro:::vpro_validate_lmh25_merge_horizon("Humus", "Fm", 0, 6, plot = "00337"), "upland Humus")
  expect_silent(vpro:::vpro_validate_lmh25_merge_horizon("Humus", "2Of", 0, 20, plot = "00337"))
  expect_error(vpro:::vpro_validate_lmh25_merge_horizon("Humus", "Of", 20, 0, plot = "00337"), "wetland Humus")
  expect_silent(vpro:::vpro_validate_lmh25_merge_horizon("Mineral", "Bm1", 0, 30, plot = "00337"))
  expect_error(vpro:::vpro_validate_lmh25_merge_horizon("Mineral", "Bm1", 30, 0, plot = "00337"), "Mineral")
  expect_error(vpro:::vpro_validate_lmh25_merge_horizon("Mineral", "Bm1", -2, 30, plot = "00337"), ">= 0 cm")

  # Child ID repair & connection validation guards
  expect_equal(vpro:::vpro_repair_staging_child_ids(c(10L, 10L, NA_integer_, 25L)), c(10L, 100000000L, 100000001L, 25L))
  expect_false(vpro_master_disconnect(NULL))
  expect_error(vpro_master_disconnect(list()), "vpro_pg_conn")
  expect_error(vpro_master_connect(role = "contributor", bootstrap = TRUE), "custodian")
  expect_error(vpro_master_connect(role = "custodian", bootstrap = NA), "TRUE")
})

test_that("vpro_master_bootstrap, vpro_master_status, cloud readers, standards sync, pull, and workspace succeed offline", {
  cl <- new_mock_pg_cluster(has_postgis = TRUE)
  on.exit(cl$close(), add = TRUE)

  # Pre-bootstrap status check
  st0 <- vpro_master_status(cl$custodian)
  expect_s3_class(st0, "vpro_pg_status")
  expect_false(st0$schemas_bootstrapped)
  expect_no_error(capture.output(print(st0), type = "message"))
  expect_s3_class(tibble::as_tibble(st0), "tbl_df")

  # Bootstrap validation guards
  expect_error(vpro_master_bootstrap(cl$contributor), "custodian")
  expect_error(
    vpro_master_bootstrap(cl$custodian, contributor_role = "same_role", custodian_role = "same_role"),
    "distinct"
  )

  # Execute full schema bootstrap with contributor & custodian role grants + RLS
  boot1 <- vpro_master_bootstrap(
    cl$custodian,
    contributor_role = "bec_contributor",
    custodian_role = "bec_custodian"
  )
  expect_equal(boot1$schema_version, 1L)
  expect_equal(boot1$created_schemas, c("becmaster", "staging", "standards"))
  expect_gt(length(boot1$created_tables), 15L)
  expect_equal(boot1$applied_migrations, "1:v1_becmaster_staging_standards")
  expect_true(boot1$postgis_enabled)
  expect_true(boot1$role_grants_applied)
  expect_true(boot1$contributor_role_set)

  # Re-running bootstrap is idempotent
  boot2 <- vpro_master_bootstrap(cl$custodian)
  expect_length(boot2$created_schemas, 0L)
  expect_length(boot2$created_tables, 0L)
  expect_length(boot2$applied_migrations, 0L)

  # Seed standards & becmaster data
  expected_vlists_sha <- seed_mock_becmaster(cl$sqlite)

  # Post-bootstrap status & print.vpro_pg_conn
  st1 <- vpro_master_status(cl$custodian)
  expect_true(st1$schemas_bootstrapped)
  expect_equal(st1$becmaster_plots, 3L)
  expect_equal(st1$becmaster_veg, 7L)
  expect_equal(st1$standards_release, "STD_2026_11")
  expect_no_error(capture.output(print(st1), type = "message"))
  expect_no_error(capture.output(print(cl$custodian), type = "message"))

  # vpro_master_standards across releases and all 6 catalogue tables
  rel_tbl <- vpro_master_standards(cl$contributor, table = "releases")
  expect_equal(nrow(rel_tbl), 1L)
  expect_equal(rel_tbl$release_id[[1L]], "STD_2026_11")
  expect_true(rel_tbl$is_current[[1L]])
  expect_gt(rel_tbl$vlists_gzip_bytes[[1L]], 1000L)

  for (stbl in c(
    "usys_all_specs", "usys_table_of_lists", "bec_site_series",
    "master_site_unit_list", "usys_zone_list", "project_metadata"
  )) {
    cat_df <- vpro_master_standards(cl$contributor, table = stbl)
    expect_s3_class(cat_df, "tbl_df")
    expect_gt(nrow(cat_df), 0L)
  }

  # vpro_master_standards_sync: gzip download, already_current short-circuit, and relational rebuild fallback
  sync_dir <- tempfile("vpro-std-sync-")
  dir.create(sync_dir)
  on.exit(unlink(sync_dir, recursive = TRUE, force = TRUE), add = TRUE)

  s_res1 <- vpro_master_standards_sync(cl$contributor, data_dir = sync_dir)
  expect_true(s_res1$updated)
  expect_false(s_res1$already_current)
  expect_equal(s_res1$local_sha256, expected_vlists_sha)
  expect_true(file.exists(s_res1$vlists_path))

  s_res2 <- vpro_master_standards_sync(cl$contributor, data_dir = sync_dir)
  expect_false(s_res2$updated)
  expect_true(s_res2$already_current)

  # Relational rebuild branch when vlists_gzip is NULL
  DBI::dbExecute(cl$sqlite, "UPDATE standards.library_releases SET vlists_gzip = NULL, vlists_sha256 = 'rebuild_sha'")
  sync_dir_rel <- tempfile("vpro-std-rebuild-")
  dir.create(sync_dir_rel)
  on.exit(unlink(sync_dir_rel, recursive = TRUE, force = TRUE), add = TRUE)
  s_res_rel <- vpro_master_standards_sync(cl$contributor, data_dir = sync_dir_rel)
  expect_true(s_res_rel$updated)
  expect_true(file.exists(s_res_rel$vlists_path))

  # vpro_master_env: Custodian sees exact coordinates; Contributor gets ~10 km redaction on '01001'
  expect_error(vpro_master_env(cl$contributor), "subset filter")
  expect_error(vpro_master_env(cl$contributor, plots = 337), "character")

  env_cust <- vpro_master_env(cl$custodian, allow_full = TRUE)
  expect_equal(env_cust$PlotNumber, c("00337", "01001", "01002"))
  expect_equal(env_cust$Latitude[env_cust$PlotNumber == "01001"], 49.6543, tolerance = 1e-6)

  env_contrib <- vpro_master_env(
    cl$contributor,
    zones = c("SBS", "CWH"),
    bbox = c(-130, 48, -120, 56)
  )
  expect_equal(env_contrib$PlotNumber, c("00337", "01001", "01002"))
  # Sensitive plot '01001' truncated to 0.1 deg / 10,000 m while '00337' stays exact!
  expect_equal(env_contrib$Latitude[env_contrib$PlotNumber == "01001"], 49.6, tolerance = 1e-6)
  expect_equal(env_contrib$Longitude[env_contrib$PlotNumber == "01001"], -125.4, tolerance = 1e-6)
  expect_equal(env_contrib$UTMEasting[env_contrib$PlotNumber == "01001"], 320000, tolerance = 1e-6)
  expect_equal(env_contrib$Latitude[env_contrib$PlotNumber == "00337"], 54.7804, tolerance = 1e-6)

  env_no_adm <- vpro_master_env(cl$contributor, plots = "00337", include_admin = FALSE, columns = c("Zone", "Elevation"))
  expect_equal(env_no_adm$PlotNumber, "00337")
  expect_true(is.na(env_no_adm$SiteUnit))

  # vpro_master_veg across strata modes and 99% lump cap (60 + 55 = 115 -> 99)
  lump_df <- data.frame(
    SppCode = c("POA PRA2", "POA SEC"),
    LumpCode = c("POASPP", "POASPP"),
    Use = c(TRUE, TRUE),
    stringsAsFactors = FALSE
  )
  veg_raw_lump <- vpro_master_veg(cl$contributor, plots = "00337", strata = "raw", lump = lump_df)
  expect_equal(veg_raw_lump$Cover[veg_raw_lump$Species == "POASPP" & veg_raw_lump$Layer == "6"], 99.0)

  veg_tot <- vpro_master_veg(cl$contributor, zones = "CWH", strata = "total", combine = "sum")
  expect_gt(nrow(veg_tot), 0L)
  veg_abcd <- vpro_master_veg(cl$contributor, zones = "CWH", strata = "abcd")
  expect_true(all(veg_abcd$Strata %in% c("A", "B", "C", "D")))
  veg_lf <- vpro_master_veg(cl$contributor, zones = "CWH", strata = "lifeform")
  expect_s3_class(veg_lf, "tbl_df")
  veg_empty <- vpro_master_veg(cl$contributor, plots = "NO_SUCH_PLOT", strata = "raw")
  expect_equal(nrow(veg_empty), 0L)

  # vpro_master_soil across both, humus, mineral, and empty result
  soil_all <- vpro_master_soil(cl$contributor, plots = c("00337", "01001"), type = "both")
  expect_s3_class(soil_all, "vpro_soil")
  expect_equal(soil_all$humus$Horizon[soil_all$humus$PlotNumber == "00337"], c("L", "Fm"))
  expect_equal(nrow(vpro_master_soil(cl$contributor, plots = "00337", type = "mineral")), 1L)
  expect_equal(nrow(vpro_master_soil(cl$contributor, plots = "NONE", type = "humus")), 0L)

  # vpro_master_audit + cryptographic chain verification (full & bounded partial window)
  aud_res <- vpro_master_audit(cl$contributor, zones = "SBS", plots = "00337", verify_chain = TRUE)
  expect_equal(nrow(aud_res), 1L)
  expect_true(attr(aud_res, "chain_verification")$valid)
  expect_equal(attr(aud_res, "chain_verification")$verified_rows, 2L)

  partial_ver <- vpro:::.vpro_master_verify_audit(cl$contributor, limit = 1L)
  expect_true(partial_ver$valid)
  expect_true(partial_ver$partial_window)

  # vpro_master_pull -> local WAL VP08 .db + download_log entry
  pull_dir <- tempfile("vpro-pull-")
  dir.create(pull_dir)
  on.exit(unlink(pull_dir, recursive = TRUE, force = TRUE), add = TRUE)
  pull_db <- file.path(pull_dir, "SubCheckout.db")

  pulled <- vpro_master_pull(
    cl$contributor,
    dest_db = pull_db,
    project = "SubCheckout",
    zones = c("SBS", "CWH")
  )
  expect_equal(pulled$plot_count, 3L)
  expect_equal(pulled$download_log_id, 1L)
  expect_true(vpro_project_inspect(pulled$dest_path, "SubCheckout")$compatible)
  # Contributor pull generalized sensitive plot '01001' while keeping '00337' exact
  pulled_env <- vpro_env(pulled$workspace, scope = "project")
  expect_equal(pulled_env$Latitude[pulled_env$PlotNumber == "01001"], 49.6, tolerance = 1e-6)
  expect_equal(pulled_env$Latitude[pulled_env$PlotNumber == "00337"], 54.7804, tolerance = 1e-6)
  # Active WAL sidecar guard & overwrite = FALSE guard
  writeLines("lock", paste0(pull_db, "-wal"))
  expect_error(
    vpro_master_pull(cl$contributor, dest_db = pull_db, project = "SubCheckout", zones = "SBS", overwrite = TRUE),
    "open in another VPro"
  )
  unlink(c(paste0(pull_db, "-wal"), paste0(pull_db, "-shm")), force = TRUE)
  expect_error(
    vpro_master_pull(cl$contributor, dest_db = pull_db, project = "SubCheckout", zones = "SBS", overwrite = FALSE),
    "overwrite = TRUE"
  )

  # vpro_master_workspace -> ephemeral cloud_workspace feeding vpro_matrix()
  ws_cloud <- vpro_master_workspace(cl$custodian, zones = c("SBS", "CWH"), unit_col = "SiteSeries")
  expect_s3_class(ws_cloud, "vpro_workspace")
  expect_equal(ws_cloud$source, "cloud_workspace")
  mat_cloud <- vpro_matrix(ws_cloud, transform = "sqrt")
  expect_equal(nrow(mat_cloud), 3L)
  expect_true("00337" %in% rownames(mat_cloud))
  ws_cloud_def <- vpro_master_workspace(cl$contributor, plots = "00337")
  expect_equal(nrow(vpro_env(ws_cloud_def, scope = "project")), 1L)
})

test_that("end-to-end staging submit, queue inspect, custodian 3-way merge, audit chain, reject, and multi-format snapshots succeed offline", {
  cl <- new_mock_pg_cluster(has_postgis = FALSE)
  on.exit(cl$close(), add = TRUE)
  vpro_master_bootstrap(cl$custodian)
  seed_mock_becmaster(cl$sqlite)

  work_root <- tempfile("vpro-sync-e2e-")
  dir.create(work_root)
  on.exit(unlink(work_root, recursive = TRUE, force = TRUE), add = TRUE)

  # 1. Custodian pulls clean baseline checkout BaseSync.db
  base_db <- file.path(work_root, "BaseSync.db")
  vpro_master_pull(cl$custodian, dest_db = base_db, project = "BaseSync", allow_full = TRUE)

  # 2. Contributor prepares working copy CrewSync.db + custom VUser.db
  crew_dir <- file.path(work_root, "crew")
  dir.create(crew_dir)
  crew_db <- file.path(crew_dir, "CrewSync.db")
  file.copy(base_db, crew_db)
  file.copy(vpro:::vpro_bundled_db("VLists.db"), file.path(crew_dir, "VLists.db"))
  file.copy(vpro:::vpro_bundled_db("VUser.db"), file.path(crew_dir, "VUser.db"))

  dbu <- DBI::dbConnect(RSQLite::SQLite(), file.path(crew_dir, "VUser.db"))
  DBI::dbExecute(
    dbu,
    paste(
      'INSERT OR REPLACE INTO "USysUserSpp" ("Code", "ScientificName", "LifeForm", "EnglishName", "Report", "SppNumber", "Codetype") VALUES',
      "('RQASPP1', 'Carex rsdkiana', 6, 'R SDK sedge', 1, 101, 'U'),",
      "('PINUCON', 'Pinus contorta', 1, 'Lodgepole pine', 1, 102, 'U'),",
      "('THUIABI', 'Abies amabilis syn', 1, 'Synonym fir', 1, 103, 'S')"
    )
  )
  DBI::dbDisconnect(dbu)

  dbw <- DBI::dbConnect(RSQLite::SQLite(), crew_db)
  for (sfx in c("Env", "Admin", "Veg", "Humus", "Mineral", "Other", "Audit", "Metadata", "SU")) {
    old_t <- paste0("BaseSync_", sfx)
    new_t <- paste0("CrewSync_", sfx)
    if (DBI::dbExistsTable(dbw, old_t)) {
      DBI::dbExecute(dbw, sprintf('ALTER TABLE "%s" RENAME TO "%s"', old_t, new_t))
    }
  }
  DBI::dbExecute(dbw, 'UPDATE "_table_metadata" SET "table_name" = REPLACE("table_name", \'BaseSync_\', \'CrewSync_\')')
  DBI::dbExecute(dbw, 'CREATE TABLE "CrewSync_Lump" ("LumpCode" TEXT, "SppCode" TEXT, "Use" SMALLINT)')
  DBI::dbExecute(dbw, "INSERT INTO \"CrewSync_Lump\" VALUES ('POASPP', 'POA PRA2', -1)")

  # Verify Sample refusal & float32 >= 100 pre-flight compliance gate
  expect_error(vpro_staging_submit(cl$contributor, vpro_connect("Sample"), submitter = "QA"), "Sample")
  DBI::dbExecute(
    dbw,
    'INSERT INTO "CrewSync_Veg" ("PlotNumber", "Species", "Layer", "Cover1", "Flag", "ID") VALUES (\'00337\', \'THUIABI\', \'1\', 99.999999, 0, 5001)'
  )
  DBI::dbDisconnect(dbw)

  ws_crew <- vpro_connect(crew_db, su = "CrewSync_SU", lump = "CrewSync_Lump", data_dir = crew_dir, config_dir = work_root)
  expect_error(vpro_staging_submit(cl$contributor, ws_crew, submitter = "Field Crew"), "compliance gate")

  # Fix cover on 5001, fast-forward '00337' SiteNotes & Cover1, edit protected BECSiteUnit on '01001',
  # create conflict on '01002' SiteNotes + delete '01002' ABIELAS (ID 107) + update '00337' Humus Fm UpperDepth,
  # and add new leading-zero plot '00338' + new ProjectID 'CREW_2026'
  dbw <- DBI::dbConnect(RSQLite::SQLite(), crew_db)
  DBI::dbExecute(dbw, 'UPDATE "CrewSync_Veg" SET "Cover1" = 12.5 WHERE "ID" = 5001')
  DBI::dbExecute(dbw, 'UPDATE "CrewSync_Env" SET "SiteNotes" = \'Crew FastForward 00337\' WHERE "PlotNumber" = \'00337\'')
  DBI::dbExecute(dbw, 'UPDATE "CrewSync_Veg" SET "Cover1" = 50.0 WHERE "PlotNumber" = \'00337\' AND "Species" = \'PINUCON\'')
  DBI::dbExecute(dbw, 'UPDATE "CrewSync_Humus" SET "UpperDepth" = 9.5 WHERE "PlotNumber" = \'00337\' AND "Horizon" = \'L\'')
  DBI::dbExecute(dbw, 'UPDATE "CrewSync_Admin" SET "BECSiteUnit" = \'CWHvm1/99\' WHERE "Plot" = \'01001\'')
  DBI::dbExecute(dbw, 'UPDATE "CrewSync_Env" SET "SiteNotes" = \'Crew Conflict 01002\' WHERE "PlotNumber" = \'01002\'')
  DBI::dbExecute(dbw, 'DELETE FROM "CrewSync_Veg" WHERE "PlotNumber" = \'01002\' AND "Species" = \'ABIELAS\'')
  DBI::dbExecute(
    dbw,
    paste(
      'INSERT INTO "CrewSync_Env" ("PlotNumber", "ProjectID", "Zone", "SubZone", "SiteSeries", "MoistureRegime", "NutrientRegime", "Elevation", "Latitude", "Longitude", "SpeciesListComplete", "Flag")',
      "VALUES ('00338', 'CREW_2026', 'SBS', 'dk', '01', '4', 'C', 610, 54.81, -127.12, -1, 0)"
    )
  )
  DBI::dbExecute(
    dbw,
    paste(
      'INSERT INTO "CrewSync_Admin" ("Plot", "PlotType", "SitePlotQuality", "VegPlotQuality", "SoilPlotQuality", "UpdatedFromCards", "BECSiteUnit", "UserSiteUnit")',
      "VALUES ('00338', 'FS882', 'Good', 'Good', 'Good', -1, 'SBSdk/01', 'SBSdk/01')"
    )
  )
  DBI::dbExecute(
    dbw,
    'INSERT INTO "CrewSync_Veg" ("PlotNumber", "Species", "Layer", "Cover1", "Flag", "ID") VALUES (\'00338\', \'PINUCON\', \'1\', 38.0, 0, 5002)'
  )
  DBI::dbExecute(
    dbw,
    'INSERT INTO "CrewSync_Humus" ("PlotNumber", "Horizon", "UpperDepth", "LowerDepth", "Flag", "ID") VALUES (\'00338\', \'Fm\', 4.0, 0.0, 0, 5003)'
  )
  DBI::dbExecute(
    dbw,
    'INSERT INTO "CrewSync_Metadata" ("ProjectID", "ProjectTitle", "ID") VALUES (\'CREW_2026\', \'Crew 2026 Survey\', 5004)'
  )
  DBI::dbExecute(dbw, 'INSERT INTO "CrewSync_SU" ("PlotNumber", "SiteUnit") VALUES (\'00338\', \'SBSdk/01\')')
  DBI::dbDisconnect(dbw)

  # Simulate concurrent Custodian edit on becmaster.env '01002' so '01002' is a true 3-way conflict
  DBI::dbExecute(cl$sqlite, 'UPDATE becmaster."env" SET "SiteNotes" = \'Custodian Edit 01002\' WHERE "PlotNumber" = \'01002\'')

  # 3. Contributor submits CrewSync to staging
  sub1 <- vpro_staging_submit(
    cl$contributor,
    ws_crew,
    submitter = "Ecologist Jane",
    notes = "Field season 2026 upload",
    base_snapshot_tag = "BECMaster_2026_Base"
  )
  expect_equal(sub1$status, "pending")
  expect_equal(sub1$plot_count, 4L)
  expect_true(sub1$compliance_passed)
  expect_gte(sub1$user_species_count, 2L)

  # 4. Queue listing & submission inspection
  q_pending <- vpro_staging_list(cl$contributor, status = "pending", submitted_by = "Ecologist Jane")
  expect_s3_class(q_pending, "vpro_staging_queue")
  expect_equal(nrow(q_pending), 1L)
  expect_no_error(capture.output(suppressMessages(print(q_pending))))
  q_empty <- vpro_staging_list(cl$contributor, status = "approved")
  expect_no_error(capture.output(suppressMessages(print(q_empty))))

  insp <- vpro_staging_inspect(cl$custodian, sub1$submission_id)
  expect_equal(insp$summary$submission_id, sub1$submission_id)
  expect_true(all(c("new_provisional", "matches_official", "matches_synonym") %in% insp$provisional_diffs$status))
  expect_equal(nrow(insp$lump), 1L)
  expect_equal(nrow(insp$su), 4L)

  # 5. Custodian 3-way diff preview (with base_db as workspace and path)
  expect_error(vpro_staging_diff(cl$contributor, sub1$submission_id), "custodian")
  prev <- vpro_staging_diff(cl$custodian, sub1$submission_id, base_db = base_db, base_project = "BaseSync")
  expect_s3_class(prev, "vpro_merge_preview")
  expect_equal(prev$added_count, 1L)
  expect_equal(prev$fast_forward_count, 1L)
  expect_gte(prev$conflict_count, 2L)
  expect_no_error(capture.output(print(prev), type = "message"))
  expect_s3_class(tibble::as_tibble(prev, what = "items"), "tbl_df")
  expect_s3_class(tibble::as_tibble(prev, what = "plots"), "tbl_df")
  expect_s3_class(tibble::as_tibble(prev, what = "conflicts"), "tbl_df")
  expect_s3_class(tibble::as_tibble(prev, what = "custodian_protected"), "tbl_df")

  # 6. Optimistic digest mismatch rolls back cleanly
  expect_error(
    vpro_staging_merge(
      cl$custodian,
      sub1$submission_id,
      expected_digest = strrep("a", 64L),
      base_db = base_db,
      base_project = "BaseSync"
    ),
    "changed since preview"
  )

  # 7. Execute Custodian 3-way merge accepting '01002' source edits (including child delete!) while holding protected BECSiteUnit
  m_res <- vpro_staging_merge(
    cl$custodian,
    sub1$submission_id,
    default_resolution = "keep_target",
    plot_resolutions = c("01002" = "accept_source"),
    expected_digest = prev$preview_digest,
    reviewer_notes = "Merged 00338 + 00337 FF + 01002 crew edits; held BECSiteUnit",
    base_db = base_db,
    base_project = "BaseSync",
    actor = "Will MacKenzie"
  )
  expect_equal(m_res$added_plots, 1L)
  expect_equal(m_res$updated_plots, 2L)
  expect_true(107L %in% m_res$reserved_deleted_ids)
  expect_gt(length(m_res$allocated_child_ids), 0L)
  expect_true(all(m_res$allocated_child_ids > 107L))
  expect_gt(m_res$audit_rows_written, 5L)

  # Verify merged BECMaster state & unbroken SHA-256 audit chain!
  after_env <- vpro_master_env(cl$custodian, allow_full = TRUE)
  expect_true("00338" %in% after_env$PlotNumber)
  expect_equal(after_env$SiteNotes[after_env$PlotNumber == "00337"], "Crew FastForward 00337")
  expect_equal(after_env$SiteNotes[after_env$PlotNumber == "01002"], "Crew Conflict 01002")
  expect_equal(after_env$BECSiteUnit[after_env$PlotNumber == "01001"], "CWHvm1/01")

  aud_after <- vpro_master_audit(cl$custodian, limit = NULL, verify_chain = TRUE)
  ver_after <- attr(aud_after, "chain_verification")
  expect_true(ver_after$valid)
  expect_equal(ver_after$tail_hash, m_res$tail_audit_hash)

  # Verify audit tamper detection (row_hash & prev_hash breakage)
  orig_after <- DBI::dbGetQuery(cl$sqlite, "SELECT audit_seq, \"AfterEdit\", prev_hash FROM becmaster.audit ORDER BY audit_seq ASC")
  last_seq <- orig_after$audit_seq[[nrow(orig_after)]]
  DBI::dbExecute(cl$sqlite, 'UPDATE becmaster.audit SET "AfterEdit" = \'TAMPERED\' WHERE audit_seq = $1', params = list(last_seq))
  tampered_ver <- vpro:::.vpro_master_verify_audit(cl$custodian)
  expect_false(tampered_ver$valid)
  expect_match(tampered_ver$detail, "tampered")
  # Restore valid AfterEdit
  DBI::dbExecute(
    cl$sqlite,
    'UPDATE becmaster.audit SET "AfterEdit" = $1 WHERE audit_seq = $2',
    params = list(orig_after$AfterEdit[[nrow(orig_after)]], last_seq)
  )
  expect_true(vpro:::.vpro_master_verify_audit(cl$custodian)$valid)

  # 8. Submit a second staging bundle and test Custodian rejection
  sub2 <- vpro_staging_submit(cl$contributor, ws_crew, submitter = "Ecologist Jane", scope = "su")
  expect_error(vpro_staging_reject(cl$contributor, sub2$submission_id, "nope"), "custodian")
  rej <- vpro_staging_reject(cl$custodian, sub2$submission_id, reviewer_notes = "Duplicate upload", actor = "Will MacKenzie")
  expect_equal(rej$status[[1L]], "rejected")
  expect_error(vpro_staging_reject(cl$custodian, sub2$submission_id, reviewer_notes = "Again"), "not in.*pending")

  # 9. Publish multi-format snapshots (unredacted and redact_sensitive = TRUE) & list snapshots
  snap_fmts <- if (requireNamespace("sf", quietly = TRUE)) {
    c("rds", "sqlite", "gpkg", "csv")
  } else {
    c("rds", "sqlite", "csv")
  }
  snap_dir <- file.path(work_root, "snapshots")
  pub <- vpro_master_publish_snapshot(
    cl$custodian,
    snapshot_tag = "BECMaster_2026_11_Pub",
    out_dir = snap_dir,
    formats = snap_fmts,
    notes = "Offline test release",
    compress = "gzip",
    redact_sensitive = TRUE
  )
  expect_equal(pub$plot_count, 4L)
  expect_equal(nrow(pub$artifacts), length(snap_fmts))
  expect_true(all(file.exists(pub$artifacts$path)))
  expect_error(
    vpro_master_publish_snapshot(cl$custodian, "BECMaster_2026_11_Pub", snap_dir, formats = "rds", overwrite = FALSE),
    "overwrite = TRUE"
  )

  # Verify redacted CSV & RDS snapshot artifacts generalized '01001' while keeping '00337' exact
  rds_snap_ws <- vpro_import_rds(pub$artifacts$path[pub$artifacts$format == "rds"][[1L]])
  rds_snap_env <- vpro_env(rds_snap_ws, scope = "project")
  expect_equal(rds_snap_env$Latitude[rds_snap_env$PlotNumber == "01001"], 49.6, tolerance = 1e-6)
  expect_equal(rds_snap_env$Latitude[rds_snap_env$PlotNumber == "00337"], 54.7804, tolerance = 1e-6)

  snaps_list <- vpro_master_list_snapshots(cl$contributor)
  expect_equal(nrow(snaps_list), 1L)
  expect_equal(snaps_list$snapshot_tag[[1L]], "BECMaster_2026_11_Pub")

  # Disconnect mock handle cleanly
  expect_true(vpro_master_disconnect(cl$contributor))
  expect_false(vpro_master_disconnect(cl$contributor))
})
