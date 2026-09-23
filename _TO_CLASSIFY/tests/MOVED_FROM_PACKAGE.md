# Historical tests moved from the package tree

These files were moved from `tests/` on 2026-09-22 because they target the superseded root Shiny layout, optional PostgreSQL infrastructure, obsolete report paths, or generated integration fixtures. They remain migration evidence and are excluded from package builds through the existing `_TO_CLASSIFY` rule in `.Rbuildignore`.

Original paths are preserved beneath this directory:

- package-level test notes and smoke wrapper: formerly `tests/*`;
- historical unit and integration tests: formerly `tests/testthat/*`;
- generated DuckDB baselines: formerly `tests/testthat/data/project_baselines/*`.

The earlier ShinyTest2 suite remains in `_TO_CLASSIFY/shinytest2/`, preserving its former `tests/shinytest2/` filenames.

The active package test tree now contains only package-native configuration, installation, DuckDB foundation, parity parser, project lifecycle, SU lifecycle, and hierarchy lifecycle tests. `tests/testthat.R` runs all of them without a filter.
