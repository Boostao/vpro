#!/usr/bin/env python3
"""Verify OKF knowledge-base hygiene, markdown allowlist, links, budgets, R export parity, and asset hygiene."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

MAX_RULE_BYTES = 24000

PRUNE_DIR_NAMES = frozenset({
    ".git",
    "node_modules",
    "dist",
    "vpro.Rcheck",
    "build",
    "__pycache__",
    ".svelte-kit",
})

ALLOWED_EXACT_MD_PATHS = frozenset({
    "README.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "ROADMAP.md",
    "AGENTS.md",
    "app/AGENTS.md",
    "r/AGENTS.md",
    "okf/AGENTS.md",
    "r/README.md",
    "r/NEWS.md",
    "app/internal/accessreader/third_party/mdbtools/ORIGIN.md",
})

ALLOWED_MD_ROOT_DIRS = frozenset({".github", ".agents", "okf", "archive"})

RULE_FILES = (
    "AGENTS.md",
    "app/AGENTS.md",
    "r/AGENTS.md",
    "okf/AGENTS.md",
    ".github/copilot-instructions.md",
)

EXTERNAL_SCHEMES = (
    "http://",
    "https://",
    "mailto:",
    "file://",
    "conversation://",
    "sidecar://",
)

# Custom SQLite scalar functions registered in Go (`app/internal/classification/projectprofiling.go`),
# distinct from R package exports in `r/NAMESPACE`.
SQLITE_SCALAR_FUNCTIONS = frozenset({
    "vpro_profile_bool",
    "vpro_profile_cover_decimal_compare",
    "vpro_profile_cover_single_decimal_compare",
    "vpro_profile_env_decimal_compare",
    "vpro_profile_max",
    "vpro_profile_number",
    "vpro_profile_single_sum",
    "vpro_profile_single_sum_decimal_compare",
    "vpro_profile_text",
})

KNOWN_S3_CLASSES = frozenset({
    "vpro_workspace",
    "vpro_pg_conn",
    "vpro_layers",
    "vpro_matrix",
    "vpro_hierarchy",
    "vpro_tax_audit",
})

BANNED_ACTIVE_TOKENS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"vpro_wails", re.IGNORECASE), "Stale repository name 'vpro_wails'"),
    (re.compile(r"\bentry_hash\b"), "Stale becmaster.audit column 'entry_hash' (use 'row_hash')"),
    (
        re.compile(r"\bconfirm_overwrite\b"),
        "Stale R write-back parameter 'confirm_overwrite' (use 'overwrite')",
    ),
    (re.compile(r"\bvpro_master_con\b"), "Stale R S3 class 'vpro_master_con' (use 'vpro_pg_conn')"),
)

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
EXPORT_NAME_RE = re.compile(r"^\s*export\(([A-Za-z0-9_.]+)\)\s*$", re.MULTILINE)
S3_METHOD_CLASS_RE = re.compile(
    r"^\s*S3method\([^,]+,\s*([A-Za-z0-9_.]+)\)\s*$", re.MULTILINE
)
EXPORTS_CLAIM_RE = re.compile(r"`?(\d+)`?\s+exports\b", re.IGNORECASE)
TITLE_SUFFIX_RE = re.compile(r"""\s+(?:"[^"]*"|'[^']*')\s*$""")
OKF_NUMBERED_DIR_RE = re.compile(r"^0[1-5]_")
VPRO_CALL_RE = re.compile(r"\b(vpro_[a-z0-9_]+)\s*\(")
VPRO_BACKTICK_RE = re.compile(r"`(vpro_[a-z0-9_]+)`")


