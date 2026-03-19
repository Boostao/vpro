accdb_path <- file.path(getwd(), "../VPRO_ACCESS/VPro64/VMessageBoard.accda")

# Assuming working directory is the root of the project vpro.git
workdir <- file.path(getwd(), "initdb/messages")
post_load_sql_path <- file.path(workdir, "post_load.sql")
trigger_sql_path <- file.path(workdir, "create_trigger_tblMessageBoard_add_to_message_list.sql")

output <- file.path(outputdir, "VMessageBoard.db")
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

for (statement in read_sql_statements(post_load_sql_path)) {
  DBI::dbExecute(con, statement)
}

DBI::dbExecute(con, 'DROP TRIGGER IF EXISTS "trg_tblMessageBoard_add_to_message_list";')
DBI::dbExecute(con, paste(readLines(trigger_sql_path, warn = FALSE), collapse = "\n"))

DBI::dbDisconnect(con)
