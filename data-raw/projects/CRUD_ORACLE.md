# CRUD Windows oracle evidence

## Scope and safeguards

These observations were collected on 2026-09-22 through `ssh win11vm` with Microsoft Access 16.0. Every mutating run copied
`C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64` to a new timestamped directory under
`C:\Users\sshadmin\AppData\Local\Temp`. The source `VPro64.accdb` SHA-256 was
`01481B94569C7172F32A812E65365F78CEA5E440DD63220D91A37DADE5778423`, and each initial copy matched it.

Temporary VBA modules were imported only into disposable copies. They opened the original bound forms and used their original event procedures. Production Access files were not modified.

Reusable successful probe sources are `data-raw/oracle/inventory.ps1`, `data-raw/oracle/modOracleProbe.bas`, `data-raw/oracle/run-vba-probe.ps1`, `data-raw/oracle/modPlotCreateProbe.bas`, `data-raw/oracle/run-plot-create-probe.ps1`, and `data-raw/oracle/restore-sql-probe.ps1`. They are migration evidence and are not package runtime code.

## Plot creation

The plot-creation probe opened the original `FS882-8x6XL` bound form on separate disposable copies. Its record source was `USysEnv`, an inner join from `Sample_Env.PlotNumber` to `Sample_Admin.Plot`; the form reported `AllowAdditions=True` and `DataEntry=False`. Each probe entered an explicit seven-character plot number. No form or table mechanism generated the plot number.

Directly committing only `PlotNumber` inserted one `Sample_Env` row but no `Sample_Admin` row. The new row was therefore absent from the joined `USysEnv` query immediately after commit. Populating an additional Env field such as `Location` produced the same orphan Env result. Populating tested Admin-bound controls (`PlotType` and `OfficeNotes`) before direct commit caused Access's bound join-form engine to insert both rows.

The normal focus-driven path is materially different. Moving focus from the newly entered `PlotNumber` to `Location` invoked `PlotNumber_LostFocus`. That handler briefly assigned the current year to Admin-bound `StartDate`, cleared it back to null, and saved. Dirtying the Admin side this way caused Access to create both Env and Admin rows even though `StartDate` ended null. The later explicit Admin repair block remained unreachable after `GoTo MyExit`.

At audit strength 2, direct commits produced no audit rows. The focus-driven path produced seven spurious `_Env` records for unbound checkbox control names `Check235`, `Check237`, `Check369`, `Check371`, `Check373`, `Check550`, and `Check552`; every `BeforeEdit` and `AfterEdit` value was null. These rows do not represent meaningful persisted field changes and should not be reproduced by a package API.

Creation created no vegetation, humus, mineral, or other child rows. The Env table defaulted `SV_FloodPlain` to false; tested `ProjectID`, `Date`, and Admin `StartDate` remained null. A dirty new record containing `PlotNumber` and `Location` was fully discarded by `acCmdUndo`, leaving no Env, Admin, Audit, or child rows.

A package-native plot-create operation should require an explicit caller-supplied plot number and transactionally insert exactly one Env row and one Admin row. It should apply canonical SQLite defaults, create no children, omit the meaningless Access checkbox audit rows, and leave no effects if validation or insertion fails. Optional initial Env/Admin values should be validated before the transaction. Plot deletion remains a separate unresolved lifecycle operation.

Reproducible results are retained in `plot-create-key-only.json`, `plot-create-env-only.json`, `plot-create-admin-only.json`, `plot-create-both-tables.json`, `plot-create-leave-key.json`, and `plot-create-cancel-dirty.json`. Every result records identical source-before, source-after, and initial-copy SHA-256 values.

## Plot-number renumbering

`FS882-8x6XL.PlotNumber_GotFocus` stores the original key, and the form contains intended confirmation and active-SU update code in `PlotNumber_BeforeUpdate` and `PlotNumber_AfterUpdate`. Both handlers begin with unconditional `Exit Sub`, however, so all confirmation, duplicate-specific messaging, and SU-update logic is unreachable in the observed version.

A disposable DAO probe changed `Sample_Env.PlotNumber` from `108050` to an unused key. Access's enforced update cascades moved the matching Admin row, 112 Audit rows, 43 Veg rows, one Humus row, three Mineral rows, and one Other row. It emitted no new audit record. The `Sample_SU` row remained under the old key because the SU relationship is not enforced and the intended form handler never executes.

Changing the same source to an existing plot failed with Access error 3399, `Cannot perform cascading operation. It would result in a duplicate key in table ''.` The complete old and target families remained unchanged.

The package should preserve the observed project-family cascade and no-audit behavior, but intentionally correct the stale SU membership defect. A package-native renumber operation should update every SU attached to the explicit context, including external SQLite files, in the same immediate SQLite transaction. It should reject source inconsistencies, existing or orphan target rows, and attached-SU source/target collisions before mutation. Unattached SU files cannot be discovered and remain outside the operation's scope.

Reproducible probe sources are `modPlotRenumberProbe.bas` and `run-plot-renumber-probe.ps1`; retained successful evidence is in `plot-renumber-dao-success.json` and `plot-renumber-dao-collision.json`. Every result records identical source-before, source-after, and initial-copy SHA-256 values. An attempted automated bound-form run encountered an Access modal and was abandoned without retaining evidence; the source handlers and DAO behavior establish the production contract without relying on that incomplete run.

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
