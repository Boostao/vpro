# Environmental plot CRUD specification

## Implemented scope

The first package-native domain CRUD slice is implemented in `R/plot-crud.R`:

- `vpro_plot_get()` reads one active project's paired Env and Admin rows;
- `vpro_plot_update()` validates requested fields, updates Env and Admin in one SQLite transaction, and writes field-level Audit rows in the same transaction.

The API is independent of Shiny and requires an explicit active project context. It writes canonical SQLite base tables, not DuckDB compatibility views. Committed writes are immediately visible through the active `USysEnv` temporary view.

Plot creation, plot-number changes, plot deletion, audit restoration, vegetation CRUD, and soil-child CRUD are intentionally outside this milestone.

## Canonical Access evidence

Primary sources are:

- `Queries/UsysEnv.txt`;
- `Forms/FS882-1x1.txt`, especially `Form_BeforeUpdate`, `btnSaveRecord_Click`, and `ProjectID_LostFocus`;
- `V7mdlAudit.AuditTrail` and `V7mdlAudit.TableName`;
- `Sample_Env`, `Sample_Admin`, and `Sample_Audit` table definitions;
- canonical Env relationships to Admin, Audit, Humus, Mineral, Other, and Veg.

`USysEnv` is an inner join from `<project>_Env.PlotNumber` to `<project>_Admin.Plot`. The environmental form is bound to that joined query. Saving a bound record invokes `AuditTrail Me` in `Form_BeforeUpdate`.

`AuditTrail` excludes plot-number and child-ID controls. For each changed field it records project, user, plot, logical table suffix, field, timestamp, before value, after value, and optional child-row ID. Its configured strengths are:

| Strength | Populated value changed | Null populated | Value cleared |
|---:|---:|---:|---:|
| 0 | No | No | No |
| 1 | Yes | No | No |
| 2 | Yes | Yes | No |
| 3 | Yes | Yes | Yes |

For FS882 forms, `TableName()` records `_Env`. Because Access edits Env and Admin columns through the same joined FS882 form, the package also records `_Env` for both field groups.

## Package-native behavior

`vpro_plot_get()` requires an active VP08 project and exactly one matching Env row and Admin row. It reads directly from the active project's SQLite file and returns the rows separately to avoid ambiguous duplicate column names from the joined query.

`vpro_plot_update()`:

1. validates the plot identifier and named field lists;
2. rejects unknown fields, duplicate cross-table field names, plot-key changes, and values incompatible with declared SQLite types;
3. default-denies protected or derived Admin fields (`BECSiteUnit`, `HumusThickness`, and `StrataCoverTotal`) unless the explicit context callback grants `update_protected_plot_field`;
4. enforces the observed Access `StartDate` range of 1900 through 2500;
5. resolves user and audit strength from explicit arguments or context configuration;
6. opens the active SQLite file and enables foreign keys;
7. verifies exactly one Env row and one Admin row;
8. updates both rows inside one transaction;
9. rereads stored values after SQLite affinity conversion;
10. appends qualifying audit rows inside that same transaction;
11. returns the refreshed base rows and inserted audit rows.

Fields omitted from a request remain unchanged. A typed `NA` explicitly clears a nullable field. Requests containing an invalid field fail before mutation.

## Intentional differences

The package does not write through Access bound forms or mutable QueryDefs. It uses explicit named updates against SQLite base tables and a single transaction. This prevents a partially saved Env/Admin record or audit trail.

The package requires a stable user identity instead of reading Access registry state implicitly. It accepts an explicit `user` or `Current.User` from the context configuration.

Audit timestamps are stored in UTC. Access used local `Now()` values without timezone metadata.

Plot keys are immutable in this API. Access's bound-form behavior includes a `PlotNumber_AfterUpdate` event, but plot-number cascade and audit semantics require a separate reviewed operation.

## Deferred CRUD slices

Plot creation and deletion are deferred because the SaveAsText evidence establishes keys and cascades but does not expose a complete dedicated create/delete procedure contract. Audit restoration is deferred because it includes selection, optional audit-record removal, and vegetation cleanup semantics. Child-table and vegetation operations require stable row-identity decisions before mutation APIs are introduced.
