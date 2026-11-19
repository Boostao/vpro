# Wave 5 (ENG-R-009): Monolith decomposition, zero <<- / stop(), vpro_use()
# non-partial-matching, and standardized vpro_error condition classes

test_that("vpro_use('None') preserves NULL list slots without $ partial matching", {
  scratch <- withr::local_tempdir()
  ws <- vpro_connect("Sample", data_dir = scratch, config_dir = scratch)
  expect_equal(ws$su, "Sample_SU")
  expect_equal(ws$hierarchy, "Sample_Hierarchy")
  expect_equal(ws$lump, "Sample_Lump")

  ws_none <- vpro_use(ws, su = "None", hierarchy = "None", lump = "None")
  expect_true(all(c("su", "su_path", "hierarchy", "hierarchy_path", "lump", "lump_path") %in% names(ws_none)))
  expect_null(ws_none[["su"]])
  expect_null(ws_none$su)
  expect_null(ws_none[["hierarchy"]])
  expect_null(ws_none$hierarchy)
  expect_null(ws_none[["lump"]])
  expect_null(ws_none$lump)
  expect_type(ws_none$su_path, "character")
  expect_type(ws_none$hierarchy_path, "character")
  expect_type(ws_none$lump_path, "character")
  expect_no_error(capture.output(print(ws_none), type = "message"))
})

test_that("error conditions across domains inherit from vpro_error_<domain> and vpro_error", {
  expect_vpro_err <- function(expr, subclass, pattern = NULL) {
    cnd <- expect_error(expr, regexp = pattern, class = "vpro_error")
    expect_s3_class(cnd, subclass)
    expect_s3_class(cnd, "vpro_error")
    invisible(cnd)
  }

  # Domain & value helpers (previously base stop() or unclassed rlang::abort())
  expect_vpro_err(vpro_narrow_float32("bad"), "vpro_error_domain", "numeric vector")
  expect_vpro_err(vpro_round_ace(1.5, digits = -1L), "vpro_error_domain", "non-negative integer")
  expect_vpro_err(vpro_presence_class(numeric(0)), "vpro_error_domain", "nonempty numeric")
  expect_vpro_err(vpro_prominence_class(c(10, 20), c(0.2, 0.4, 0.6)), "vpro_error_domain", "common length")
  expect_vpro_err(vpro_prominence_class(10, 0.5, return_score = NA), "vpro_error_domain", "TRUE or FALSE")
  expect_vpro_err(vpro_classify_diagnostic_codes(c("5 - 5")), "vpro_error_domain", "named character")
  expect_vpro_err(vpro_classify_diagnostic_codes(c(U1 = "9 - 9")), "vpro_error_domain", "1 - \\+")

  # Dynamic strings containing literal { } braces never crash cli::cli_abort()
  brace_path <- file.path(tempdir(), "missing-{plot}-db}.sqlite")
  expect_vpro_err(vpro_project_inspect(brace_path), "vpro_error_workspace", "does not exist")
  expect_vpro_err(vpro:::vpro_sqlite_ro(brace_path), "vpro_error_domain", "does not exist")

  scratch <- withr::local_tempdir()
  ws <- vpro_connect("Sample", data_dir = scratch, config_dir = scratch)

  expect_vpro_err(vpro_use(ws, su = "NoSuch_{SU}"), "vpro_error_workspace", "not found")
  expect_vpro_err(vpro_filter_plots(ws, site_min = "Bad{Level}"), "vpro_error_read", "DataQuality")
  expect_vpro_err(vpro_veg(ws, lump = data.frame(A = 1)), "vpro_error_taxonomy", "SppCode")
  expect_vpro_err(vpro_matrix(ws, sparse = NA), "vpro_error_analysis", "TRUE or FALSE")
  expect_vpro_err(vpro_cluster(ws, k = 1L), "vpro_error_analysis", "integer >= 2")
  expect_vpro_err(vpro_profile_rule("Env", field = "", value = "1"), "vpro_error_analysis", "non-empty")
  expect_vpro_err(vpro_sf(ws, audit_geodesy = NA), "vpro_error_spatial", "TRUE or FALSE")
  expect_vpro_err(vpro_climate(ws, force_offline = TRUE, allow_fallback = FALSE), "vpro_error_climate", "Cannot set both")
  expect_vpro_err(vpro_edatopic_grid(ws, min_constancy = 150), "vpro_error_edatopic", "min_constancy")
  expect_vpro_err(vpro_diagnostics(ws, min_constancy = -5), "vpro_error_diagnostics", "min_constancy")
  expect_vpro_err(vpro_pairwise(ws, min_plots = 0L), "vpro_error_diagnostics", "positive integer")
  expect_vpro_err(vpro_export_xlsx(ws, path = ""), "vpro_error_report", "non-empty")
  expect_vpro_err(
    vpro_write_su(ws, tibble::tibble(PlotNumber = "00001", SiteUnit = "X"), candidate = TRUE),
    "vpro_error_writeback",
    "read-only installed"
  )
  expect_vpro_err(vpro_access_inspect(brace_path), "vpro_error_import", "existing")
  expect_vpro_err(vpro:::vpro_parse_sidecar_payload(123L), "vpro_error_sidecar", "payload_json")
  expect_vpro_err(vpro_master_disconnect(list()), "vpro_error_cloud", "vpro_pg_conn")
  expect_vpro_err(vpro:::vpro_bundled_file("extdata", "no_such_{file}.db", must_work = TRUE), "vpro_error_resource", "not found")
})

