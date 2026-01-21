# Fix SppList Schema
# Issue: SppList was created with all BOOLEAN columns (because csv was empty).
# Fix: Recreate with VARCHAR columns.

library(duckdb)

con <- dbConnect(duckdb(), "data/vpro.duckdb")

# 1. Get current column names
schema <- dbGetQuery(con, "DESCRIBE SppList")
cols <- schema$column_name

# 2. Drop table
print("Dropping malformed SppList...")
dbExecute(con, "DROP TABLE SppList")

# 3. Recreate with VARCHAR
# Construct CREATE TABLE statement
col_defs <- paste(sapply(cols, function(x) paste0("\"", x, "\" VARCHAR")), collapse = ", ")
create_stmt <- paste("CREATE TABLE SppList (", col_defs, ")") 

print("Recreating SppList with VARCHAR schema...")
dbExecute(con, create_stmt)

# Verify
desc <- dbGetQuery(con, "DESCRIBE SppList")
print(desc)

dbDisconnect(con)
