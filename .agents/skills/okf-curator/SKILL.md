---
name: okf-curator
description: Synchronizes the Operational Knowledge Framework (`okf/`), master index (`okf/00_index.md`), and decision ledger (`okf/04_evidence_and_sources/decisions_and_gaps.md`) after architectural changes, R export or Wails RPC additions, domain policy approvals, or before release commits, and enforces zero stray markdown sprawl.
---

# OKF Curator — Self-Curating Knowledge Sync Workflow

Follow [`okf/AGENTS.md`](../../../okf/AGENTS.md) whenever code, exports, Wails services, domain policies, or architectural specs change so `okf/` remains the single live source of truth at `HEAD`.

## When to Trigger

Run this curation pass in the same commit whenever you:
- Add, remove, or rename R exports in `r/NAMESPACE`, R modules in `r/R/*.R`, vignettes in `r/vignettes/`, or Quarto templates in `r/inst/quarto/`.
- Add, remove, or change Wails services (`app/main.go`), `app/internal/*` DAG layers, or active frontend views (`app/frontend/src/`).
- Approve, modify, or implement a domain oracle or product policy in `okf/02_present_state/oracles/`.
- Ship a design previously documented under `okf/03_future_architecture/` or resolve a `D-XX` decision item.
- Prepare a release or merge commit.

## Step-by-Step Curation Protocol

1. **Prevent stray markdown sprawl:**
   - Do not leave ad-hoc `*.md` notes in `app/`, `r/`, `site/`, `docs-src/`, or `scripts/`.
   - Consolidate active domain/engineering facts into the appropriate `okf/02_present_state/` or `okf/05_engineering_and_agents/` file, or move superseded prototype notes to `archive/` only if historical provenance is explicitly needed.
2. **Update `02_present_state/` & `05_engineering_and_agents/` in place:**
   - Overwrite stale counts (e.g., `r/NAMESPACE` export counts, `r/R/*.R` file counts, vignette counts, Wails service counts), symbol names, file paths, and `Status:` banners directly in place.
   - Never append dated "update logs" to present-state specifications.
   - Graduate any newly implemented feature out of `okf/03_future_architecture/` into `okf/02_present_state/` and update links accordingly.
3. **Record settled decisions in `decisions_and_gaps.md`:**
   - Log or update numbered **`D-XX`** ADR entries in `okf/04_evidence_and_sources/decisions_and_gaps.md` (including its summary Mermaid graph) with status, file references, and exact parameter/policy invariants.
4. **Refresh `okf/00_index.md`:**
   - Ensure the `**Audit Baseline Date:**` header, summary metrics (including `` `<N>` exports `` matching `r/NAMESPACE`), directory manifest tree, and module table match `okf/` on disk, and verify every `.md` file under `okf/01_*`..`okf/05_*` is indexed.
5. **Run mechanical hygiene verification:**
   ```bash
   python3 scripts/check-okf-hygiene.py
   python3 -m unittest discover -s scripts/tests -p 'test_*.py'
   ```
   Fix any reported allowlist violation, rule byte-budget breach (`>= 24,000` bytes), missing index reference, broken relative link, or `vpro_wails` / policy drift before committing.
