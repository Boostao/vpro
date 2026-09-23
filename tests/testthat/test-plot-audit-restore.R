local_audit_restore_context <- function(path, authorize = NULL) {
  con <- tryCatch(vpro_db_connect(), error = identity)
  if (inherits(con, "error")) {
    testthat::skip(conditionMessage(con))
  }
  context <- vpro_project_context(con = con, authorize = authorize)
  withr::defer(vpro_db_disconnect(context$con), envir = parent.frame())
  vpro_project_attach(context, path, "Sample")
  vpro_project_activate(context, "Sample")
  context
}

local_audit_restore_copy <- function() {
  path <- tempfile(fileext = ".db")
  file.copy(system.file("extdata", "projects", "Sample.db", package = "vpro"), path)
  path
}

audit_restore_plot_number <- function(context) {
  DBI::dbGetQuery(
    context$con,
    'SELECT "PlotNumber" FROM USysEnv ORDER BY "PlotNumber" LIMIT 1'
  )$PlotNumber[[1L]]
}

latest_audit_event <- function(context, plot_number, field) {
  history <- vpro_plot_audit_list(context, plot_number)
  tail(history[history$EditField == field, , drop = FALSE], 1L)
}

test_that("audit restoration resolves Env and Admin fields and preserves history", {
  path <- local_audit_restore_copy()
  context <- local_audit_restore_context(path)
  plot_number <- audit_restore_plot_number(context)

  vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "First location"),
    admin = list(OfficeNotes = "First note"),
    user = "tester",
    audit_strength = 2
  )
  vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "Second location"),
    admin = list(OfficeNotes = "Second note"),
    user = "tester",
    audit_strength = 1
  )
  location_event <- latest_audit_event(context, plot_number, "Location")
  notes_event <- latest_audit_event(context, plot_number, "OfficeNotes")
  before_count <- nrow(vpro_plot_audit_list(context, plot_number))

  env_result <- vpro_plot_audit_restore(context, plot_number, location_event)
  admin_result <- vpro_plot_audit_restore(context, plot_number, notes_event)

  plot <- vpro_plot_get(context, plot_number)
  expect_identical(plot$env$Location, "First location")
  expect_identical(plot$admin$OfficeNotes, "First note")
  expect_identical(env_result$target$Location, "First location")
  expect_identical(admin_result$target$OfficeNotes, "First note")
  expect_false(env_result$audit_deleted)
  expect_identical(nrow(vpro_plot_audit_list(context, plot_number)), before_count)
})

test_that("audit restoration rejects stale current values and invalid targets", {
  path <- local_audit_restore_copy()
  context <- local_audit_restore_context(path)
  plot_number <- audit_restore_plot_number(context)

  vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "First location"),
    user = "tester",
    audit_strength = 2
  )
  stale_event <- latest_audit_event(context, plot_number, "Location")
  vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "Later location"),
    user = "tester",
    audit_strength = 1
  )

  expect_snapshot(
    error = TRUE,
    vpro_plot_audit_restore(context, plot_number, stale_event)
  )
  expect_identical(vpro_plot_get(context, plot_number)$env$Location, "Later location")
  expect_snapshot(
    error = TRUE,
    vpro_plot_audit_restore(context, plot_number, transform(stale_event, audit_rowid = 999999999))
  )
  expect_snapshot(
    error = TRUE,
    vpro_plot_audit_restore(context, plot_number, transform(stale_event, User = "changed fingerprint"))
  )
})

test_that("malformed numeric audit values are rejected without mutation", {
  path <- local_audit_restore_copy()
  context <- local_audit_restore_context(path)
  plot_number <- audit_restore_plot_number(context)
  vpro_plot_update(
    context,
    plot_number,
    env = list(Elevation = 100L),
    user = "tester",
    audit_strength = 2
  )
  vpro_plot_update(
    context,
    plot_number,
    env = list(Elevation = 200L),
    user = "tester",
    audit_strength = 1
  )
  event <- latest_audit_event(context, plot_number, "Elevation")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbExecute(
    con,
    "UPDATE Sample_Audit SET BeforeEdit = '1.9' WHERE rowid = ?",
    params = list(event$audit_rowid)
  )
  malformed <- latest_audit_event(context, plot_number, "Elevation")

  expect_error(
    vpro_plot_audit_restore(context, plot_number, malformed),
    "incompatible with declared SQLite type",
    fixed = TRUE
  )
  expect_identical(vpro_plot_get(context, plot_number)$env$Elevation, 200L)
})

