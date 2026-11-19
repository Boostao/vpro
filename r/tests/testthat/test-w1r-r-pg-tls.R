test_that("vpro_resolve_pg_credentials enforces remote TLS across args, env, becmaster.env, and URIs (ENG-R-001)", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(
    VPRO_PG_URL = "",
    VPRO_PG_ADMIN_URL = "",
    VPRO_PG_HOST = "",
    VPRO_PG_PORT = "",
    VPRO_PG_DBNAME = "",
    VPRO_PG_USER = "",
    VPRO_PG_PASSWORD = "",
    VPRO_PG_ADMIN_USER = "",
    VPRO_PG_ADMIN_PASSWORD = "",
    VPRO_PG_SSLMODE = ""
  )

  # Exact replay of evidence/ENG-R-001/repro.R
  for (mode in c("disable", "allow", "prefer")) {
    expect_error(
      vpro:::vpro_resolve_pg_credentials(
        role = "contributor",
        host = "db.example.gov.bc.ca",
        user = "bec_contributor",
        password = "redacted",
        sslmode = mode,
        config_dir = cfg
      ),
      class = "vpro_pg_tls_required"
    )
    expect_error(
      vpro:::vpro_resolve_pg_credentials(
        role = "custodian",
        url = paste0("postgres://admin:secret@db.example.gov.bc.ca:5432/becmaster?sslmode=", mode),
        config_dir = cfg
      ),
      class = "vpro_pg_tls_required"
    )
  }

  for (mode in c("require", "verify-ca", "verify-full")) {
    creds <- vpro:::vpro_resolve_pg_credentials(
      role = "contributor",
      host = "db.example.gov.bc.ca",
      user = "bec_contributor",
      password = "redacted",
      sslmode = mode,
      config_dir = cfg
    )
    expect_equal(creds$sslmode, mode)
    expect_equal(creds$host, "db.example.gov.bc.ca")
  }

  # becmaster.env with remote plaintext sslmode is rejected by vpro_resolve_pg_credentials
  # and causes vpro_has_pg_credentials() to return FALSE cleanly without throwing
  writeLines(
    c(
      "VPRO_PG_HOST=db.example.gov.bc.ca",
      "VPRO_PG_USER=contrib_u",
      "VPRO_PG_PASSWORD=secret",
      "VPRO_PG_SSLMODE=allow"
    ),
    file.path(cfg, "becmaster.env")
  )
  expect_error(
    vpro:::vpro_resolve_pg_credentials("contributor", config_dir = cfg),
    class = "vpro_pg_tls_required"
  )
  expect_false(vpro_has_pg_credentials("contributor", config_dir = cfg))
})

