accdb_path <- file.path(getwd(), "../VPRO_ACCESS/VPro64/VMetaData.accda")

# Assuming working directory is the root of the project vpro.git
workdir <- file.path(getwd(), "initdb/metadata")

output <- file.path(outputdir, "VMetaData.db")
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
    test1 <- read_table_preserve_names(DBI::dbConnect(mdbtoolr::mdb(), accdb_path), tb) |> data.table::setDT()
    test2 <- read_table_preserve_names(con, tb) |> data.table::setDT()
    comparison <- harmonize_validation_tables(test1, test2)
    test1 <- comparison$test1
    test2 <- comparison$test2
    if (!validation_tables_equal(test1, test2)) {
      browser()
      stop(sprintf("Data mismatch for table %s", tb))
    }
  }
}

DBI::dbDisconnect(con)