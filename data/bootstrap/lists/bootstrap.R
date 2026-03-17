accdb_path <- file.path(getwd(), "../VPRO_ACCESS/VPro64/VLists.accda")

# Assuming working directory is the root of the project vpro.git
workdir <- file.path(getwd(), "data/bootstrap/lists")

output <- file.path(workdir, "VLists.db")
unlink(output, force = TRUE)

con <- DBI::dbConnect(RSQLite::SQLite(), output)

DBI::dbExecute(con, "PRAGMA foreign_keys = ON;")

tbs <- list.files(workdir, pattern = "\\.csv$") |>
  tools::file_path_sans_ext() |>
  unique()

for (tb in tbs) {
  sql_path <- file.path(workdir, sprintf("%s.sql", tb))
  statements <- read_sql_statements(sql_path)
  for (statement in statements) {
    DBI::dbExecute(con, statement)
  }
}

for (tb in tbs) {
  data_path <- file.path(workdir, sprintf("%s.csv", tb))
  load_csv_into_table(con, tb, data_path)
  if (validate) {
    # Validate against original Access DB
    test1 <- DBI::dbReadTable(DBI::dbConnect(mdbtoolr::mdb(), accdb_path), tb) |> data.table::setDT()
    test2 <- DBI::dbReadTable(con, tb) |> data.table::setDT()
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
      stop(sprintf("Data mismatch for table %s", tb))
    }
  }
}

DBI::dbDisconnect(con)