test_that("libpq comma-separated multi-host strings require every component to be loopback or Unix socket", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(
    VPRO_PG_URL = "",
    VPRO_PG_ADMIN_URL = "",
    VPRO_PG_HOST = "",
    VPRO_PG_PORT = "",
    VPRO_PG_DBNAME = "",
    VPRO_PG_USER = "",
    VPRO_PG_PASSWORD = "",
    VPRO_PG_ADMIN_USER = "",
    VPRO_PG_ADMIN_PASSWORD = "",
    VPRO_PG_SSLMODE = ""
  )

  mixed_hosts <- c(
    "/tmp,db.example.gov.bc.ca",
    "/var/run/postgresql, 203.0.113.7",
    "127.0.0.1,db.example.gov.bc.ca",
    "db.example.gov.bc.ca,127.0.0.1",
    "[::1],db.example.gov.bc.ca",
    "localhost,10.0.0.5",
    "127.0.0.1,",
    ",127.0.0.1",
    ","
  )
  for (mh in mixed_hosts) {
    expect_false(vpro:::vpro_is_loopback_pg_host(mh), info = mh)
    for (mode in c("disable", "allow", "prefer")) {
      expect_error(
        vpro:::vpro_resolve_pg_credentials(
          role = "contributor",
          host = mh,
          user = "u",
          password = "p",
          sslmode = mode,
          config_dir = cfg
        ),
        class = "vpro_pg_tls_required",
        info = paste(mh, mode)
      )
      if (requireNamespace("RPostgres", quietly = TRUE)) {
        expect_error(
          vpro_master_connect(
            role = "contributor",
            host = mh,
            user = "u",
            password = "p",
            sslmode = mode,
            config_dir = cfg
          ),
          class = "vpro_pg_tls_required",
          info = paste(mh, mode)
        )
      }
    }
  }

  mixed_urls <- c(
    "postgres://u:p@127.0.0.1,db.example.gov.bc.ca/becmaster?sslmode=disable",
    "postgres://u:p@127.0.0.1:5432,db.example.gov.bc.ca:5432/becmaster?sslmode=prefer",
    "postgres://u:p@[::1]:5432,db.example.gov.bc.ca:5432/becmaster?sslmode=allow",
    "postgres://u:p@%2Ftmp,db.example.gov.bc.ca/becmaster?sslmode=disable",
    "postgres://u:p@127.0.0.1%2Cdb.example.gov.bc.ca/becmaster?sslmode=disable",
    "postgres://u:p@/becmaster?host=/tmp,db.example.gov.bc.ca&sslmode=disable",
    "postgres://u:p@127.0.0.1/becmaster?host=db.example.gov.bc.ca&sslmode=disable",
    "postgres://u:p@db.example.gov.bc.ca/becmaster?host=127.0.0.1&sslmode=disable",
    "postgres://u:p@127.0.0.1/becmaster?hostaddr=203.0.113.7&sslmode=disable"
  )
  for (u in mixed_urls) {
    expect_error(
      vpro:::vpro_resolve_pg_credentials("contributor", url = u, config_dir = cfg),
      class = "vpro_pg_tls_required",
      info = u
    )
    if (requireNamespace("RPostgres", quietly = TRUE)) {
      expect_error(
        vpro_master_connect("contributor", url = u, config_dir = cfg),
        class = "vpro_pg_tls_required",
        info = u
      )
    }
  }

  # All-loopback / all-Unix-socket multi-host configurations permit local non-TLS
  local_multi_hosts <- c(
    "127.0.0.1,localhost",
    "/var/run/postgresql,/tmp",
    "/tmp,127.0.0.1,[::1],[0:0:0:0:0:0:0:1],[::ffff:127.0.0.1]"
  )
  for (lh in local_multi_hosts) {
    expect_true(vpro:::vpro_is_loopback_pg_host(lh), info = lh)
    creds <- vpro:::vpro_resolve_pg_credentials(
      "contributor",
      host = lh,
      user = "u",
      password = "p",
      sslmode = "disable",
      config_dir = cfg
    )
    expect_equal(creds$sslmode, "disable")
  }

  local_multi_url <- "postgres://u:p@[::1]:5432,[0:0:0:0:0:0:0:1]:5432/becmaster?sslmode=disable"
  creds_local_url <- vpro:::vpro_resolve_pg_credentials("contributor", url = local_multi_url, config_dir = cfg)
  expect_equal(creds_local_url$host, "::1,0:0:0:0:0:0:0:1")
  expect_equal(creds_local_url$sslmode, "disable")

  remote_tls_url <- "postgres://u:p@db1.example.gov.bc.ca:5432,db2.example.gov.bc.ca:5432/becmaster?sslmode=verify-full"
  creds_remote_url <- vpro:::vpro_resolve_pg_credentials("contributor", url = remote_tls_url, config_dir = cfg)
  expect_equal(creds_remote_url$host, "db1.example.gov.bc.ca,db2.example.gov.bc.ca")
  expect_equal(creds_remote_url$sslmode, "verify-full")
})

