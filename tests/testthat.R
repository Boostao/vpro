library(testthat)
library(vpro)

# Historical generated tests are retained as migration evidence but target a
# superseded app layout. Only package-native tests run until each legacy test is
# reconciled with the parity ledger.
test_check("vpro", filter = "^(config|install|db-foundation|parity-parser|project-context)$")
