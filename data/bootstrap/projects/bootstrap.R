accdb_path <- file.path(getwd(), "../VPRO_ACCESS/VPro64/VPro64.accdb")

# Assuming working directory is the root of the project vpro.git
workdir <- file.path(getwd(), "data/bootstrap/projects")
views_sql_path <- file.path(workdir, "views.sql")

# Listing project prefixes
projects <- list.files(workdir, pattern = "\\.csv$") |>
  tools::file_path_sans_ext() |>
  strsplit(split = "_") |>
  vapply(`[`, 1, FUN.VALUE = character(1)) |>
  unique() |>
  sort()

for (p in projects) {
  output <- file.path(workdir, sprintf("%s.db", p))
  unlink(output, force = TRUE)

  con <- DBI::dbConnect(RSQLite::SQLite(), output)

  DBI::dbExecute(con, "PRAGMA foreign_keys = ON;")

  tbs <- list.files(workdir, pattern = paste0("^", p, ".*\\.csv$")) |>
    tools::file_path_sans_ext() |>
    unique()

  env_tb <- sprintf("%s_Env", p)
  if (env_tb %in% tbs) {
    tbs <- c(env_tb, setdiff(tbs, env_tb))
  }

  for (tb in tbs) {
    sql_path <- file.path(workdir, sprintf("%s.sql", tb))
    statements <- read_sql_statements(sql_path)

    for (statement in statements) {
      DBI::dbExecute(con, statement)
    }
  }

  for (tb in tbs) {
    data_path <- file.path(workdir, sprintf("%s.csv", tb))
    table_name <- sub(paste0("^", p, "_"), "", tb)
    load_csv_into_table(con, table_name, data_path)

    if (validate) {
      # Validate against original Access DB
      test1 <- DBI::dbReadTable(DBI::dbConnect(mdbtoolr::mdb(), accdb_path), tb) |> data.table::setDT()
      test2 <- DBI::dbReadTable(con, table_name) |> data.table::setDT()
      for (nm in names(test1)) {
        if (inherits(test2[[nm]], "blob") && inherits(test1[[nm]], "character")) {
          test2[, (nm) := vapply(test2[[nm]], function(x) {
            if (is.null(x)) NA_character_ else rawToChar(x)
          }, character(1))]
        } else if (!inherits(test2[[nm]], class(test1[[nm]]))) {
          if (inherits(test1[[nm]], "POSIXct")) {
            test2[, (nm) := mdbtoolr:::.coerce_datetime(test2[[nm]])]
          } else {
            test2[, (nm) := as(test2[[nm]], class(test1[[nm]])[1])]
          }
        }
      }
      if (!isTRUE(all.equal(test1, test2, ignore.row.order = TRUE)) &&
          !isTRUE(all.equal(test1, test2, tolerance = sqrt(.Machine$double.eps) * 100))) {
        browser()
        stop(sprintf("Data mismatch for table %s in project %s", table_name, p))
      }
    }

  }

  for (statement in read_sql_statements(views_sql_path)) {
    DBI::dbExecute(con, statement)
  }

  DBI::dbDisconnect(con)
}
