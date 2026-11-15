# Project relationship drift

## `_Env.StartDate` oracle finding

Investigated on 2026-09-22 against a disposable copy of
`C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64\VPro64.accdb` on the Windows
Access VM. The production working copy was not modified.

### Static evidence

`V7mdlRelationships.CreateRelationship` attempts to create relation
`<Project>6` from `<Project>_Env` to `<Project>_Metadata` using two fields:

- `ProjectID` to `ProjectID`
- `StartDate` to `StartDate`

The current Access schema does not contain `<Project>_Env.StartDate`.
`<Project>_Env.Date` is a Date/Time plot-collection date, while
`<Project>_Metadata.StartDate` is an Integer project year. The exported Access
relationship inventory contains no Env–Metadata relationship. `USysMetadata`
is a direct projection of the metadata table and does not join it to Env.

### Access oracle results

DAO inspection of the live schema found:

- `Sample_Env` contains `ProjectID` and `Date`, but no `StartDate`.
- `Sample_Metadata` contains `ProjectID`, `StartDate`, and `EndDate`.
- No relation connects `Sample_Env` to `Sample_Metadata`.

Replaying the `CreateRelationship` DAO sequence against a disposable database
copy appended relations `Sample1` through `Sample5`, then stopped while creating
`Sample6` with DAO error 3799:

> Could not find field 'StartDate'.

Because the VBA error handler exits the function, `Sample7` (Env–Admin) is not
created during that invocation. The operation is not transactional and leaves
the first five newly named relations in place.

DAO accepts either a ProjectID-only relation or a `Date` to `StartDate` relation
when relation attribute `2` is used, but this only demonstrates that a
non-enforced relation can be declared. It does not establish semantic validity.
Sample data confirms that `Date` is not a renamed `StartDate`: plot dates span
multiple years, whereas metadata StartDate is one project-level year.

### Migration disposition

Treat the Env–Metadata `StartDate` relationship as stale VBA, not as a missing
SQLite foreign key. Do not rename `Env.Date`, add `Env.StartDate`, or synthesize
a `Date`–`StartDate` relationship.

Canonical SQLite project schemas should continue to:

- retain `Env.Date` as the plot-collection timestamp;
- retain `Metadata.StartDate` as the project-year attribute;
- omit an Env–Metadata foreign key;
- declare valid project-family foreign keys directly in table schemas; and
- preserve those schema constraints transactionally during save-as.

This intentionally differs from the failing, non-transactional Access
relationship-repair routine while matching the observed Access database and its
exported relationship metadata.
