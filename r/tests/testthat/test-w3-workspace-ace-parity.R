# W3 workspace directory resolution, ACE 15-sig-digit rounding, and Sample.db
# precedence parity (ENG-XCUT-007 + dup ENG-R-005, UX-ADMIN-003).

test_that("ENG-XCUT-007 + ENG-R-005: vpro_data_dir and vpro_config_dir preserve symlinks, expand ~, clean .., ignore relative XDG_*, and reject empty HOME", {
  td <- tempfile("vpro-w3-dirs-")
  real_dir <- file.path(td, "real_vpro")
  link_dir <- file.path(td, "symlink_vpro")
  cwd_dir <- file.path(td, "cwd")
  dir.create(real_dir, recursive = TRUE)
  dir.create(cwd_dir, recursive = TRUE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)

  has_symlink <- isTRUE(tryCatch(file.symlink(real_dir, link_dir), warning = function(w) FALSE, error = function(e) FALSE))

  withr::with_options(list(vpro.data_dir = NULL, vpro.config_dir = NULL), {
    withr::with_dir(cwd_dir, {
      cwd_clean <- vpro:::vpro_lexical_clean_path(getwd(), convert_backslash = (.Platform$OS.type == "windows"))

      # 1. Symlinked VPRO_DATA_DIR / VPRO_CONFIG_DIR and XDG_* preserve symlink path (no realpath dereference)
      if (has_symlink) {
        link_clean <- vpro:::vpro_lexical_clean_path(link_dir)
        withr::with_envvar(c(HOME = "/home/x", VPRO_DATA_DIR = link_dir, VPRO_CONFIG_DIR = link_dir), {
          expect_identical(vpro_data_dir(), link_clean)
          expect_identical(vpro_config_dir(), link_clean)
        })
        expect_identical(
          vpro:::vpro_resolve_data_dir(os = "Linux", opt = NULL, env_data = "", xdg_data = link_dir, home = "/home/x"),
          paste0(link_clean, "/vpro")
        )
        expect_identical(
          vpro:::vpro_resolve_config_dir(os = "Linux", opt = NULL, env_cfg = "", xdg_cfg = link_dir, home = "/home/x"),
          paste0(link_clean, "/vpro")
        )
      }

      # 2. Tilde overrides (~, ~/, ~/custom_vpro_test, ~/a/b/../c/) expand against HOME; ~literal stays relative
      withr::with_envvar(c(HOME = "/home/x", VPRO_DATA_DIR = "~/custom_vpro_test", VPRO_CONFIG_DIR = "~/a/b/../cfg/"), {
        expect_identical(vpro_data_dir(), "/home/x/custom_vpro_test")
        expect_identical(vpro_config_dir(), "/home/x/a/cfg")
      })
      withr::with_envvar(c(HOME = "/home/x", VPRO_DATA_DIR = "~", VPRO_CONFIG_DIR = "~/"), {
        expect_identical(vpro_data_dir(), "/home/x")
        expect_identical(vpro_config_dir(), "/home/x")
      })
      withr::with_envvar(c(HOME = "/home/x", VPRO_DATA_DIR = "~literal", VPRO_CONFIG_DIR = "rel/c"), {
        expect_identical(vpro_data_dir(), paste0(cwd_clean, "/~literal"))
        expect_identical(vpro_config_dir(), paste0(cwd_clean, "/rel/c"))
      })

      # 3. Non-existent .. and duplicate/trailing slashes clean lexically
      withr::with_envvar(c(HOME = "/home/x", VPRO_DATA_DIR = "/a/b/../c/", VPRO_CONFIG_DIR = "/a//c/"), {
        expect_identical(vpro_data_dir(), "/a/c")
        expect_identical(vpro_config_dir(), "/a/c")
      })
      expect_identical(vpro:::vpro_lexical_clean_path("///../../a/./b/../c//"), "/a/c")

      # 4. Single-space segment override preserved
      withr::with_envvar(c(HOME = "/home/x", VPRO_DATA_DIR = " ", VPRO_CONFIG_DIR = " "), {
        expect_identical(vpro_data_dir(), paste0(cwd_clean, "/ "))
        expect_identical(vpro_config_dir(), paste0(cwd_clean, "/ "))
      })

      # 5. Relative XDG_DATA_HOME / XDG_CONFIG_HOME (including ~/...) ignored per XDG Base Dir Spec across Linux & BSD
      for (unix_os in c("Linux", "FreeBSD")) {
        expect_identical(
          vpro:::vpro_resolve_data_dir(os = unix_os, opt = NULL, env_data = "", xdg_data = "rel_xdg_data", home = "/home/x"),
          "/home/x/.local/share/vpro"
        )
        expect_identical(
          vpro:::vpro_resolve_config_dir(os = unix_os, opt = NULL, env_cfg = "", xdg_cfg = "rel_xdg_cfg", home = "/home/x"),
          "/home/x/.config/vpro"
        )
        expect_identical(
          vpro:::vpro_resolve_data_dir(os = unix_os, opt = NULL, env_data = "", xdg_data = "~/xdg_data", home = "/home/x"),
          "/home/x/.local/share/vpro"
        )
        expect_identical(
          vpro:::vpro_resolve_data_dir(os = unix_os, opt = NULL, env_data = "", xdg_data = "/xdg/d/../d2/", home = ""),
          "/xdg/d2/vpro"
        )
        expect_identical(
          vpro:::vpro_resolve_config_dir(os = unix_os, opt = NULL, env_cfg = "", xdg_cfg = "/xdg/c//", home = ""),
          "/xdg/c/vpro"
        )
      }

      # 6. Empty HOME="" never resolves /.local/share/vpro or /.config/vpro, while HOME="/" works cleanly
      expect_error(
        vpro:::vpro_resolve_data_dir(os = "Linux", opt = NULL, env_data = "", xdg_data = "", home = ""),
        "\\$HOME is not defined"
      )
      expect_error(
        vpro:::vpro_resolve_config_dir(os = "Linux", opt = NULL, env_cfg = "", xdg_cfg = "rel/c", home = ""),
        "\\$HOME is not defined"
      )
      expect_error(
        vpro:::vpro_resolve_data_dir(os = "Darwin", opt = NULL, env_data = "", home = ""),
        "\\$HOME is not defined"
      )
      expect_error(
        vpro:::vpro_resolve_data_dir(os = "Linux", opt = "~/vp", env_data = "", home = ""),
        "\\$HOME is not defined"
      )
      expect_error(
        vpro:::vpro_resolve_data_dir(os = "Windows", opt = NULL, env_data = "", localappdata = "", userprofile = "", home = ""),
        "%USERPROFILE% is not defined"
      )
      expect_identical(
        vpro:::vpro_resolve_data_dir(os = "Linux", opt = NULL, env_data = "", xdg_data = "", home = "/"),
        "/.local/share/vpro"
      )
      expect_identical(
        vpro:::vpro_resolve_config_dir(os = "Linux", opt = NULL, env_cfg = "", xdg_cfg = "", home = "/"),
        "/.config/vpro"
      )
    })
  })
})