test_that("loopback detector validates IPv4 0..255 octets and expanded/mapped IPv6 loopback forms", {
  valid_loopbacks <- c(
    "localhost",
    "LOCALHOST",
    "127.0.0.1",
    "127.0.0.0",
    "127.255.255.254",
    "127.1.2.3",
    "::1",
    "[::1]",
    "0:0:0:0:0:0:0:1",
    "[0:0:0:0:0:0:0:1]",
    "0000:0000:0000:0000:0000:0000:0000:0001",
    "::ffff:127.0.0.1",
    "[::ffff:127.0.0.1]",
    "::FFFF:127.255.255.254",
    "0:0:0:0:0:ffff:127.0.0.1",
    "/tmp",
    "/var/run/postgresql"
  )
  for (h in valid_loopbacks) {
    expect_true(vpro:::vpro_is_loopback_pg_host(h), info = h)
    expect_true(vpro:::vpro_require_pg_tls(h, "disable"), info = h)
  }

  invalid_or_remote <- c(
    "127.999.999.999",
    "127.0.0.256",
    "127.256.0.1",
    "127.0.1",
    "127.0.0.1.2",
    "127.010.0.1",
    "127.0.0.1.evil.example",
    "10.0.0.1",
    "192.168.1.1",
    "0.0.0.0",
    "::",
    "[::]",
    "::2",
    "::ffff:127.999.999.999",
    "::ffff:10.0.0.1",
    "::127.0.0.1",
    "0:0:0:0:0:0:ffff:127.0.0.1",
    "::1::1",
    "2001:db8::1",
    "fe80::1",
    "[[::1]]",
    "[/tmp]",
    "[localhost]",
    "db.example.gov.bc.ca"
  )
  for (h in invalid_or_remote) {
    expect_false(vpro:::vpro_is_loopback_pg_host(h), info = h)
    expect_error(
      vpro:::vpro_require_pg_tls(h, "disable"),
      class = "vpro_pg_tls_required",
      info = h
    )
  }

  expect_equal(vpro:::vpro_libpq_host("[::1]"), "::1")
  expect_equal(
    vpro:::vpro_libpq_host("[::1], [0:0:0:0:0:0:0:1], [::ffff:127.0.0.1]"),
    "::1,0:0:0:0:0:0:0:1,::ffff:127.0.0.1"
  )
})

test_that("live PostgreSQL test opt-in aliases and non-test database refusal match ENG-GO-003", {
  withr::local_envvar(
    VPRO_RUN_LIVE_PG_TESTS = "",
    VPRO_RUN_PG_TESTS = "",
    VPRO_LIVE_PG_TEST = "",
    VPRO_LIVE_PG = "",
    VPRO_LIVE_PG_DESTRUCTIVE_DB = ""
  )

  expect_false(vpro:::vpro_live_pg_tests_enabled())

  for (var_name in c("VPRO_RUN_LIVE_PG_TESTS", "VPRO_RUN_PG_TESTS", "VPRO_LIVE_PG_TEST", "VPRO_LIVE_PG")) {
    for (truthy in c("1", "true", "TRUE")) {
      env_list <- stats::setNames(list(truthy), var_name)
      withr::with_envvar(env_list, {
        expect_true(vpro:::vpro_live_pg_tests_enabled(), info = paste(var_name, truthy))
      })
    }
    for (falsy in c("", "0", "false", "no")) {
      env_list <- stats::setNames(list(falsy), var_name)
      withr::with_envvar(env_list, {
        expect_false(vpro:::vpro_live_pg_tests_enabled(), info = paste(var_name, falsy))
      })
    }
  }

  # Production / non-test database names MUST be refused even when confirmed_db matches!
  forbidden_dbs <- c(
    "becmaster",
    "BECMaster",
    "postgres",
    "template0",
    "template1",
    "defaultdb",
    "becmaster_fixing",
    "becmaster_v13",
    "becmaster_latest",
    "becmaster_prod",
    "becmaster_prod_test",
    ""
  )
  for (bad_db in forbidden_dbs) {
    expect_false(vpro:::vpro_is_disposable_pg_test_dbname(bad_db), info = bad_db)
    expect_error(
      vpro:::vpro_require_disposable_pg_test_db(
        dbname = bad_db,
        confirmed_db = bad_db,
        contrib_dbname = bad_db
      ),
      class = "vpro_pg_destructive_db_refused",
      info = bad_db
    )
  }

  # Valid test/scratch databases pass ONLY when confirmation and contributor/custodian dbnames match
  allowed_dbs <- c(
    "becmaster_test",
    "test_becmaster",
    "becmaster_qa",
    "becmaster_tmp",
    "becmaster_scratch",
    "becmaster_disposable",
    "vpro-qa-01"
  )
  for (ok_db in allowed_dbs) {
    expect_true(vpro:::vpro_is_disposable_pg_test_dbname(ok_db), info = ok_db)
    expect_true(
      vpro:::vpro_require_disposable_pg_test_db(
        dbname = ok_db,
        confirmed_db = ok_db,
        contrib_dbname = ok_db
      ),
      info = ok_db
    )
    expect_error(
      vpro:::vpro_require_disposable_pg_test_db(
        dbname = ok_db,
        confirmed_db = "",
        contrib_dbname = ok_db
      ),
      class = "vpro_pg_destructive_db_refused",
      info = ok_db
    )
    expect_error(
      vpro:::vpro_require_disposable_pg_test_db(
        dbname = ok_db,
        confirmed_db = "other_test",
        contrib_dbname = ok_db
      ),
      class = "vpro_pg_destructive_db_refused",
      info = ok_db
    )
    expect_error(
      vpro:::vpro_require_disposable_pg_test_db(
        dbname = ok_db,
        confirmed_db = ok_db,
        contrib_dbname = "becmaster"
      ),
      class = "vpro_pg_destructive_db_refused",
      info = ok_db
    )
  }
})

