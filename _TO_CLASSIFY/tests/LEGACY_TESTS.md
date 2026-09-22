# Historical test suite

Most files under `tests/testthat/` predate the current package architecture and refer to missing `app/R/logic`, root-level `reports/`, persistent DuckDB files, or an optional PostgreSQL model. They are retained as migration evidence, not treated as passing parity tests.

`tests/testthat.R` temporarily runs only package-native foundation tests. Each historical test must be reviewed against the Access parity ledger, moved or rewritten to exercise exported package APIs, and then added to the active filter. A similarly named R function or HTML report is not sufficient evidence of Access equivalence.
