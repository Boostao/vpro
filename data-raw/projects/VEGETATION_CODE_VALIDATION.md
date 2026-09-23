# Vegetation-code validation contract

## Access evidence

The canonical source is
`V7mdlReportsValidateVegCodes.CheckVegData`. It reads the configured current
project and plot list, constructs one of two DAO queries, and opens Excel only
when findings exist.

Without an active SU, the query left-joins every `<Project>_Veg` row to
`USysAllSpecs` by `Species = Code` and reports rows whose reference code is null.
It does not join to Env. Vegetation belonging to an orphan plot therefore remains
in scope.

With an active SU, the query starts from `<SU>_SU`, left-joins the vegetation and
master-list result by plot number, and requires only a non-null SU plot number.
Consequently:

- vegetation outside the SU is excluded;
- duplicate SU and vegetation rows can multiply intermediate rows;
- an SU plot with no vegetation produces a projected `(Null, Null)` finding
  because the selected plot number comes from Veg rather than SU;
- blank SU plot numbers are eligible if they join to vegetation;
- null SU plot numbers are excluded.

Both variants use `SELECT DISTINCTROW` without `ORDER BY`. Null and blank species
codes are not explicitly filtered. Validation uses the physical master
`USysAllSpecs` table directly. It does not use `USysAllSpecies`, does not include
`USysUserSpp`, and does not filter synonym rows by `CodeType`.

## Package API

`vpro_validate_vegetation_codes()` requires an active project context and accepts
an explicit SQLite species-reference database, defaulting to bundled
`VLists.db`. The reference database must contain `USysAllSpecs.Code`.

By default, an active SU restricts validation using the Access left-join shape.
`use_active_su = FALSE` validates the complete active project. Same-file and
external active SUs are supported without changing context attachment ownership.

The package uses SQLite `NOCASE` for ASCII case-insensitive code matching as a
portable approximation of Access database comparison. Exact accent and locale
collation equivalence is not claimed. Codes are not trimmed or otherwise
normalized.

Findings contain `PlotNumber` and `Species`, are deduplicated on those projected
values, and are sorted deterministically. This replaces Access's unspecified
record order and Excel automation. The operation is read-only and does not alter
project, SU, configuration, reference data, or compatibility views.
