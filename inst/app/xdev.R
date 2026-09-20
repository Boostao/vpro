setwd(system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE, stderr = NULL))
setwd("app")
source("R/logic/00.db.R")
source("R/logic/01.state.R")
con <- init_state()
db_sys_dbs
db_query(con, "SELECT * FROM Sample.qryHerbariumReportData LIMIT 1;") |> names()
db_query(con, "SELECT * FROM Sample.UsysEnv LIMIT 1;") |> names()

options("shiny.autoreload" = TRUE)
shiny::runApp("app")
