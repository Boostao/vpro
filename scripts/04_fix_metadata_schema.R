# Fix USysProjectMetadata Schema and Migrate Data
# Issue: USysProjectMetadata was created with all BOOLEAN columns.
# Fix: Recreate with VARCHAR columns and populate.

library(duckdb)
library(dplyr)

con <- dbConnect(duckdb(), "data/vpro.duckdb")

# 1. Get current column names
schema <- dbGetQuery(con, "DESCRIBE USysProjectMetadata")
cols <- schema$column_name

# 2. Drop table
print("Dropping malformed USysProjectMetadata...")
dbExecute(con, "DROP TABLE USysProjectMetadata")

# 3. Recreate with VARCHAR
# Construct CREATE TABLE statement
col_defs <- paste(sapply(cols, function(x) paste0("\"", x, "\" VARCHAR")), collapse = ", ")
create_stmt <- paste("CREATE TABLE USysProjectMetadata (", col_defs, ")") # No primary key for now

print("Recreating USysProjectMetadata with VARCHAR schema...")
dbExecute(con, create_stmt)

# 4. Run Migration Logic (from 03_migrate_metadata.R)
projects <- dbGetQuery(con, "
  SELECT DISTINCT 
    projectid, 
    MAX(projecttitle) as projecttitle 
  FROM Sample_Metadata 
  WHERE projectid IS NOT NULL AND projectid != ''
  GROUP BY projectid
")

if (nrow(projects) > 0) {
  print(paste("Migrating", nrow(projects), "projects..."))
  for (i in 1:nrow(projects)) {
    # Escape single quotes
    pid <- gsub("'", "''", projects$projectid[i])
    title <- gsub("'", "''", projects$projecttitle[i])
    
    # Insert
    sql <- sprintf("INSERT INTO USysProjectMetadata (projectid, projecttitle) VALUES ('%s', '%s')", pid, title)
    dbExecute(con, sql)
  }
  print("Migration complete.")
} else {
  print("No projects found in Sample_Metadata to migrate.")
}

# Verify
count <- dbGetQuery(con, "SELECT COUNT(*) as n FROM USysProjectMetadata")
print(paste("Final count in USysProjectMetadata:", count$n))

dbDisconnect(con)