test_that("ENG-R-009 structural complexity, super-assignment, and error AST bounds hold", {
  ns <- asNamespace("vpro")
  ns_names <- ls(ns, all.names = TRUE)

  count_branches <- function(fn_body) {
    tok <- 0L
    walk <- function(x) {
      if (is.call(x)) {
        h <- x[[1L]]
        if (is.name(h) && as.character(h) %in% c("if", "for", "while", "repeat", "&&", "||", "tryCatch", "switch")) {
          tok <<- tok + 1L
        }
        for (a in as.list(x)) {
          if (!missing(a)) walk(a)
        }
      }
    }
    walk(fn_body)
    tok
  }

  has_forbidden_call <- function(fn_body, targets) {
    hit <- FALSE
    walk <- function(x) {
      if (is.call(x)) {
        fn_txt <- paste(deparse(x[[1L]]), collapse = "")
        if (fn_txt %in% targets) {
          hit <<- TRUE
        }
        for (a in as.list(x)) {
          if (!missing(a)) walk(a)
        }
      }
    }
    walk(fn_body)
    hit
  }

  for (nm in ns_names) {
    obj <- get(nm, envir = ns, inherits = FALSE)
    if (!is.function(obj)) next
    b <- count_branches(body(obj))
    expect_lte(b, 80L, label = paste0("branches(", nm, ")"))
    expect_false(
      has_forbidden_call(body(obj), c("<<-", "stop", "base::stop", "rlang::abort")),
      label = paste0("forbidden <<- / stop / rlang::abort in ", nm)
    )
  }

  src_dir <- testthat::test_path("../../R")
  if (dir.exists(src_dir)) {
    r_files <- sort(list.files(src_dir, "\\.R$", full.names = TRUE))
    expect_gt(length(r_files), 30L)
    for (f in r_files) {
      ex <- parse(f, keep.source = TRUE)
      sr <- attr(ex, "srcref")
      for (i in seq_along(ex)) {
        e <- ex[[i]]
        if (
          is.call(e) &&
            (identical(e[[1L]], as.name("<-")) || identical(e[[1L]], as.name("="))) &&
            is.call(e[[3L]]) &&
            identical(e[[3L]][[1L]], as.name("function"))
        ) {
          fn_nm <- as.character(e[[2L]])[[1L]]
          n_lines <- sr[[i]][[3L]] - sr[[i]][[1L]] + 1L
          n_br <- count_branches(e[[3L]])
          expect_lte(n_lines, 300L, label = paste0(basename(f), "::", fn_nm, " lines"))
          expect_lte(n_br, 80L, label = paste0(basename(f), "::", fn_nm, " branches"))
        }
      }
    }
  }
})
