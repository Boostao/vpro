# Small deterministic helpers: source review

Source: `../VPRO_ACCESS/VPro64_forAI/Modules/` (SaveAsText). This review distinguishes individual functions from their containing workflows; no export or profile workflow is mapped as complete.

| Procedure | Callers and evidence | Decision |
|---|---|---|
| `V7mdlPlotProfiling.MadMax` (lines 11–30) | Used in `ProfileVeg`'s species `Any` and lumped `Any` SQL predicates (lines 178, 390); `SumAll` uses a different sum (line 206). Starts at zero, compares ten covers and returns `Single`. | `vpro_profile_max_cover()` implements the numeric maximum, with explicit missing-cover omission and double precision. VBA Null comparison behavior in Access SQL and complete plot selection are **not** claimed equivalent. |
| `V7mdlExportToR2.NullToPeriod` (lines 4–12) | Private helper called for Zone, SubZone and MoistureRegime only in `RunR`'s six-column output (lines 77–80). | `vpro_export_code()` substitutes periods only for missing character codes, not blank or whitespace-only text. Access passes through arbitrary non-Null Variants; R requires character. No file serialization or process launch. |
| `V7mdlUtility.SetTo99` (lines 433–440) | No production caller located in SaveAsText; unlike `vpro_cap_percent()` it caps at 99.9. | Deferred: no demonstrated use justifying another standalone capping API. |
| `V7mdlUtility.PadSpaces` and `JustR` (lines 460–495) | No direct production callers located. `JustR` returns length minus field width (including negative values) or empty string for Null; `PadSpaces` appends literal spaces without truncation. | Deferred as unused presentation helpers; their VBA coercion and error-handler behavior are not mapped. |
| `V7mdlExportCompactNew.JustTheFirstTwoWords` (lines 1169–1188) | Only a local `test` call found. Searches for two literal spaces; leading/repeated spaces matter and Null gives empty text. | Deferred: no located production caller; not equivalent to splitting on whitespace. |

The tests for the two mapped functions cover boundaries, missing inputs, invalid types, recycling and whitespace. They do not establish parity for the surrounding SQL, Access file output or UI effects.
