# Access Form (`SaveAsText`) to Shiny UI generator

Script: `scripts/Tools/access_form_to_shiny.R`

## What it does

- Input: Access exported form text file (`<form>.txt`) or a folder containing many form exports.
- Output: `ui_<form>.R` Shiny UI file.
- Preserves (best effort):
	- Control names (stored as IDs where possible and always as `data-access-name`)
	- Absolute position and size
	- Visual control ordering
	- Tab navigation hints (`TabIndex`/`TabStop` when explicitly available)
- Adds migration-focused fidelity helpers:
	- UI scaling (`--scale=...`) to reduce overlap/compression in Shiny rendering
	- Z-index layering by control traversal order
	- Access color integer conversion to CSS hex (`#RRGGBB`) for many controls
	- Font mapping (`FontSize` to `em`, `FontWeight`, `FontName`)
	- Form scrollbar mapping (`ScrollBars` to CSS overflow)
	- `OptionGroup` rendering as grouped `radioButtons` choices (from child `OptionButton` controls)
	- Access `Tab` / `Page` support via Shiny tab selector (`tabsetPanel`) with per-page conditional rendering
	- `Subform` recursive rendering by resolving sibling form exports (for example `Name = "frmVPics"` -> `frmVPics.txt`)
	- Configurable z-order strategy (`--zorder=natural|reverse`, default `natural`)
	- Access caption mnemonic support (`&X` -> underlined `X`, `&&` -> literal `&`)
	- Controls with `[Event Procedure]` are emitted as native Shiny inputs/buttons where possible (`textInput`, `selectInput`, `checkboxInput`, `actionButton`) for interactive server bindings
- Does **not** migrate VBA/event logic implementation.

## Usage

Single form:

```bash
Rscript scripts/Tools/access_form_to_shiny.R VPRO_ACCESS/VPro64_forAI/Forms/frmDirectories.txt
```

Single form with explicit scale (recommended for dense forms):

```bash
Rscript scripts/Tools/access_form_to_shiny.R --scale=1.8 VPRO_ACCESS/VPro64_forAI/Forms/FS882-6x4XL.txt
```

Single form with explicit output path:

```bash
Rscript scripts/Tools/access_form_to_shiny.R VPRO_ACCESS/VPro64_forAI/Forms/frmDirectories.txt VPRO_ACCESS/VPro64_forAI/Forms/ui_frmDirectories.R
```

All forms in a directory:

```bash
Rscript scripts/Tools/access_form_to_shiny.R VPRO_ACCESS/VPro64_forAI/Forms
```

All forms with scaling:

```bash
Rscript scripts/Tools/access_form_to_shiny.R --scale=1.8 VPRO_ACCESS/VPro64_forAI/Forms
```

Force reverse stacking order (if needed for specific forms):

```bash
Rscript scripts/Tools/access_form_to_shiny.R --scale=1.8 --zorder=reverse VPRO_ACCESS/VPro64_forAI/Forms/FS882-6x4XL.txt
```

## Notes

- Access text exports are often UTF-16; the script auto-detects BOM/encoding.
- The generated UI is an absolute-position layout scaffold intended for migration kickoff.
- Controls with limited native Shiny equivalents (e.g., image/attachment frames) are emitted as placeholders.
- `Subform` controls attempt recursive conversion; if the target `.txt` is missing or recursive, a placeholder is emitted.
