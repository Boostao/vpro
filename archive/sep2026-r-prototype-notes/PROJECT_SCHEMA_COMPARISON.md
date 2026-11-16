# Project schema comparison contract

## Access evidence

The canonical source is `V7mdlCompareTablesToTemplate`. `CheckThisProject`
compares eight fixed template/project pairs: Audit, Env, Humus, Mineral, Other,
Veg, Metadata, and Admin.

For each template table, Access iterates template fields only. It reports a
project field as `Missing`, `Size`, or `Type`. Project-only fields, field order,
nullability, defaults, keys, indexes, relationships, validation rules, and table
metadata are not compared. Results are written to a new Excel workbook. If no
field difference is found, Access displays an informational message.

The module has no discovered production caller. Its private `TestFunction`
invokes the comparison for `Sample` only.

## Package API

`vpro_project_compare_schema()` performs the same directional field comparison
against SQLite project families. It defaults to the bundled VP08 `Sample.db`
project but accepts another template database and project prefix.

The operation is read-only and returns one deterministic data-frame row per
finding with table, field, difference, expected, and actual values. A conforming
project returns an empty data frame. Missing project tables are reported
explicitly rather than failing through an unhandled DAO table lookup. A missing
template table is an input error.

Field names are matched case-insensitively, consistent with Access field lookup.
Declared SQLite type aliases are normalized before comparison. Declared sizes
are compared separately when encoded in a type such as `VARCHAR(7)`.

The canonical SQLite translation generally stores Access text fields as
unbounded `VARCHAR`; Access field lengths preserved only in SQL comments cannot
be recovered through SQLite schema metadata. This API therefore does not infer
sizes from comments or data values.

Presentation and export are caller responsibilities. The package does not open
Excel or display modal success messages.

A broader structural validator for defaults, nullability, keys, indexes,
relationships, and checks would be a separate modernized API because those
properties were not part of the observed Access comparison contract.
