# Environmental plot CRUD specification

## Implemented scope

Package-native plot-domain CRUD is implemented in `R/plot-crud.R`, `R/plot-child.R`, `R/plot-other.R`, `R/plot-soil.R`, and `R/plot-vegetation.R`:

- `vpro_plot_create()` validates initial values and transactionally creates one paired Env/Admin plot without audit or child rows;
- `vpro_plot_renumber()` transactionally changes one plot key across the canonical project family and every SU attached to the context;
- `vpro_plot_delete()` transactionally removes one complete plot family and its membership from every SU attached to the context;
- `vpro_plot_get()` reads one active project's paired Env and Admin rows;
- `vpro_plot_audit_list()` reads that plot's canonical audit history without modifying it and exposes complete one-row event selections with SQLite `audit_rowid` locators;
- `vpro_plot_audit_restore()` transactionally restores one audited field from its recorded `BeforeEdit` value, preserving the audit event by default;
- `vpro_plot_update()` validates requested fields, updates Env and Admin in one SQLite transaction, and writes field-level Audit rows in the same transaction;
- `vpro_plot_other_list()` reads one plot's `_Other` child rows;
- `vpro_plot_other_update()` updates one existing `_Other` row and writes child-ID audit records in the same transaction;
- `vpro_plot_humus_list()` and `vpro_plot_mineral_list()` read one plot's soil child rows in their respective Access form orders;
- `vpro_plot_humus_get()` and `vpro_plot_mineral_get()` read one existing soil row by plot and child ID;
- `vpro_plot_humus_update()` and `vpro_plot_mineral_update()` update one existing soil row and write child-ID audit records in the same transaction;
- Other, Humus, and Mineral `create()`/`delete()` APIs reproduce oracle-observed child-row lifecycle behavior;
- vegetation list, get, create, update, and delete APIs use guarded project/plot/ID identity and `_Veg` audit rows.

The APIs are independent of Shiny and require an explicit active project context. They read and write canonical SQLite base tables, not DuckDB compatibility views. Committed writes are immediately visible through the active compatibility views.

Multi-event audit selection is intentionally outside the implemented milestone.

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

`vpro_plot_create()` requires an active VP08 project, an explicit unused plot number, and optional named Env/Admin values. It validates fields and SQLite types before mutation, applies the existing protected-Admin authorization policy, acquires an immediate SQLite write transaction, and then checks and inserts Env followed by Admin. Concurrent creators therefore serialize before collision detection. Existing complete pairs receive a collision error; legacy Env-only or Admin-only rows receive a distinct integrity error and are never repaired implicitly. Omitted columns retain SQLite defaults such as false `SV_FloodPlain`. Creation returns the stored pair, writes no audit or child rows, and does not change active SU, hierarchy, or configuration state. Under an active SU, the new base plot remains accessible through `vpro_plot_get()` but is absent from the filtered `USysEnv` view until separately added to that SU.

This intentionally replaces Access's focus-sensitive behavior. The package always creates a valid pair rather than allowing key-only or Env-only orphan rows, and it omits the seven null-to-null checkbox audit rows emitted by the normal `FS882-8x6XL` focus path.

`vpro_plot_renumber()` requires an active VP08 project, one complete source Env/Admin pair, and an unused target key. It acquires an immediate transaction and updates the canonical Env key once; SQLite's enforced relationships cascade the key to Admin, Audit, Veg, Humus, Mineral, and Other. The operation verifies that every source count moved unchanged and that no foreign-key violations remain. It writes no new audit event, matching the Windows oracle.

Every SU currently attached to the explicit project context participates in the same transaction. Same-file and external SQLite SU tables are preflighted for target collisions, updated explicitly, and verified before commit. This intentionally corrects `FS882-8x6XL.PlotNumber_AfterUpdate`: its active-SU update code is unreachable after an unconditional `Exit Sub`, leaving legacy SU membership stale. Unattached SU files cannot be discovered and are not modified. Active SU filtering remains selected, and committed membership is immediately visible through `USysEnv`.

`vpro_plot_delete()` requires an active VP08 project and exactly one Env/Admin pair. It deletes the canonical Env row in an immediate transaction and relies on enforced relationships to remove Admin, Audit, Veg, Humus, Mineral, and Other rows. This includes deletion of the plot's complete audit history and creates no replacement audit event, matching both the bound-form and DAO Windows probes. Matching membership rows are removed explicitly from every same-file or external SU attached to the context in the same transaction; an external-SU failure rolls back the project cascade. Unattached SU files cannot be discovered. Project, active-SU, hierarchy, and configuration selections remain unchanged, while SU diagnostics are refreshed after commit.

`vpro_plot_get()` requires an active VP08 project and exactly one matching Env row and Admin row. It reads directly from the active project's SQLite file and returns the rows separately to avoid ambiguous duplicate column names from the joined query.

`vpro_plot_audit_list()` requires an existing plot in the active project, reads its rows directly from the canonical `_Audit` table, and returns all columns—including `Restore`, `Flag`, and child `ID`—without mutation. It also returns `audit_rowid`, the SQLite row identifier used to select one event from a specific database file. It follows `USysAuditTrail` by sorting chronologically on `EditWhen`; child ID and SQLite row order make timestamp ties deterministic. Explicit project and plot predicates replace the saved `USysAudit` form's Access function call and hard-coded design-time plot value.

`vpro_plot_audit_restore()` applies a bounded correction to Access's defective restoration path. It accepts one complete row selected from `vpro_plot_audit_list()`, looks it up by `audit_rowid` and active project/plot, and verifies the full event contents before mutation because SQLite row IDs alone are not durable identities. It resolves `_Env` fields against both physical Env and Admin schemas and requires exactly one schema match. `_Other`, `_Humus`, `_Mineral`, and `_Veg` targets require a nonmissing signed 32-bit child ID and exactly one `(PlotNumber, ID)` row. Key fields and unsupported suffixes are rejected. Recorded text is converted according to the target SQLite declaration and validated through the normal plot write rules.

Before mutation, the target's current stored value must equal the audit event's `AfterEdit` value. This optimistic guard prevents restoration of an older event from overwriting later work. Exactly one existing field is restored to `BeforeEdit` in a SQLite transaction. The source audit event is retained by default; `delete_audit = TRUE` deletes it in the same transaction, so a deletion failure rolls back the field change. Protected Admin fields retain `update_protected_plot_field` authorization. Restoration does not create missing child rows, append a second audit event, or delete vegetation rows that become sparse. Unlike the legacy routine, vegetation cover fields are eligible because they are ordinary typed fields under this one-field contract.

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

Plot keys remain immutable in ordinary update APIs. `vpro_plot_renumber()` is the separate reviewed operation for coordinated key changes. It follows Access's enforced project-table cascades and no-audit behavior while updating all explicitly attached SUs rather than reproducing the legacy form's unreachable handler.

## Deferred CRUD slices

Multi-event restoration and UI selection remain deferred. The package deliberately does not reproduce Access's broken Admin target resolution, legacy skipping of vegetation cover fields, or implicit empty-vegetation cleanup. Each package call restores one explicitly selected event and one existing field; callers may compose higher-level review workflows only after choosing their own ordering and failure policy.
