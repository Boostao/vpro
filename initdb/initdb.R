{setwd(system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE, stderr = NULL))}
source("initdb/z_initutils.R")