# VPro Product Roadmap (`Boostao/vpro`)

This roadmap defines the multi-horizon vision for **VPro 2.0** (*VENUS — Vegetation and Environment NexUS — Professional*) across the **Desktop Workstation (`app/`)**, **Headless R Companion SDK (`r/`)**, and **Provincial Cloud `BECMaster`** ecosystem for the **B.C. Ministry of Forests, Research Branch — BEC Program**.

*(Derived from Contract `RE26OCF433` Schedule A, client triage `VPro2.0_Functions`, and [`okf/03_future_architecture/`](./okf/03_future_architecture/target_stack_recommendation.md) / [`okf/04_evidence_and_sources/decisions_and_gaps.md`](./okf/04_evidence_and_sources/decisions_and_gaps.md)).*

---

## Horizon 1 — Workstation & R SDK Hardening (`v2.0.x` — Active)

**Goal:** Deliver an official, rock-solid replacement for Microsoft Access `VPro64` that field technicians, regional BEC ecologists, and quantitative scientists can depend on daily.

- **100% Verified Access `VPro64` Feature Parity:** End-to-end verification and remediation of every retained/modified Access capability (`FS882`, `Two-Page`, `SIVI`, inline `CHARS`, `UniversalDatasheetGrid`, `New`/`SaveAs`/`Splinter`/`Compare`/`3-Way Merge`, `OptimizeVeg`, `SU`/`Hierarchy`/`Lump`/Profiling, `USysTableOfLists` + `LMH25` validation, `.accdb` + `TurboVeg 3` + `VENUS 5` + `.gpkg`/`.rds`/`.xlsx`/`.pdf` interchange, and diagnostic synthesis) against empirical DAO/BEC oracles.
- **Unified Full BC Government Design System (`#003366` / `#FCBA19`):** Replace legacy Wails `"W"` / Svelte icon remnants and split CSS palettes with one coherent BC Gov Navy & Gold token architecture (`BC Sans` + `IBM Plex Mono`), precision SVGs, and single-source generated platform icons across `app/`, `site/`, and `r/pkgdown`.
- **Responsive Multi-Aspect-Ratio UI & Accurate Guided Tours:** Support desktop workstations, `1366×768` field laptops, ruggedized Toughbooks/tablets (`1024×768` / `768×1024`), and narrow panes (`390×844`) with reactive `ResizeObserver` spotlight tours and a 1-click **Diagnostic Stamp** in `Help -> About`.
- **Orthogonal `vpro` R 2.0 SDK & App $\leftrightarrow$ R Equivalence:** Consolidate overlapping `r/NAMESPACE` exports into a crisp, memorable R API paired with automated cross-language (`Go` vs `R`) numerical equivalence regression tests.
- **Lean, Agent-Maintainable Monorepo:** Right-size mega-files and over-fragmented micro-files, compact multi-MB JSON fixtures, and add Playwright multi-viewport + lockstep CI gates.

---

## Horizon 2 — Provincial Cloud `BECMaster` & `BECWeb 2.0` (`v2.1–v2.2`)

**Goal:** Transition regional BEC projects from manual `.accdb`/`.db` email attachments to an accredited, auditable provincial PostgreSQL/PostGIS repository while maintaining offline local-first speed.

- **Ministry OIDC Accreditation & RBAC (`IDIR` / `BCeID`):** Wire federated OIDC authentication and role mapping (`public`, `contributor`, `ecologist`, `custodian`) into both `app/internal/cloudsync` and `r/R/cloud_*.R`.
- **Live Accredited `BECdb` Unit Additions:** Enable regional ecologists to propose and Custodians to approve new official site series / site units (`RE26OCF433` Schedule A §3.g.ii) via `standards.library_releases`.
- **Custodian Staging Queue & Public Portal (`BECWeb 2.0`):** Productionize `staging` submission compliance gating, `SERIALIZABLE` 3-way merge review UI, download telemetry (`becmaster.download_log`), SHA-256 hash-chained `becmaster.audit` verification, and public Quarto/Shiny read-only `BECWeb 2.0` unit guides and map views with rare-plant coordinate redaction.

---

## Horizon 3 — Field Mobility, Card Ingestion & Phase 2 Companions (`v3.0`)

**Goal:** Eliminate post-field transcription bottlenecks and integrate deferred/companion forestry modules once core `BECMaster` workflows are battle-tested in production.

- **Enterprise Code Signing & Notarization:** Enroll Windows OV/EV Authenticode and Apple Developer ID certificates for zero-warning SmartScreen/Gatekeeper installation across BC Government managed endpoints.
- **Offline Field Tablet PWA (`Outcome 6`):** Mobile-first offline `VP08` plot capture supporting rugged tablets in zero-connectivity backcountry settings with deterministic conflict-free upload into Desktop/Cloud `BECMaster`.
- **Confidence-Scored Field Card HTR/OCR:** Optional local handwritten `FS882`/`FS1333` Rite-in-the-Rain ingestion pipeline constrained by `USysAllSpecs` lexicons, `LMH25` horizon/substrate grammars, and split-screen human-in-the-loop (HITL) verification.
- **Phase 2 Companion & Deferred Modules:** Evaluate and integrate deferred orange-tier features (`Herbarium`, `Colour-Theme`, `Hierarchy Diagram`, `Print All Labels`) and companion forestry workbenches (`VTrees` mensuration / Kozak taper, Coarse Woody Debris `CWD`, and Wildlife Habitat Assessment `WHA`) per [`okf/04_evidence_and_sources/decisions_and_gaps.md`](./okf/04_evidence_and_sources/decisions_and_gaps.md).
