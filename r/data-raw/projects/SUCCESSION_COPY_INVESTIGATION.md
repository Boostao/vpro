# Succession vegetation copying: investigation only

**Status: disposable Access oracle completed; no copy API approved or implemented.** Canonical source: `../VPRO_ACCESS/VPro64_forAI/Modules/V7mdlSuccession.txt`, `CopySuccessionData` (lines 110–170) and `Check4DuplicateData` (lines 172–193). These are private procedures. A static search of the exported Access text found no caller; this does not prove they were never invoked through an unexported mechanism. The existing conversion oracle did not execute this routine.

## Observed source-code path (not runtime-verified)

The routine takes a plot and target year, reads the source year from an `InputBox`, and queries the active project's Veg table for that plot/source year. For each source row it checks `(PlotNumber, Species, NewYear)` in another dynaset. If no match is found, it inserts plot, year and species; of `Cover1` through `Cover7`, it sets **only the first non-null source cover column to zero**, not its source value. It does not explicitly set layer, the other cover values, heights, totals, collected status, ID or audit history. No explicit transaction or meaningful success count is present. The return value becomes true when any source rows exist, before inserts are attempted.

The duplicate branch does not advance the source recordset, so once a duplicate is encountered the remaining counted iterations revisit the same row. Errors are caught and displayed; earlier inserts can remain. Duplicate-lookup errors are suppressed and can lead to an attempted insert. Plot/species values are interpolated into SQL/DAO criteria. There is no explicit handling for same-year copies, prompt cancellation, invalid years, or null/blank species. The Access ID/default behavior for `AddNew` must be established in a disposable oracle; canonical SQLite `Sample_Veg.ID` is nullable and indexed, not auto-generated (`data-raw/projects/Sample_Veg.sql`).

## Disposable Windows Access oracle

On Access 16.0, `data-raw/oracle/run-succession-copy-probe.ps1` cloned the full front-end folder into a fresh VM temp directory **for each case**, copied eight populated `Sample_*` tables as `Oracle_*` into a separate backend, linked that backend into the clone, added the required Veg year field and selected `Oracle`. The test module `modSuccessionCopyProbe.bas` added isolated, tagged rows for plot `00337` and called a test-only adaptation of the two canonical private functions. The adaptation exposes `CopySuccessionData`, renames its functions to avoid collisions, substitutes an explicit source year for the `InputBox`, and captures messages/errors instead of showing modal dialogs. **The original iteration, duplicate lookup, insert and cover-assignment bodies were not changed.** This is a direct adapted-function probe, *not* a normal-UI invocation or proof of a production caller. The canonical front end remained at SHA-256 `01481B94569C7172F32A812E65365F78CEA5E440DD63220D91A37DADE5778423` and the canonical module at `D6EB938872691EE2FCC08551CC80E024B4AAAE716146DBA63CA611B7F4B6266A` before and after all five runs. The VM registry project settings were restored by the runner. Results: `data-raw/oracle/succession-copy-{covers,duplicate,duplicate-after,same-year,missing}.tsv`.

| Scenario | Observed result on disposable backend |
|---|---|
| Three source rows: multiple covers, `Cover2` first, and no covers | Returned true; three new rows got distinct generated signed IDs. Only the **first** non-null source `Cover1`–`Cover7` became zero, all other tested covers remained null, and no-cover source yielded a destination row with all tested covers null. Tested Layer, TotalA and Collected remained null. |
| First source species already in target year | Returned true, added no rows; later eligible source species was never reached. |
| Duplicate after one eligible source species | Returned true, kept the first new row with zero cover, then skipped a later eligible species after hitting the duplicate. No rollback occurred. |
| Source and target both 2020 | Returned true and added no rows, as the source rows already matched the duplicate test. |
| Source year with no rows | Returned false, captured the no-record message, and added no rows. |

In every case the plot's existing 14 audit rows remained at 14; the routine did not emit a new audit row in these fixtures. IDs varied across runs, so do not hard-code their values. The test did not establish generated-ID collision behavior, case/accent collation, unescaped quote handling, invalid prompt input, failure halfway through an insert, explicit null species, or a normal UI call site. In particular, replacing the year prompt means this evidence **does not** test prompt cancellation or invalid text. It demonstrates partial persistence after encountering a duplicate, not behavior after a genuine DAO exception.

## Proposed bounded next slice

Only after user approval, specify a package API for an explicit project/path, plot, source year and target year. Decide whether to intentionally correct the zero-cover and stuck-on-duplicate behaviors, whether to preserve other fields, the ID policy, duplicate collation, permissions/backup policy, and transactional semantics. Do not present those choices as established legacy parity. Succession schema conversion and recovery remain separate operations (`SUCCESSION_CONVERSION_DESIGN.md`).