test_that("ENG-XCUT-007: vpro_round_ace matches Go RoundCalibratedDecimal on >2^53 scaled mantissas, MaxFloat64, subnormals, and -0.0", {
  expect_identical(vpro_round_ace(100000000000.005, 6L), 100000000000.005)
  expect_identical(vpro_round_ace(1e307, 2L), 1e307)
  expect_identical(vpro_round_ace(-1e307, 2L), -1e307)
  expect_identical(vpro_round_ace(.Machine$double.xmax, 2L), .Machine$double.xmax)
  expect_identical(vpro_round_ace(-.Machine$double.xmax, 2L), -.Machine$double.xmax)
  expect_identical(vpro_round_ace(.Machine$double.xmax, 0L), .Machine$double.xmax)

  # Subnormals and +0.0 signbit normalization
  smallest <- 2^(-1074)
  expect_identical(vpro_round_ace(smallest, 323L), 0.0)
  expect_identical(sprintf("%.1f", vpro_round_ace(-smallest, 323L)), "0.0")
  expect_identical(vpro_round_ace(2 * smallest, 323L), 2 * smallest)
  expect_identical(sprintf("%.1f", vpro_round_ace(-0.001, 2L)), "0.0")
  expect_identical(sprintf("%.1f", vpro_round_ace(-0.0, 2L)), "0.0")
  expect_identical(vpro_round_ace(1.005, 500L), 1.005)
})

