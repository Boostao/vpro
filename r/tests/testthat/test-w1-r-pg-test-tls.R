test_that("vpro_master_connect refuses plaintext sslmodes for remote hosts before connecting (ENG-R-001)", {
  skip_if_not_installed("RPostgres")
  cfg <- withr::local_tempdir()
  withr::local_envvar(
    VPRO_PG_URL = "", VPRO_PG_ADMIN_URL = "", VPRO_PG_HOST = "", VPRO_PG_USER = "",
    VPRO_PG_PASSWORD = "", VPRO_PG_SSLMODE = ""
  )
  for (mode in c("disable", "allow", "prefer")) {
    expect_error(
      vpro_master_connect("contributor", host = "db.example.gov.bc.ca", user = "u", password = "p",
        sslmode = mode, config_dir = cfg),
      class = "vpro_pg_tls_required"
    )
    expect_error(
      vpro_master_connect("contributor", url = paste0("postgres://u:p@203.0.113.7:5432/becmaster?sslmode=", mode),
        config_dir = cfg),
      class = "vpro_pg_tls_required"
    )
  }
})

test_that("loopback hosts and TLS modes pass the TLS guard", {
  for (h in c("127.0.0.1", "localhost", "::1", "[::1]", "/var/run/postgresql", "")) {
    expect_true(vpro_require_pg_tls(h, "disable"))
  }
  for (mode in c("require", "verify-ca", "verify-full")) {
    expect_true(vpro_require_pg_tls("db.example.gov.bc.ca", mode))
  }
  expect_false(vpro_is_loopback_pg_host("127.0.0.1.evil.example"))
  expect_false(vpro_is_loopback_pg_host("10.0.0.5"))
})
