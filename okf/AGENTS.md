# `okf/` — Self-Curating Operational Knowledge Framework Protocol

**Read root [`../AGENTS.md`](../AGENTS.md) and [`./00_index.md`](./00_index.md) before editing any specification.** Every engineering change that alters architecture, exports, Wails RPCs, or settled domain policies must leave `okf/` synchronized in the same commit.

## 1. Zero Stray Markdown Rule (Enforced Allowlist)

- **Never create ad-hoc `.md` notes** (`*_NOTES.md`, `*_AUDIT.md`, `*_DESIGN.md`, `TODO.md`) inside `app/`, `r/`, `site/`, `docs-src/`, or `scripts/`.
- Only allowlisted markdown paths may exist in the repository, mechanically enforced by [`../scripts/check-okf-hygiene.py`](../scripts/check-okf-hygiene.py):
  - Root docs: `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `ROADMAP.md`, `AGENTS.md`
  - Scoped agent rules: `app/AGENTS.md`, `r/AGENTS.md`, `okf/AGENTS.md`
  - R package docs: `r/README.md`, `r/NEWS.md`
  - Third-party provenance: `app/internal/accessreader/third_party/mdbtools/ORIGIN.md`
  - Automation & skills: `.github/**/*.md`, `.agents/**/*.md`
  - Knowledge & archives: `okf/**/*.md`, `archive/**/*.md`

## 2. Directory Lifecycle & In-Place Truth Rules

| Directory | Lifecycle Role | Editing Rule |
|---|---|---|
| **`01_history_and_evolution/` & `../archive/`** | Frozen historical provenance (`archive/oct2026-parity-ledgers/`, `archive/sep2026-r-prototype-notes/`). | **Immutable reference only.** Never treat as active product scope or feature gating. |
| **`02_present_state/` & `05_engineering_and_agents/`** | Living, in-place truth of current `HEAD` (domain, capability matrix, data dictionary, 9 empirical oracles, Go/R playbooks). | **Overwrite stale facts in place** (counts, symbol names, file paths, `Status:` banners). **Never append dated changelogs.** |
| **`03_future_architecture/`** | Unbuilt Phase 2+ proposals (Cloud `BECWeb 2.0`, Field PWA/HTR, `VTrees`). | **Graduate to `02_present_state/` when shipped** and update links in [`00_index.md`](./00_index.md). |
| **`04_evidence_and_sources/`** | `citations_index.md` + canonical ADR register [`decisions_and_gaps.md`](./04_evidence_and_sources/decisions_and_gaps.md). | Append numbered **`D-XX`** entries only for settled product/architecture decisions or new client sign-off items. |

## 3. Same-Commit Synchronization Trigger & Hygiene Gate

Update `okf/` **in the same commit** whenever a change modifies:
1. **`r/NAMESPACE` exports or `r/R/*.R` / `r/vignettes/` / `r/inst/quarto/` counts** $\rightarrow$ update [`00_index.md`](./00_index.md) and [`05_engineering_and_agents/r_sdk_engineering.md`](./05_engineering_and_agents/r_sdk_engineering.md).
2. **Wails services (`app/main.go`), `app/internal/*` DAG layers, or frontend views** $\rightarrow$ update [`00_index.md`](./00_index.md), [`02_present_state/system_architecture.md`](./02_present_state/system_architecture.md), and [`05_engineering_and_agents/desktop_app_engineering.md`](./05_engineering_and_agents/desktop_app_engineering.md).
3. **Domain/BEC oracle rules or policy approval status** $\rightarrow$ update [`02_present_state/oracles/`](./02_present_state/oracles/) and log a **`D-XX`** entry in [`04_evidence_and_sources/decisions_and_gaps.md`](./04_evidence_and_sources/decisions_and_gaps.md).
4. **Any new `.md` file under `okf/01_*`..`okf/05_*`** $\rightarrow$ register it in [`00_index.md`](./00_index.md) (manifest tree and table).

Before committing, verify zero markdown bloat, zero broken relative links, rule byte budgets (`< 24,000` bytes), and zero `vpro_wails` drift in active docs:

```bash
python3 scripts/check-okf-hygiene.py
```