test_that("child audit restoration uses compound identity and typed values", {
  path <- local_audit_restore_copy()
  context <- local_audit_restore_context(path)
  plot_number <- audit_restore_plot_number(context)
  created <- vpro_plot_vegetation_create(
    context,
    plot_number,
    list(Species = "RESTORE", Cover1 = 1),
    user = "creator",
    audit_strength = 2
  )
  id <- created$vegetation$ID
  vpro_plot_vegetation_update(
    context,
    plot_number,
    id,
    list(Cover1 = 2),
    user = "editor",
    audit_strength = 1
  )
  event <- latest_audit_event(context, plot_number, "Cover1")

  result <- vpro_plot_audit_restore(context, plot_number, event)

  expect_identical(result$target$ID, id)
  expect_identical(result$target$Cover1, 1)
  expect_identical(vpro_plot_vegetation_get(context, plot_number, id)$Cover1, 1)
})

test_that("ambiguous child identity prevents restoration", {
  path <- local_audit_restore_copy()
  context <- local_audit_restore_context(path)
  plot_number <- audit_restore_plot_number(context)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbAppendTable(
    con,
    "Sample_Veg",
    data.frame(
      PlotNumber = c(plot_number, plot_number),
      Species = c("DUPONE", "DUPTWO"),
      Cover1 = c(2, 2),
      ID = c(2000000010, 2000000010),
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    con,
    "Sample_Audit",
    data.frame(
      Project = "Sample",
      User = "tester",
      PlotNumber = plot_number,
      Table = "_Veg",
      EditField = "Cover1",
      EditWhen = "2026-09-22 17:00:00 UTC",
      BeforeEdit = "1",
      AfterEdit = "2",
      ID = 2000000010,
      stringsAsFactors = FALSE
    )
  )
  event <- latest_audit_event(context, plot_number, "Cover1")

  expect_snapshot(
    error = TRUE,
    vpro_plot_audit_restore(context, plot_number, event)
  )
  expect_identical(
    DBI::dbGetQuery(
      con,
      "SELECT Cover1 FROM Sample_Veg WHERE PlotNumber = ? AND ID = ?",
      params = list(plot_number, 2000000010)
    )$Cover1,
    c(2, 2)
  )
})

test_that("audit deletion is explicit and transactional", {
  path <- local_audit_restore_copy()
  context <- local_audit_restore_context(path)
  plot_number <- audit_restore_plot_number(context)
  vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "Delete this audit"),
    user = "tester",
    audit_strength = 2
  )
  event <- latest_audit_event(context, plot_number, "Location")

  result <- vpro_plot_audit_restore(
    context,
    plot_number,
    event,
    delete_audit = TRUE
  )

  expect_true(result$audit_deleted)
  expect_false(event$audit_rowid %in% vpro_plot_audit_list(context, plot_number)$audit_rowid)
  expect_true(is.na(vpro_plot_get(context, plot_number)$env$Location))
})

test_that("failed audit deletion rolls back the restored field", {
  path <- local_audit_restore_copy()
  context <- local_audit_restore_context(path)
  plot_number <- audit_restore_plot_number(context)
  vpro_plot_update(
    context,
    plot_number,
    env = list(Location = "Must remain"),
    user = "tester",
    audit_strength = 2
  )
  event <- latest_audit_event(context, plot_number, "Location")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  withr::defer(DBI::dbDisconnect(con))
  DBI::dbExecute(
    con,
    "CREATE TRIGGER prevent_audit_delete BEFORE DELETE ON Sample_Audit BEGIN SELECT RAISE(ABORT, 'delete blocked'); END"
  )

  expect_error(
    vpro_plot_audit_restore(context, plot_number, event, delete_audit = TRUE),
    "delete blocked",
    fixed = TRUE
  )
  expect_identical(vpro_plot_get(context, plot_number)$env$Location, "Must remain")
  expect_true(event$audit_rowid %in% vpro_plot_audit_list(context, plot_number)$audit_rowid)
})

test_that("protected Admin restoration requires authorization", {
  path <- local_audit_restore_copy()
  authorized <- local_audit_restore_context(
    path,
    authorize = function(permission, resource) {
      identical(permission, "update_protected_plot_field") && identical(resource$field, "BECSiteUnit")
    }
  )
  plot_number <- audit_restore_plot_number(authorized)
  vpro_plot_update(
    authorized,
    plot_number,
    admin = list(BECSiteUnit = "RESTORED"),
    user = "steward",
    audit_strength = 2
  )
  event <- latest_audit_event(authorized, plot_number, "BECSiteUnit")
  unauthorized <- local_audit_restore_context(path)

  expect_snapshot(
    error = TRUE,
    vpro_plot_audit_restore(unauthorized, plot_number, event)
  )
  expect_identical(vpro_plot_get(unauthorized, plot_number)$admin$BECSiteUnit, "RESTORED")
  vpro_plot_audit_restore(authorized, plot_number, event)
  expect_true(is.na(vpro_plot_get(authorized, plot_number)$admin$BECSiteUnit))
})
