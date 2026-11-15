setwd(system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE, stderr = NULL))
validate <- FALSE # Already validated, might need to validate on mac to make sure it is the same.
source("data-raw/z_initutils.R")
