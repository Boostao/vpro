# VPRO deterministic parity inventory

A **base R only** developer tool for indexing canonical Access text exports and static R targets. It does not execute Access VBA or target R code, and generated files contain no timestamps.

```sh
Rscript data-raw/parity/run_inventory.R \
  --source "/path/to/VPro64_forAI" \
  --target "/path/to/vpro" \
  --output data-raw/parity/generated
```

`--source` may instead be supplied as `VPRO_PARITY_SOURCE`; `--target` defaults to the current directory and can use `VPRO_PARITY_TARGET`. The tool discovers only `Forms`, `Modules`, `Queries`, `Reports`, `Macros`, `Tables_Def`, `Relationships`, and `Tables_Design`, excluding `FORM_IMPL_SPEC_*.md` and `ui_*.R`.

## Outputs

- `manifest.csv`: stable object IDs, source-relative paths, byte sizes, detected encoding, and `md5` hashes. MD5 is an integrity identifier, **not** a security claim.
- `source-items.csv`, `query-sql.csv`: object/procedure/event/macro inventory and decoded static query text.
- `target-items.csv`: statically parseable R functions and `test_that()` declarations.
- `parity.csv`, `unresolved.csv`: one row per source object, procedure, event, and macro action, with broad rules-based domain/classification. Exact symbol matches are only `candidate` mappings until reviewed. Curated mappings in `reviewed-overrides.csv` are validated against stable source and target IDs and removed from `unresolved.csv`.
- `summary.json`, `discrepancy-tree.mmd`, and `discrepancy-tree.md`: aggregate discrepancy counts.
- `tree-index.csv` and `trees/*.mmd`: detailed deterministic trees for every Access object.

## Scope limits

VBA parsing is lexical rather than a VBA compiler: declarations and simple risk flags are detected, not evaluated. Event control association follows nearby Access `Name` properties and can be ambiguous in nested `Begin` sections. Query SQL reconstruction handles quoted `dbMemo "SQL"` fragments and `\015`/`\012` escapes; dynamically assembled SQL is intentionally not inferred. Target function inventory uses `parse()`/`getParseData()` and skips malformed R files.
