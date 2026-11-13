# Environment-code validation contract

## Access evidence

The canonical source is `V7mdlReportsValidateEnvData.ValidateEnvData` and its
private helper `ReportData`.

`ValidateEnvData` reads distinct `ListName`, `FieldUsedIn`, and `ValidateLoops`
definitions from `USysTableOfLists` where `Validate = Yes`. A positive
`ValidateLoops` value expands the field name by appending each integer from one
to that value. Otherwise, the unmodified field name is checked. In the canonical
VLists data, `SiteDisturbance` is expanded to `SiteDisturbance1` through
`SiteDisturbance3`; all other enabled definitions identify one field.

For each field, `ReportData` left-joins the current `USysEnv` query to list items
having the selected `ListName`. It reports non-null, non-empty environment values
for which no equal list item exists. Values are not trimmed or otherwise
normalized, so whitespace-only values remain eligible. Duplicate matching list
items do not create findings, and duplicate projected findings may be emitted by
the Access recordset if the source query contains them.

`USysEnv` is the active Env-Admin inner join. When an SU is active, it is the
Env-SU-Admin intersection. Orphan Env rows and SU rows without a complete
Env-Admin pair are therefore outside the validation scope.

Each field-level query has its own error handler. A missing or malformed dynamic
field produces modal error messages identifying that field, then validation
continues with the next definition. Successful findings are written to separate
blocks in a visible Excel workbook. If no field produces findings, Access writes
`No errors noted`.

## Package API

`vpro_validate_environment_codes()` requires an active project context and
accepts an explicit SQLite list-reference database, defaulting to bundled
`VLists.db`. The reference database must contain `USysTableOfLists` with
`ListName`, `Item`, `FieldUsedIn`, `ValidateLoops`, and `Validate` fields.

The API returns a list containing two deterministic data frames:

- `findings`: `list_name`, `field`, `PlotNumber`, and `value`;
- `skipped`: `list_name`, `field`, and `reason` for definitions that could not be
  evaluated.

Returning skipped definitions preserves Access's field-level continuation while
making errors visible without modal dialogs. Null or blank metadata names and
non-integer loop counts are skipped explicitly. Dynamic fields are resolved
case-insensitively across the physical Env and Admin schemas. Missing or
ambiguous fields are skipped. This case-insensitive resolution is important for
the canonical `SoilClassSubgroup` metadata, which matches the bundled VP08 field
`SoilClassSubGroup`.

By default, an active SU restricts validation through the same Env-SU-Admin
intersection represented by `USysEnv`. `use_active_su = FALSE` validates the
complete active Env-Admin project join. Same-file and external SUs are supported
without changing context attachment ownership.

SQLite `NOCASE` is used as a portable approximation of Access database text
comparison. Exact locale and accent equivalence is not claimed. Environment
values and list items are not trimmed or normalized. Findings are deduplicated
on their projected plot and value and sorted by definition, plot, and value.
This intentional determinism replaces Access's unspecified row order and avoids
repeated rows that provide no additional diagnostic information.

The operation is read-only. It does not create the temporary
`qryTableOfLists`, automate Excel, or modify project, SU, reference,
configuration, or compatibility-view state.
