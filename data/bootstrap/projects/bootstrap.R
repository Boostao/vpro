library(DBI)
library(duckdb)
#library(mdbtoolr)
#library(data.table)
#accdb_path <- file.path(getwd(), "../VPRO_ACCESS/VPro64/VPro64.accdb")

# Assuming working directory is the root of the project vpro.git
workdir <- file.path(getwd(), "data/bootstrap/projects")

# Listing projects prefix
projects <- list.files(workdir, pattern = "\\.csv$") |> 
  tools::file_path_sans_ext() |> 
  strsplit(split = "_") |> 
  vapply(`[`, 1, FUN.VALUE = character(1)) |>
  unique() |>
  sort()

con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
DBI::dbExecute(con,"INSTALL sqlite; LOAD sqlite;")

for (p in projects) {
  
  # SQLite DB file to create
  output <- sprintf("%s.db", file.path(workdir, projects))
  unlink(output, force = TRUE)
  DBI::dbExecute(con, sprintf("ATTACH '%s' AS sqlite_db (TYPE sqlite);", output))

  tbs <- list.files(workdir, pattern = paste0(p, ".*\\.csv$")) |> 
    tools::file_path_sans_ext() |> 
    unique()

  DBI::dbExecute(con, "USE sqlite_db;")

  for (tb in tbs) {
    sql_path <- file.path(workdir, sprintf("%s.sql", tb))
    data_path <- file.path(workdir, sprintf("%s.csv", tb))
    sql <- readLines(sql_path) |> paste(collapse = "\n")
    DBI::dbExecute(con, sql)
    table_name <- sub(paste0("^", p, "_"), "", tb)
    DBI::dbExecute(con, sprintf("INSERT INTO %s BY NAME (SELECT * FROM read_csv('%s', sample_size = -1));", table_name, data_path))
    
    if (FALSE) {
      # Validate against original Access DB
      test1 <- DBI::dbReadTable(DBI::dbConnect(mdbtoolr::mdb(), accdb_path), tb) |> data.table::setDT()
      test2 <- DBI::dbReadTable(con, table_name) |> data.table::setDT()
      for (nm in names(test1)) {
        if (!inherits(test2[[nm]], class(test1[[nm]]))) {
          test2[, (nm) := as(test2[[nm]], class(test1[[nm]])[1])]
        }
      }
      stopifnot(
        all.equal(
          test1,
          test2,
          tolerance = sqrt(.Machine$double.eps) * 100,
          ignore.row.order = TRUE
        )
      )
    }
  }

}