def strip_fenced_code_blocks(text: str) -> str:
    """Remove CommonMark fenced code blocks (``` or ~~~) while preserving line count."""
    out: list[str] = []
    fence_char: str | None = None
    fence_len = 0

    for line in text.splitlines():
        stripped = line.lstrip(" ")
        if fence_char is None:
            if stripped.startswith("```") or stripped.startswith("~~~"):
                ch = stripped[0]
                run = 0
                while run < len(stripped) and stripped[run] == ch:
                    run += 1
                if ch == "`" and "`" in stripped[run:]:
                    out.append(line)
                    continue
                fence_char = ch
                fence_len = run
                out.append("")
                continue
            out.append(line)
        else:
            if stripped.startswith(fence_char * fence_len):
                rest = stripped.lstrip(fence_char).strip()
                if not rest:
                    fence_char = None
                    fence_len = 0
            out.append("")

    return "\n".join(out)


def extract_relative_link_targets(text: str) -> list[str]:
    """Return relative link path targets from markdown outside fenced code blocks."""
    cleaned = strip_fenced_code_blocks(text)
    targets: list[str] = []
    for match in LINK_RE.finditer(cleaned):
        raw = match.group(1).strip()
        if not raw:
            continue
        if raw.startswith("<"):
            end = raw.find(">")
            target = raw[1:end].strip() if end != -1 else raw[1:].strip()
        else:
            target = TITLE_SUFFIX_RE.sub("", raw).strip()

        if not target or target.startswith("#"):
            continue
        lowered = target.lower()
        if any(lowered.startswith(scheme) for scheme in EXTERNAL_SCHEMES):
            continue

        path_part = target.split("#", 1)[0].strip()
        if path_part:
            targets.append(path_part)
    return targets


def is_allowed_markdown_path(rel_posix: str) -> bool:
    """Return True if a repo-relative POSIX markdown path is on the allowlist."""
    if rel_posix in ALLOWED_EXACT_MD_PATHS:
        return True
    parts = PurePosixPath(rel_posix).parts
    return bool(parts and parts[0] in ALLOWED_MD_ROOT_DIRS)


def collect_markdown_files(repo_root: Path) -> list[Path]:
    """Walk repo_root pruning build/vendor artifacts and return sorted markdown file paths."""
    found: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(repo_root):
        rel_dir = Path(dirpath).relative_to(repo_root)
        kept_dirs: list[str] = []
        for d in sorted(dirnames):
            if d in PRUNE_DIR_NAMES:
                continue
            if rel_dir == Path("site") and d == "dist":
                continue
            kept_dirs.append(d)
        dirnames[:] = kept_dirs

        for fname in sorted(filenames):
            if fname.endswith(".md"):
                found.append(Path(dirpath) / fname)
    return sorted(found)


