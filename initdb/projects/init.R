accdb_path <- file.path(getwd(), "../VPRO_ACCESS/VPro64/VPro64.accdb")

# Assuming working directory is the root of the project vpro.git
workdir <- file.path(getwd(), "initdb/projects")
views_sql_path <- file.path(workdir, "views.sql")
meta_sql_path <- file.path(workdir, "_table_metadata.sql")
meta_csv_path <- file.path(workdir, "_table_metadata.csv")

# Listing project prefixes
projects <- list.files(workdir, pattern = "\\.csv$") |>
  tools::file_path_sans_ext() |>
  strsplit(split = "_") |>
  vapply(`[`, 1, FUN.VALUE = character(1)) |>
  unique() |>
  sort() |>
  setdiff("")

for (p in projects) {
  output <- file.path(outputdir, sprintf("%s.db", p))
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
    load_csv_into_table(con, tb, data_path)

    if (validate) {
      # Validate against original Access DB
      test1 <- read_table_preserve_names(DBI::dbConnect(mdbr::mdb(), accdb_path), tb) |> data.table::setDT()
      test2 <- read_table_preserve_names(con, tb) |> data.table::setDT()
      comparison <- harmonize_validation_tables(test1, test2)
      test1 <- comparison$test1
      test2 <- comparison$test2
      if (!validation_tables_equal(test1, test2)) {
        browser()
        stop(sprintf("Data mismatch for table %s in project %s", tb, p))
      }
    }
  }

  for (statement in read_sql_statements(views_sql_path)) {
    DBI::dbExecute(con, statement)
  }

  for (statement in read_sql_statements(meta_sql_path)) {
    DBI::dbExecute(con, statement)
    load_csv_into_table(con, "_table_metadata", meta_csv_path)
    DBI::dbExecute(con, "DELETE FROM _table_metadata WHERE table_name NOT LIKE ?;", params = list(sprintf("%s_%%", p)))
  }

  DBI::dbDisconnect(con)
}
