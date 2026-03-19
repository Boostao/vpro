table_hash <- function(con, table_name) {
  table_name <- DBI::Id(strsplit(table_name, "\\.")[[1]])
  query <- sprintf(
    "SELECT bit_xor(hash(*columns(*)))::VARCHAR AS table_hash FROM %s;",
    DBI::dbQuoteIdentifier(con, table_name)
  )
  result <- DBI::dbGetQuery(con, query)
  result$table_hash
}