def collect_repo_relative_files(repo_root: Path) -> list[str]:
    """Return tracked POSIX file paths via git ls-files when inside git, else walk repo_root."""
    if (repo_root / ".git").exists():
        proc = subprocess.run(
            ["git", "-C", str(repo_root), "ls-files"],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode == 0:
            return sorted(line for line in proc.stdout.splitlines() if line)

    paths: list[str] = []
    for dirpath, dirnames, filenames in os.walk(repo_root):
        dirnames[:] = [d for d in sorted(dirnames) if d not in PRUNE_DIR_NAMES]
        for fname in sorted(filenames):
            paths.append((Path(dirpath) / fname).relative_to(repo_root).as_posix())
    return sorted(paths)


def is_historical_or_vendor_markdown(rel_posix: str) -> bool:
    """Return True for frozen historical archives or third-party vendor provenance markdown."""
    return (
        rel_posix.startswith("archive/")
        or rel_posix.startswith("okf/01_history_and_evolution/")
        or rel_posix == "app/internal/accessreader/third_party/mdbtools/ORIGIN.md"
    )


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check_hygiene(repo_root: Path) -> list[str]:
    """Run all OKF curation, markdown, R export parity, and asset hygiene checks."""
    errors: list[str] = []
    repo_root = repo_root.resolve()

    all_md_files = collect_markdown_files(repo_root)

    # 1. Markdown allowlist
    for md_path in all_md_files:
        rel_posix = md_path.relative_to(repo_root).as_posix()
        if not is_allowed_markdown_path(rel_posix):
            errors.append(f"Disallowed markdown file outside allowlist: {rel_posix}")

    # 2. Rule byte budgets (< 24,000 bytes)
    for rel_rule in RULE_FILES:
        rule_path = repo_root / rel_rule
        if not rule_path.is_file():
            errors.append(f"Missing required rule file: {rel_rule}")
            continue
        size = len(rule_path.read_bytes())
        if size >= MAX_RULE_BYTES:
            errors.append(
                f"Rule file {rel_rule} is {size} bytes (must be < {MAX_RULE_BYTES} bytes)"
            )

    # 3. OKF index completeness (every okf/01_*..05_*.md referenced in okf/00_index.md)
    okf_dir = repo_root / "okf"
    index_path = okf_dir / "00_index.md"
    okf_md_files = sorted(okf_dir.rglob("*.md")) if okf_dir.is_dir() else []

    if not index_path.is_file():
        errors.append("Missing required manifest: okf/00_index.md")
    else:
        index_text = index_path.read_text(encoding="utf-8")
        indexed_rel_paths: set[str] = set()
        for target in extract_relative_link_targets(index_text):
            resolved = (index_path.parent / target).resolve()
            try:
                rel_from_okf = resolved.relative_to(okf_dir.resolve()).as_posix()
                indexed_rel_paths.add(rel_from_okf)
            except ValueError:
                pass

        for doc_path in okf_md_files:
            rel_from_okf = doc_path.relative_to(okf_dir)
            if OKF_NUMBERED_DIR_RE.match(rel_from_okf.parts[0]):
                rel_str = rel_from_okf.as_posix()
                if rel_str not in indexed_rel_paths:
                    errors.append(
                        f"Unindexed OKF document missing from okf/00_index.md: okf/{rel_str}"
                    )

    # 4. Broken relative link check across ALL allowlisted non-archive markdown files
    for md_path in all_md_files:
        rel_src = md_path.relative_to(repo_root).as_posix()
        if rel_src.startswith("archive/") or not is_allowed_markdown_path(rel_src):
            continue
        text = md_path.read_text(encoding="utf-8")
        for target in extract_relative_link_targets(text):
            resolved = (md_path.parent / target).resolve()
            if not resolved.exists():
                errors.append(f"Broken relative link in {rel_src}: {target}")

    # 5. Oracle status banner & banned stale tokens across all active markdown files
    veg_policy_path = okf_dir / "02_present_state" / "oracles" / "VEGETATION_OPTIMIZATION_POLICY.md"
    if not veg_policy_path.is_file():
        errors.append(
            "Missing required oracle document: okf/02_present_state/oracles/VEGETATION_OPTIMIZATION_POLICY.md"
        )
    else:
        veg_text = veg_policy_path.read_text(encoding="utf-8")
        if "not approved or implemented" in veg_text.lower():
            errors.append(
                "Stale status banner in okf/02_present_state/oracles/VEGETATION_OPTIMIZATION_POLICY.md: "
                "contains 'not approved or implemented'"
            )

    active_md_files: list[tuple[str, str]] = []
    for md_path in all_md_files:
        rel_posix = md_path.relative_to(repo_root).as_posix()
        if not is_allowed_markdown_path(rel_posix) or is_historical_or_vendor_markdown(rel_posix):
            continue
        content = md_path.read_text(encoding="utf-8")
        active_md_files.append((rel_posix, content))
        for pattern, label in BANNED_ACTIVE_TOKENS:
            if pattern.search(content):
                errors.append(f"{label} found in {rel_posix}")

    # 6. R NAMESPACE export count & vpro_*() symbol parity across active docs
    namespace_path = repo_root / "r" / "NAMESPACE"
    if not namespace_path.is_file():
        errors.append("Missing required R namespace file: r/NAMESPACE")
    else:
        ns_text = namespace_path.read_text(encoding="utf-8")
        r_exports = set(EXPORT_NAME_RE.findall(ns_text))
        r_s3_classes = {
            cls for cls in S3_METHOD_CLASS_RE.findall(ns_text) if cls.startswith("vpro_")
        } | KNOWN_S3_CLASSES
        actual_exports = len(r_exports)

        for count_doc in (
            "okf/00_index.md",
            "okf/05_engineering_and_agents/r_sdk_engineering.md",
        ):
            doc_file = repo_root / count_doc
            if doc_file.is_file():
                doc_text = doc_file.read_text(encoding="utf-8")
                for match in EXPORTS_CLAIM_RE.finditer(doc_text):
                    claimed = int(match.group(1))
                    if claimed != actual_exports:
                        errors.append(
                            f"R export count mismatch in {count_doc}: claims {claimed} exports, "
                            f"but r/NAMESPACE has {actual_exports} export(...) entries"
                        )

        valid_call_symbols = r_exports | SQLITE_SCALAR_FUNCTIONS
        valid_backtick_symbols = valid_call_symbols | r_s3_classes

        for rel_posix, content in active_md_files:
            unknown_syms: set[str] = set()
            for sym in VPRO_CALL_RE.findall(content):
                if sym not in valid_call_symbols:
                    unknown_syms.add(sym)
            for sym in VPRO_BACKTICK_RE.findall(content):
                if sym not in valid_backtick_symbols:
                    unknown_syms.add(sym)
            if unknown_syms:
                joined = ", ".join(sorted(unknown_syms))
                errors.append(
                    f"Unknown/unexported R vpro_* symbol(s) in {rel_posix} (absent from r/NAMESPACE): {joined}"
                )

    # 7. Repo-level filename, dead packaging, and 7-DB support seed hygiene
    for rel_file in collect_repo_relative_files(repo_root):
        if " " in rel_file:
            errors.append(f"Tracked repository path contains spaces: {rel_file}")

    dead_appimage_dir = repo_root / "app" / "build" / "linux" / "appimage"
    if dead_appimage_dir.exists():
        errors.append("Dead AppImage packaging directory present: app/build/linux/appimage")

    r_extdata = repo_root / "r" / "inst" / "extdata"
    app_family = repo_root / "app" / "resources" / "database-family"
    if r_extdata.is_dir():
        for entry in sorted(r_extdata.iterdir()):
            if entry.is_file() and entry.suffix.lower() in {".db", ".sqlite", ".sqlite3"}:
                errors.append(
                    f"Uncompressed SQLite seed in r/inst/extdata (must be .db.gz): {entry.name}"
                )
        if not (r_extdata / "Sample.db.gz").is_file():
            errors.append("Missing bundled project seed: r/inst/extdata/Sample.db.gz")

        if app_family.is_dir():
            for app_db in sorted(app_family.glob("*.db")):
                gz_seed = r_extdata / f"{app_db.name}.gz"
                if not gz_seed.is_file():
                    errors.append(
                        f"Missing compressed support-DB seed in r/inst/extdata for {app_db.name}: "
                        f"expected r/inst/extdata/{app_db.name}.gz"
                    )
                    continue
                try:
                    raw_r = gzip.decompress(gz_seed.read_bytes())
                except OSError as exc:
                    errors.append(f"Corrupt gzip seed r/inst/extdata/{gz_seed.name}: {exc}")
                    continue
                if sha256_bytes(raw_r) != sha256_bytes(app_db.read_bytes()):
                    errors.append(
                        f"Support-DB SHA-256 drift between app/resources/database-family/{app_db.name} "
                        f"and gunzipped r/inst/extdata/{gz_seed.name}"
                    )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root directory (defaults to parent of scripts/)",
    )
    args = parser.parse_args()

    errors = check_hygiene(args.root)
    if errors:
        print("OKF hygiene check FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("OK: OKF curation, markdown allowlist, links, budgets, R export parity, and asset hygiene checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
