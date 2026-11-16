#!/usr/bin/env python3
"""Verify OKF knowledge-base hygiene, markdown allowlist, links, budgets, and anti-drift invariants."""

from __future__ import annotations

import argparse
import os
from pathlib import Path, PurePosixPath
import re
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

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
EXPORT_LINE_RE = re.compile(r"^\s*export\(", re.MULTILINE)
EXPORTS_CLAIM_RE = re.compile(r"`?(\d+)`?\s+exports\b", re.IGNORECASE)
TITLE_SUFFIX_RE = re.compile(r"""\s+(?:"[^"]*"|'[^']*')\s*$""")
OKF_NUMBERED_DIR_RE = re.compile(r"^0[1-5]_")


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


def check_hygiene(repo_root: Path) -> list[str]:
    """Run all OKF curation and markdown hygiene checks and return a list of errors."""
    errors: list[str] = []
    repo_root = repo_root.resolve()

    # 1. Markdown allowlist
    for md_path in collect_markdown_files(repo_root):
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

    # 4. Broken relative link check across *AGENTS.md, copilot-instructions.md, and okf/**/*.md
    link_checked_files: list[Path] = []
    seen: set[Path] = set()
    for rel_rule in RULE_FILES:
        p = (repo_root / rel_rule).resolve()
        if p.is_file() and p not in seen:
            seen.add(p)
            link_checked_files.append(p)
    for p in okf_md_files:
        rp = p.resolve()
        if rp not in seen:
            seen.add(rp)
            link_checked_files.append(rp)

    for md_path in link_checked_files:
        rel_src = md_path.relative_to(repo_root).as_posix()
        text = md_path.read_text(encoding="utf-8")
        for target in extract_relative_link_targets(text):
            resolved = (md_path.parent / target).resolve()
            if not resolved.exists():
                errors.append(f"Broken relative link in {rel_src}: {target}")

    # 5. Anti-drift checks
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

    for doc_path in okf_md_files:
        rel_from_okf = doc_path.relative_to(okf_dir)
        rel_posix = doc_path.relative_to(repo_root).as_posix()
        if rel_posix == "okf/00_index.md" or re.match(r"^0[2-5]_", rel_from_okf.parts[0]):
            content = doc_path.read_text(encoding="utf-8")
            if "vpro_wails" in content.lower():
                errors.append(f"Stale repository name 'vpro_wails' found in {rel_posix}")

    namespace_path = repo_root / "r" / "NAMESPACE"
    if not namespace_path.is_file():
        errors.append("Missing required R namespace file: r/NAMESPACE")
    elif index_path.is_file():
        ns_text = namespace_path.read_text(encoding="utf-8")
        actual_exports = len(EXPORT_LINE_RE.findall(ns_text))
        index_text = index_path.read_text(encoding="utf-8")
        for match in EXPORTS_CLAIM_RE.finditer(index_text):
            claimed = int(match.group(1))
            if claimed != actual_exports:
                errors.append(
                    f"R export count mismatch in okf/00_index.md: claims {claimed} exports, "
                    f"but r/NAMESPACE has {actual_exports} export(...) entries"
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

    print("OK: OKF curation, markdown allowlist, links, budgets, and anti-drift checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