test_that("populated becmaster.env never triggers TCP connections without opt-in or against 'becmaster'", {
  # Bind an ephemeral local TCP listener to verify 0 incoming socket connections
  srv <- NULL
  bound_port <- NA_integer_
  for (cand_port in sample(39000L:49000L, 25L)) {
    srv <- tryCatch(serverSocket(cand_port), error = function(e) NULL)
    if (!is.null(srv)) {
      bound_port <- cand_port
      break
    }
  }
  skip_if(is.null(srv), "Could not bind ephemeral local serverSocket")
  on.exit(close(srv), add = TRUE)

  cfg <- withr::local_tempdir()
  writeLines(
    c(
      "VPRO_PG_HOST=127.0.0.1",
      paste0("VPRO_PG_PORT=", bound_port),
      "VPRO_PG_DBNAME=becmaster",
      "VPRO_PG_SSLMODE=disable",
      "VPRO_PG_USER=contrib_u",
      "VPRO_PG_PASSWORD=contrib_p",
      "VPRO_PG_ADMIN_USER=admin_u",
      "VPRO_PG_ADMIN_PASSWORD=admin_p"
    ),
    file.path(cfg, "becmaster.env")
  )

  withr::local_options(vpro.config_dir = cfg)
  withr::local_envvar(
    VPRO_CONFIG_DIR = cfg,
    VPRO_PG_URL = "",
    VPRO_PG_ADMIN_URL = "",
    VPRO_PG_HOST = "",
    VPRO_PG_PORT = "",
    VPRO_PG_DBNAME = "",
    VPRO_PG_USER = "",
    VPRO_PG_PASSWORD = "",
    VPRO_PG_ADMIN_USER = "",
    VPRO_PG_ADMIN_PASSWORD = "",
    VPRO_PG_SSLMODE = "",
    VPRO_RUN_LIVE_PG_TESTS = "",
    VPRO_RUN_PG_TESTS = "",
    VPRO_LIVE_PG_TEST = "",
    VPRO_LIVE_PG = "",
    VPRO_LIVE_PG_DESTRUCTIVE_DB = ""
  )

  # 1. Opt-in unset -> skipped with 0 TCP connections
  expect_false(vpro:::vpro_live_pg_tests_enabled())
  expect_false(socketSelect(list(srv), FALSE, timeout = 0.02))

  # 2. VPRO_RUN_PG_TESTS=true + VPRO_LIVE_PG_DESTRUCTIVE_DB=becmaster -> refused before connecting (0 TCP connections)
  withr::with_envvar(
    c(
      VPRO_RUN_PG_TESTS = "true",
      VPRO_LIVE_PG_DESTRUCTIVE_DB = "becmaster"
    ),
    {
      expect_true(vpro:::vpro_live_pg_tests_enabled())
      admin_creds <- vpro:::vpro_resolve_pg_credentials("custodian")
      contrib_creds <- vpro:::vpro_resolve_pg_credentials("contributor")
      expect_error(
        vpro:::vpro_require_disposable_pg_test_db(
          dbname = admin_creds$dbname,
          confirmed_db = Sys.getenv("VPRO_LIVE_PG_DESTRUCTIVE_DB"),
          contrib_dbname = contrib_creds$dbname
        ),
        class = "vpro_pg_destructive_db_refused"
      )
      expect_false(socketSelect(list(srv), FALSE, timeout = 0.02))
    }
  )
})
