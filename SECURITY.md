# Security & Data Custody Policy (`Boostao/vpro`)

## Supported Versions

Security fixes are backported to the active `stable` desktop release series (`app/`), the current `r/` SDK release series, and the latest `preview` build listed in [`site/release-manifest.json`](./site/release-manifest.json). Legacy Microsoft Access `VPro64` binaries are unmaintained upstream and unsupported for security patches.

## Reporting a Vulnerability

**Please do not open public GitHub issues for security vulnerabilities or leaked credentials.**

Report suspected vulnerabilities privately via one of:
1. **GitHub Security Advisories** ("Report a vulnerability" in the `Boostao/vpro` Security tab), or
2. Email to **Bruno Tremblay** (`bruno@boostao.ca`) with steps to reproduce, affected OS/version, and impact scope.

We aim to acknowledge reports within **3 business days** and coordinate remediation before public disclosure.

## Ecological Data Custody & Architectural Security Controls

- **Local-First SQLite Custody (`VP08`):** Desktop project files (`.db`) reside on user-controlled storage. Diagnostic copies and issue reports must never include sensitive landowner PII or protected rare-plant coordinates unless explicitly sanitized.
- **PostgreSQL `BECMaster` Cloud Security:**
  - Non-loopback PostgreSQL connections require TLS (`sslmode = "require"` or `"verify-full"`).
  - Passwords, DSNs, and tokens are strictly redacted from logs, `print()` methods, and error strings; `.env` / `becmaster.env` credential files are git- and R-build-ignored.
  - Access relies on least-privilege PostgreSQL roles + Row-Level Security (`public`, `contributor`, `ecologist`, `custodian`), public rare-plant coordinate redaction, and SHA-256 hash-chained `becmaster.audit` ledgers.
- **Supply-Chain & Release Verification:** Every release publishes `SHA256SUMS.txt` and `release-manifest.json` verified post-upload by [`scripts/release.py`](./scripts/release.py), including Windows PE non-inbox DLL allowlist checks and weekly `govulncheck` / `npm audit` scans. *(Note: Desktop binaries currently require checksum verification where enterprise OV/EV Authenticode or Apple Notarization is pending — see [`ROADMAP.md`](./ROADMAP.md)).*
