# Report quality-filter contract

## Access evidence

The canonical source is `V7mdlReportsQualityControl`, principally `QC`, `QCLV`,
`FillRemovedBy`, `SetLevels`, and `LevelAsNumber`.

Both filters require the current site-unit table. They join that SU to the
current `USysEnv` Env-Admin relation and retain rows meeting inclusive Site,
Vegetation, and Soil quality thresholds. Threshold ranks come from
`USysTableOfLists` rows where `ListName = DataQuality`. The canonical order is
Poor 1, Fair 2, Good 3, and Excellent 4.

Each quality dimension has an independent include-null setting. Because Access
left-joins the quality text to the complete list table, a label absent from every
list follows the same branch as a null label. A label belonging to another list
is excluded by the `ListName = DataQuality Or ListName Is Null` predicate. The
filter does not trim or normalize source quality values.

`QCLV`, used by the long-vegetation report, checks only Site, Vegetation, and
Soil quality. `QC`, used by the short-vegetation report, also applies
`BEC_Use >= threshold` directly to text. It does not use the BEC list's numeric
`ItemOrder`. This lexical direction is preserved even though larger canonical
BEC codes generally describe lower-quality or less-usable plots.

When filtering is disabled, Access copies the original SU unchanged. When it is
enabled, Access creates `USysDeleteMe_SU`, changes the current plot-list registry
state after success, and returns false if no plots pass. Report cleanup later
restores the original selection and deletes the temporary table.

`FillRemovedBy` builds a persistent temporary report table and assigns Site,
Veg, Soil, BEC, or Mixed reasons. Its diagnostics use hard-coded quality ranks,
ignore null exclusion settings, and compare removals after subsequent report
transformations, so they can misattribute non-quality removals.

## Package API

`vpro_filter_plot_quality()` requires an active project and active SU. It accepts
explicit thresholds and null-handling flags instead of reading registry-backed
report options. It returns:

- `selected`: deterministic `PlotNumber` and `SiteUnit` rows;
- `removed`: original quality values, a primary `removed_by` reason, and all
  `failed_criteria`;
- `thresholds`: resolved labels, ranks, BEC threshold, and missing-value options.

`bec_min = NULL` represents long-report `QCLV` behavior. Supplying `bec_min`
enables the short-report BEC predicate. The package uses deterministic
case-insensitive UTF-8 lexical comparison as a portable approximation of Access
database text comparison. Exact locale and accent equivalence is not claimed.

Data-quality list names and threshold labels are matched case-insensitively.
Duplicate labels, missing lists, non-finite ranks, invalid thresholds, and
missing required Admin fields fail explicitly rather than surfacing DAO lookup
or SQL errors. Long-report mode does not require `BEC_Use`. Missing plot quality
values and labels absent from all lists retain the Access joined-null behavior;
labels belonging to another list fail that criterion, matching the full Access
join.

Unlike Access, the package does not create temporary tables, mutate the active
SU, or rely on registry state. An SU row lacking a complete Env-Admin pair is
returned as a `Project` removal instead of disappearing silently through the
inner join. Criterion diagnostics use the actual filter result and null flags;
multiple failures are labeled `Mixed`. Disabled filtering returns the complete
active SU without consulting list metadata or requiring Admin quality fields.

The operation is read-only and supports same-file or external active SUs without
changing context attachment ownership.
