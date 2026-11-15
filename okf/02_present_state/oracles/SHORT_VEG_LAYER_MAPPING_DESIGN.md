# Short-vegetation layer mapping design

## Scope and provenance

`short-veg-layer-mapping-v1.sqlite` in this directory is the versioned source
build artifact. An approved **runtime copy** is bundled at
`inst/extdata/short-veg-layer-mapping-v1.sqlite` for the bounded
`vpro_report_short_veg_layers()` data API. Neither file replaces an Access
database or confers taxonomic review. Regenerate the source artifact from the
package root with:

```r
source("data-raw/projects/build-short-veg-layer-mapping.R")
build_short_veg_layer_mapping()
```

Sourcing defines the builder only; it does not regenerate the artifact. The builder validates
both sources before creating a temporary SQLite file in the output directory, validates that
file, and only then replaces the requested output. Invalid input therefore leaves an existing
output unchanged. After validating the new source artifact and its metadata,
copy it to `inst/extdata/short-veg-layer-mapping-v1.sqlite` and run the API
tests. Runtime validates `mapping_set.version = access-layercode-v1`, CSV SHA-256
`8a03d48c3a7f0e0a2e0868569969ad91603b124ce38febb38b5a3b284e99d510`,
17 mapping rows and the report key/code/strata pairs. The copy is opened read-only;
there is no runtime regeneration.

The builder reads `data-raw/vpro/LayerCode.csv` as text and validates it
against `data-raw/vpro/LayerCode.sql`. It retains the Access column names
unchanged: `LayerCode`, `Layer1234567`, `LayerCompact`, `Layer`, `LayerText`,
`Strata`, `StrataNum`, and `Lifeform`. Empty CSV fields become SQL `NULL`;
text keys such as `"01"` remain text. The supplied file has 17 nonblank data
rows; its final physical line is blank and is not a record. The artifact records the source CSV
SHA-256 (of the CSV file contents), repository-relative source path
(`data-raw/vpro/LayerCode.csv`), mapping-set version, migration intent, and fixed creation
date (`2026-09-23`). SQLite file bytes are not a reproducibility
contract: regeneration must instead validate tables, row counts, constraints,
and metadata.

The short-vegetation layer/strata oracle documents the source behavior in
`SHORT_VEG_LAYER_STRATA_ORACLE.md`. It observed that generated report keys
join `LayerCode.Layer1234567`, while some legacy Access lifeform SQL joins the
padded `LayerCode.LayerCode` key. For example, the report key `1` must join
`Layer1234567 = "1"`, not `LayerCode = "01"`.

## Intentional modernization and limits

A downstream mapping consumer must intentionally join short-vegetation report
keys to `layer_mapping.Layer1234567`. This corrects the observed legacy
lifeform join-key mismatch; it does **not** claim full Access report parity.
The `Lifeform` column is retained only as source evidence. Species `LifeForm`
for a modern report must come from reviewed species metadata, not this mapping
or an unreviewed legacy join.

This artifact provides no default legacy emulation. It neither changes the
source CSV/SQL contract nor resolves taxonomy. Taxonomy review remains a
caller-governed decision under `SHORT_VEG_SPECIES_METADATA_REVIEW.md`.
