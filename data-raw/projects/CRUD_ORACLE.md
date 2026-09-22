# CRUD Windows oracle evidence

## Scope and safeguards

These observations were collected on 2026-09-22 through `ssh win11vm` with Microsoft Access 16.0. Every mutating run copied
`C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64` to a new timestamped directory under
`C:\Users\sshadmin\AppData\Local\Temp`. The source `VPro64.accdb` SHA-256 was
`01481B94569C7172F32A812E65365F78CEA5E440DD63220D91A37DADE5778423`, and each initial copy matched it.

Temporary VBA modules were imported only into disposable copies. They opened the original bound forms and used their original event procedures. Production Access files were not modified.

Reusable successful probe sources are `data-raw/oracle/inventory.ps1`, `data-raw/oracle/modOracleProbe.bas`, `data-raw/oracle/run-vba-probe.ps1`, and `data-raw/oracle/restore-sql-probe.ps1`. They are migration evidence and are not package runtime code.

## Child creation and deletion

The probe opened `SubOtherXL`, `SoilHumusXL`, `SoilMineralXL`, and `SubVegAXL`. All four reported `AllowAdditions=True` and `AllowDeletions=True`. Their record sources were `UsysOther`, `UsysHumus`, `UsysMineral`, and `USysVegA` respectively.

Creating rows through these bound forms generated signed 32-bit IDs while the row was still dirty. Representative IDs were `1790097051`, `825842496`, `-1089435071`, and `2103358318`. The ID remained unchanged after commit. Canceling a dirty new Other row discarded it.

At audit strength 2, creation produced field-level audit records with the generated child ID:

- Other: `DataName`, `DataItem`, and defaulted `UserFlag1` through `UserFlag3`;
- Humus: `Horizon` and `Comment`;
- Mineral: `Horizon` and `Comments`;
- vegetation: `Species` and `Cover1`.

The general `Flag` field was not defaulted or audited. Deleting each newly created row through the bound form produced no additional audit records. Access supplied its standard record-deletion confirmation because no form-specific before/after-delete handlers were defined; the automated probe suppressed that UI confirmation but exercised `acCmdDeleteRecord`.

Duplicate explicit IDs were rejected with Access error 3022 for Other, Humus, and Mineral because those tables have unique ID indexes. Vegetation accepted duplicate IDs, including duplicate `(PlotNumber, ID)` values, because its ID index is non-unique.

The field default text is `GenUniqueID()`. Calling `Eval("GenUniqueID()")` directly returned Access error 2425, but bound-form insertion evaluated the field default successfully. The package therefore reproduces the observed outcome rather than depending on a callable VBA function: it generates a random signed 32-bit ID and checks the target table for collisions before insertion.

## Vegetation identity

The bundled canonical SQLite database contains 1,633 vegetation rows. It has no duplicate `ID`, `(PlotNumber, ID)`, or `(PlotNumber, Species)` values, but these are data observations rather than schema guarantees. `Layer` is null in all bundled rows.

The Access oracle showed that a vegetation row retained its ID after changing `Species`. `V7mdlAudit.AuditTrail` stored that same ID on both creation and species-edit audit rows. Therefore `ID`, scoped by project and plot, is the operational row identifier.

However, Access accepted duplicate IDs in the same plot. Package vegetation get, update, and delete operations must therefore query by `(PlotNumber, ID)` and require exactly one matching row. They must reject ambiguous imported legacy data rather than update or delete multiple rows. The package-generated IDs are collision-checked against the whole project vegetation table.

## Env/Admin audit restoration

`FS882` edits both physical Env and Admin columns through joined `USysEnv`, while `V7mdlAudit.TableName()` labels the form `_Env`. `RestoreAuditRecords()` passes `CurrProject & "_Env"` to `RestoreTo()`.

The exact `RestoreTo()` SQL for `_Env` opens the physical `<project>_Env` table by `PlotNumber`. A controlled Access DAO probe confirmed that an Env field such as `Location` exists in this target, while an Admin field such as `PlotType` does not. An `_Admin` suffix produces no SQL branch at all and Access fails opening an empty table/query name.

Consequently, the legacy routine can restore physical Env fields but cannot restore Admin fields recorded through the joined form. A mislabeled Admin audit row targets the wrong physical table and fails on the missing field. This is a legacy defect, not a contract to reproduce.

A package-native restore API should intentionally resolve `_Env` audit fields against both physical schemas: exactly one matching Env or Admin field is eligible; unknown or ambiguous fields must fail before mutation. Restoration should remain transactional, preserve audit rows by default, and expose explicit deletion of successfully restored audit rows as an option. Child restoration must continue to require `(PlotNumber, ID)`. Cover-field vegetation audit rows remain skipped by the legacy routine, and vegetation cleanup behavior requires a separately bounded implementation decision.
