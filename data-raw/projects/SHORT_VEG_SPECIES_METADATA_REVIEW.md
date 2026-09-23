# Short-vegetation species metadata review

## Purpose and current state

`SHORT_VEG_SPECIES_CONFLICT_CANDIDATES.csv` is a **read-only review inventory**, not a resolved species list and not an approval record. It reproduces the Access-style five-field `UNION` candidate population from bundled `VLists.db::USysAllSpecs` and `VUser.db::USysUserSpp`: values with `Codetype = 's'` are excluded case-insensitively, NULL `Codetype` values are excluded as they are by an Access `<>` predicate, identical `(Code, ScientificName, Lifeform, EnglishName, Codetype)` tuples are deduplicated, and only normalized codes with more than one remaining tuple are included. `source_provenance` identifies the source database/table contributing each tuple.

The inventory currently has **72 pending rows in 35 normalized-code groups**. It has **no reviewed resolution**: every row has `status = pending`, and `reviewer`, `review_date`, and `rationale` are intentionally blank. No row implies a preferred, accepted, current, or approved metadata value.

`sample_veg_usage_count` is a read-only count of `Sample.db::Sample_Veg` records grouped case-insensitively by normalized species code. Two used conflict keys require a unique review decision before they could be used in a downstream short-vegetation metadata presentation:

| Normalized code | Candidate rows | Sample_Veg records |
|---|---:|---:|
| `ANEMRIC` | 2 | 2 |
| `CAMPHIP` | 2 | 2 |

The four corresponding candidate rows remain pending; these counts do not choose between them.

## Reproducible build and source validation

From the package root, regenerate the inventory with R:

```r
source("data-raw/projects/build-short-veg-species-conflicts.R")
```

The build opens all source SQLite databases using `mode=ro`, reads only `USysAllSpecs`, `USysUserSpp`, and `Sample_Veg`, and makes no canonical database changes. Before review or application of a review decision, validate the exact bundled source versions against these SHA-256 fingerprints:

| Source | Bytes | SHA-256 |
|---|---:|---|
| `inst/extdata/VLists.db` | 4,427,776 | `dd80135e45878d92dee626701ba29bd4cc1d69549d6784c2a91dc276f6a79a51` |
| `inst/extdata/VUser.db` | 155,648 | `19c8cf4d7b0cfae2ad141b5f02918de0428ad1dd1f27d3f3c8b40ca48874d4e8` |
| `inst/extdata/projects/Sample.db` | 503,808 | `e63f0c2a051761701bdad3c81bcfde4067ab322883c7e4ac84a3541ae8578ad8` |

A fingerprint mismatch requires rebuilding the inventory and repeating review for affected code groups; do not carry a decision forward by assumption.

## Strict review workflow

1. Confirm the three source fingerprints and regenerate the CSV from the reviewed revision.
2. Review all rows for one normalized code together, preserving the five source fields and provenance as evidence.
3. For each **used** normalized code, record exactly one explicitly selected candidate tuple in a separately governed override record. Selection requires a named reviewer, review date, rationale, source fingerprint set, and the complete selected five-field tuple.
4. Do not infer a selection from row order, source priority, most frequent use, spelling, or a CSV edit. There is no automatic pick.
5. Store approved overrides non-destructively: retain this generated candidate inventory unchanged, retain every unselected candidate and provenance, and keep overrides outside canonical `VLists.db`, `VUser.db`, and `Sample.db`.
6. Revalidate the override against its candidate tuple and the source fingerprints whenever it is consumed. Reject missing, ambiguous, stale, or fingerprint-mismatched selections.

Codes not used by `Sample_Veg` may remain pending. A used key without exactly one valid reviewed override must remain unresolved and must not be silently converted into a display or export value.
