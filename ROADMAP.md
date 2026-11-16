# VPro Product Roadmap (`Boostao/vpro`)

This roadmap outlines the planned milestones for **VPro 2.0** (*VENUS — Vegetation and Environment NexUS — Professional*) across **VPro Desktop**, the **`vpro` R Companion Package**, and **Provincial Cloud `BECMaster`** for the **B.C. Ministry of Forests, Research Branch — BEC Program**.

*(Aligned with the client function review and long-term architecture notes in [`okf/03_future_architecture/`](./okf/03_future_architecture/target_stack_recommendation.md) and [`okf/04_evidence_and_sources/decisions_and_gaps.md`](./okf/04_evidence_and_sources/decisions_and_gaps.md).)*

---

## Horizon 1 — Desktop & R Companion Hardening (`v2.0.x` — Active)

**Goal:** Deliver a reliable daily replacement for Microsoft Access `VPro 64` that field technicians, regional BEC ecologists, and quantitative analysts can count on.

- **Verified VPro 64 Workflow Parity:** End-to-end verification of retained and updated VPro 64 workflows (`FS882`, `Two-Page`, `SIVI`, extended shrub layers, multi-plot 9-table Datasheet editing, project create/save-as/split/compare/3-way merge, vegetation duplicate cleanup, Site Unit / Hierarchy / Lumping / Plot Profiling, `LMH25 (2023)` field checks, Access `.accdb`/`.mdb` + `TurboVeg 3` + `VENUS 5.0` + GeoPackage / `.rds` / `.xlsx` / PDF exchange, and live BEC diagnostic synthesis).
- **Unified BC Government Design & Branding:** Consistent BC Government Navy and Gold visual language (`BC Sans` and crisp custom icons) across VPro Desktop, the download and documentation portal, and the `vpro` R package reference site.
- **Field-Ready Screen Layouts & Accurate Guided Tours:** Smooth layouts across desktop monitors, `1366×768` field laptops, ruggedized field tablets (`1024×768` / `768×1024`), and narrow windows (`390×844`), paired with self-adjusting step-by-step tours and a one-click standards stamp under `Help -> About`.
- **Streamlined `vpro` R Companion API & Cross-Tool Agreement:** Consolidated, memorable R functions backed by automated checks confirming identical ecological calculations between VPro Desktop and R.
- **Clean, Maintainable Project Structure:** Well-organized code modules, compact sample and test files, and automated multi-screen quality checks.

---

## Horizon 2 — Provincial Cloud `BECMaster` & `BECWeb 2.0` (`v2.1–v2.2`)

**Goal:** Transition regional BEC projects from emailed database attachments to a shared, auditable provincial repository while preserving fast offline field work.

- **Ministry Sign-In & Role Permissions (`IDIR` / `BCeID`):** Connect federated Ministry sign-in and role-based permissions (`public`, `contributor`, `ecologist`, `custodian`) in both VPro Desktop and R.
- **Approved Regional `BECdb` Unit Additions:** Enable regional ecologists to propose new site series or site units and allow custodians to review and publish approved updates to provincial standards.
- **Custodian Review Queue & Public `BECWeb 2.0` Portal:** Productionize pre-upload compliance checks, conflict-checked 3-way merge review, tamper-evident audit logs, download tracking, and public online Site Unit guides and maps with sensitive rare-species coordinates hidden.

---

## Horizon 3 — Field Mobility, Card Transcription & Forestry Companions (`v3.0`)

**Goal:** Eliminate post-field transcription bottlenecks and integrate companion forestry workflows once Cloud `BECMaster` is proven in daily use.

- **Code-Signed Windows & Notarized macOS Installers:** Add official Windows Authenticode and Apple Developer ID signing so installers open without security warnings on managed BC Government workstations.
- **Offline Field Tablet Capture:** Mobile-friendly offline plot entry for rugged tablets in zero-connectivity field sites with clean, conflict-free upload into VPro Desktop and Cloud `BECMaster`.
- **Assisted Field Card Transcription:** Optional local handwriting recognition for scanned `FS882` and `FS1333` Rite-in-the-Rain field cards, guided by `BCPlantTaxonomy` species lists and `LMH25` horizon/substrate rules with side-by-side human review.
- **Deferred Utilities & Companion Forestry Modules:** Evaluate and add deferred utilities (`Herbarium`, `Colour-Theme`, `Hierarchy Diagram`, `Print All Labels`) and companion forestry workbenches (`VTrees` timber mensuration / Kozak taper, Coarse Woody Debris `CWD`, and Wildlife Habitat Assessment `WHA`) tracked in [`okf/04_evidence_and_sources/decisions_and_gaps.md`](./okf/04_evidence_and_sources/decisions_and_gaps.md).