test_that("UX-ADMIN-003: vpro_connect('Sample') prefers workspace Sample.db via options(vpro.data_dir) and VPRO_DATA_DIR over bundled extdata/Sample.db", {
  td <- tempfile("vpro-w3-sample-ws-")
  cfg <- tempfile("vpro-w3-sample-cfg-")
  empty_td <- tempfile("vpro-w3-sample-empty-")
  dir.create(file.path(td, "projects"), recursive = TRUE)
  dir.create(cfg, recursive = TRUE)
  dir.create(empty_td, recursive = TRUE)
  on.exit(unlink(c(td, cfg, empty_td), recursive = TRUE, force = TRUE), add = TRUE)

  # Fallback to bundled Sample.db when workspace data_dir has no Sample.db
  withr::with_options(list(vpro.data_dir = empty_td, vpro.config_dir = cfg), {
    withr::with_envvar(c(VPRO_DATA_DIR = "", VPRO_CONFIG_DIR = ""), {
      ws_bundled <- vpro_connect("Sample")
      expect_identical(ws_bundled$source, "sample")
      expect_identical(ws_bundled$su, "Sample_SU")
      expect_equal(nrow(vpro_env(ws_bundled)), 51L)
      expect_equal(nrow(vpro_env(ws_bundled, scope = "project")), 52L)
    })
  })

  # Seed a live WAL-mode workspace Sample.db with a user edit on leading-zero plot '00337'
  bundled_sample <- vpro:::vpro_bundled_db("Sample.db")
  ws_db <- file.path(td, "projects", "Sample.db")
  file.copy(bundled_sample, ws_db)
  wcon <- DBI::dbConnect(RSQLite::SQLite(), ws_db)
  on.exit(if (DBI::dbIsValid(wcon)) DBI::dbDisconnect(wcon), add = TRUE)
  DBI::dbExecute(wcon, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(
    wcon,
    "UPDATE \"Sample_Env\" SET \"SiteNotes\" = 'UX-ADMIN-003 live workspace edit' WHERE typeof(\"PlotNumber\") = 'text' AND CAST(\"PlotNumber\" AS BLOB) = CAST('00337' AS BLOB)"
  )

  # 1. options(vpro.data_dir = td) + vpro_connect("Sample") opens workspace Sample.db (52 plots incl. '00337', zero warnings)
  withr::with_options(list(vpro.data_dir = td, vpro.config_dir = cfg), {
    withr::with_envvar(c(VPRO_DATA_DIR = "", VPRO_CONFIG_DIR = ""), {
      listed <- vpro_list_projects()
      expect_true("Sample" %in% listed$project)

      expect_no_warning(ws_opt <- vpro_connect("Sample"))
      expect_identical(
        normalizePath(ws_opt$project_path, winslash = "/", mustWork = TRUE),
        normalizePath(ws_db, winslash = "/", mustWork = TRUE)
      )
      expect_identical(ws_opt$source, "workspace")
      expect_null(ws_opt$su)

      expect_no_warning(env_opt <- vpro_env(ws_opt))
      expect_equal(nrow(env_opt), 52L)
      expect_true("00337" %in% env_opt$PlotNumber)
      expect_identical(
        env_opt$SiteNotes[env_opt$PlotNumber == "00337"],
        "UX-ADMIN-003 live workspace edit"
      )

      # Case-insensitive project request ('sample') on Linux also resolves projects/Sample.db
      ws_lower <- vpro_connect("sample")
      expect_identical(ws_lower$source, "workspace")
      expect_identical(ws_lower$project_path, ws_opt$project_path)
    })
  })

  # 2. VPRO_DATA_DIR env var (with options(vpro.data_dir = NULL)) also prefers workspace Sample.db
  withr::with_options(list(vpro.data_dir = NULL, vpro.config_dir = NULL), {
    withr::with_envvar(c(VPRO_DATA_DIR = td, VPRO_CONFIG_DIR = cfg), {
      ws_env <- vpro_connect("Sample")
      expect_identical(ws_env$source, "workspace")
      expect_identical(
        normalizePath(ws_env$project_path, winslash = "/", mustWork = TRUE),
        normalizePath(ws_db, winslash = "/", mustWork = TRUE)
      )
      expect_true("00337" %in% vpro_env(ws_env)$PlotNumber)
    })
  })

  # 3. When config.yml specifies CurrPlotlist = "Sample_SU" for CurrProject = "Sample", vpro_connect("Sample") honors it
  yaml::write_yaml(
    list(Current = list(CurrProject = "Sample", CurrPlotlist = "Sample_SU")),
    file.path(cfg, "config.yml")
  )
  withr::with_options(list(vpro.data_dir = td, vpro.config_dir = cfg), {
    ws_cfg_su <- vpro_connect("Sample")
    expect_identical(ws_cfg_su$source, "workspace")
    expect_identical(ws_cfg_su$su, "Sample_SU")
    expect_equal(nrow(vpro_env(ws_cfg_su)), 51L)
  })
})
