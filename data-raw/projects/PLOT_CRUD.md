# Environmental plot CRUD specification

## Implemented scope

Package-native plot-domain CRUD is implemented in `R/plot-crud.R`, `R/plot-child.R`, `R/plot-other.R`, `R/plot-soil.R`, and `R/plot-vegetation.R`:

- `vpro_plot_get()` reads one active project's paired Env and Admin rows;
- `vpro_plot_audit_list()` reads that plot's canonical audit history without modifying it;
- `vpro_plot_update()` validates requested fields, updates Env and Admin in one SQLite transaction, and writes field-level Audit rows in the same transaction;
- `vpro_plot_other_list()` reads one plot's `_Other` child rows;
- `vpro_plot_other_update()` updates one existing `_Other` row and writes child-ID audit records in the same transaction;
- `vpro_plot_humus_list()` and `vpro_plot_mineral_list()` read one plot's soil child rows in their respective Access form orders;
- `vpro_plot_humus_get()` and `vpro_plot_mineral_get()` read one existing soil row by plot and child ID;
- `vpro_plot_humus_update()` and `vpro_plot_mineral_update()` update one existing soil row and write child-ID audit records in the same transaction;
- Other, Humus, and Mineral `create()`/`delete()` APIs reproduce oracle-observed child-row lifecycle behavior;
- vegetation list, get, create, update, and delete APIs use guarded project/plot/ID identity and `_Veg` audit rows.

The APIs are independent of Shiny and require an explicit active project context. They read and write canonical SQLite base tables, not DuckDB compatibility views. Committed writes are immediately visible through the active compatibility views.

Plot creation, plot-number changes, plot deletion, audit selection, and audit restoration are intentionally outside this milestone.

## Canonical Access evidence

Primary sources are:

- `Queries/UsysEnv.txt`;
- `Forms/FS882-1x1.txt`, especially `Form_BeforeUpdate`, `btnSaveRecord_Click`, and `ProjectID_LostFocus`;
- `V7mdlAudit.AuditTrail` and `V7mdlAudit.TableName`;
- `Queries/UsysOther.txt` and `Forms/SubOtherXL.txt`, especially `Form_BeforeUpdate`;
- `Queries/UsysHumus.txt`, `Queries/UsysMineral.txt`, and the `SoilHumus` and `SoilMineral` forms, especially their ordering and `Form_BeforeUpdate` events;
- `Queries/UsysVeg.txt`, `Queries/USysVegA.txt`, and `Forms/SubVegAXL.txt`;
- `Sample_Env`, `Sample_Admin`, `Sample_Audit`, `Sample_Other`, `Sample_Humus`, `Sample_Mineral`, and `Sample_Veg` table definitions;
- canonical Env relationships to Admin, Audit, Humus, Mineral, Other, and Veg;
- controlled Windows Access observations documented in `CRUD_ORACLE.md`.

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

`vpro_plot_audit_list()` requires an existing plot in the active project, reads its rows directly from the canonical `_Audit` table, and returns all columns—including `Restore`, `Flag`, and `ID`—without mutation. It follows `USysAuditTrail` by sorting chronologically on `EditWhen`; audit ID and SQLite row order make timestamp ties deterministic. Explicit project and plot predicates replace the saved `USysAudit` form's Access function call and hard-coded design-time plot value.

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

`vpro_plot_other_list()` requires an existing paired Env/Admin plot, reads the active project's `_Other` table, and returns all stored columns ordered by `DataName` and then stable child `ID`. It reads base-project membership even when an active SU filters the `USysEnv` compatibility view.

`vpro_plot_other_update()` identifies exactly one existing row by `(PlotNumber, ID)`, rejects key changes and invalid fields or values, updates the row transactionally, rereads stored values, and appends qualifying `_Other` audit rows carrying that child ID.

The Humus and Mineral APIs apply the same existing-row identity, validation, transaction, and audit contract. Humus rows are ordered by descending `UpperDepth` and `Horizon`; Mineral rows are ordered by ascending `UpperDepth` and `Horizon`. Stable `ID` ordering resolves ties. The `get()` operations make the `(PlotNumber, ID)` identity explicit without exposing mutable form state. Updates write `_Humus` or `_Mineral` audit suffixes and preserve the child ID used by Access restoration logic.

Child creation uses collision-checked signed 32-bit IDs. At audit strength 2 or 3, every populated stored non-key field is recorded with the generated ID in the same transaction. Other creation supplies Access-observed false defaults for `UserFlag1` through `UserFlag3`. Child deletion first requires exactly one `(PlotNumber, ID)` row and writes no audit record, matching the observed Access bound-form behavior.

Vegetation rows use `(PlotNumber, ID)` as a guarded operational locator. The Windows oracle showed that ID remains stable across species edits but Access permits duplicate IDs even within one plot. Every vegetation get, update, and delete therefore requires exactly one match and rejects ambiguous imported data. Creation requires a nonblank species of at most eight characters and generates an unused project-level ID. Updates and creation write `_Veg` audit rows under the standard strength rules.

## Intentional differences

The package does not write through Access bound forms or mutable QueryDefs. It uses explicit named updates against SQLite base tables and a single transaction. This prevents a partially saved Env/Admin record or audit trail.

The package requires a stable user identity instead of reading Access registry state implicitly. It accepts an explicit `user` or `Current.User` from the context configuration.

Audit timestamps are stored in UTC. Access used local `Now()` values without timezone metadata.

Plot keys are immutable in this API. Access's bound-form behavior includes a `PlotNumber_AfterUpdate` event, but plot-number cascade and audit semantics require a separate reviewed operation.

## Deferred CRUD slices

Plot creation, plot-number changes, and plot deletion remain deferred because their multi-table cascade, authorization, and audit contracts have not been observed.

Audit restoration remains deferred by design after oracle review. Access records Admin edits through joined FS882 forms as `_Env`, but `RestoreTo()` opens the physical Env table, where Admin fields do not exist; an `_Admin` suffix has no SQL branch. The package must not reproduce this defect. A future restore API should resolve an `_Env` audit field against the physical Env and Admin schemas, require exactly one match, restore transactionally, preserve audit rows by default, and explicitly handle child rows, skipped vegetation cover fields, and empty-vegetation cleanup.
