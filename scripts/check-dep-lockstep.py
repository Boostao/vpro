#!/usr/bin/env python3
"""Verify lockstep versions across Go modules, npm packages, and CI workflows."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

STOCK_WAILS_APPICON_SHA256 = (
    "985eb536bb829188b6fc3cb65d8130b4743ff773fa5ed170c0955c317cb98739"
)


def parse_go_mod(text: str) -> dict[str, str]:
    """Extract Go toolchain version and required module versions from go.mod."""
    info: dict[str, str] = {}
    tc_match = re.search(r"^\s*toolchain\s+go([0-9]+\.[0-9]+\.[0-9]+)\s*$", text, re.MULTILINE)
    if tc_match:
        info["toolchain"] = tc_match.group(1)
    go_match = re.search(r"^\s*go\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?)\s*$", text, re.MULTILINE)
    if go_match:
        info["go"] = go_match.group(1)
    wails_match = re.search(
        r"^\s*github\.com/wailsapp/wails/v3\s+v?([^\s]+)", text, re.MULTILINE
    )
    if wails_match:
        info["wails_v3"] = wails_match.group(1)
    return info


def normalize_semver(raw: str) -> str:
    """Strip npm range prefixes (^, ~, =) and leading 'v'."""
    return raw.strip().lstrip("^~=v")


def major_minor(raw: str) -> str:
    """Return 'major.minor' for lockstep family checks."""
    cleaned = normalize_semver(raw).split("-")[0].split("+")[0]
    parts = cleaned.split(".")
    if len(parts) < 2:
        raise ValueError(f"Expected semantic version with major.minor, got {raw!r}")
    return f"{parts[0]}.{parts[1]}"


def collect_workflow_pins(workflows_dir: Path) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Collect (file:line, version) tuples for Go and wails3 pins in workflows."""
    go_pins: list[tuple[str, str]] = []
    wails_pins: list[tuple[str, str]] = []
    for wf in sorted(workflows_dir.glob("*.y*ml")):
        for idx, line in enumerate(wf.read_text(encoding="utf-8").splitlines(), start=1):
            loc = f"{wf.name}:{idx}"
            gm = re.search(r"go-version:\s*['\"]?([0-9]+\.[0-9]+(?:\.[0-9]+)?)['\"]?", line)
            if gm:
                go_pins.append((loc, gm.group(1)))
            wm = re.search(r"github\.com/wailsapp/wails/v3/cmd/wails3@v?([^\s'\"]+)", line)
            if wm:
                wails_pins.append((loc, wm.group(1)))
    return go_pins, wails_pins


def check_lockstep(repo_root: Path, *, strict_brand: bool = False) -> list[str]:
    """Return list of human-readable violation strings; empty means compliant."""
    errors: list[str] = []

    go_mod_path = repo_root / "app" / "go.mod"
    pkg_json_path = repo_root / "app" / "frontend" / "package.json"
    workflows_dir = repo_root / ".github" / "workflows"

    if not go_mod_path.is_file():
        return [f"Missing {go_mod_path}"]
    if not pkg_json_path.is_file():
        return [f"Missing {pkg_json_path}"]

    go_info = parse_go_mod(go_mod_path.read_text(encoding="utf-8"))
    pkg = json.loads(pkg_json_path.read_text(encoding="utf-8"))
    deps = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}

    # 1. Wails v3 runtime <-> Go module <-> CI CLI pin
    go_wails = go_info.get("wails_v3")
    npm_wails = deps.get("@wailsio/runtime")
    if not go_wails:
        errors.append("app/go.mod is missing github.com/wailsapp/wails/v3")
    if not npm_wails:
        errors.append("app/frontend/package.json is missing @wailsio/runtime")
    if go_wails and npm_wails:
        norm_go = normalize_semver(go_wails)
        norm_npm = normalize_semver(npm_wails)
        if norm_go != norm_npm:
            errors.append(
                f"Wails v3 runtime mismatch: app/go.mod has {norm_go} but @wailsio/runtime has {norm_npm}"
            )

    go_pins, wails_pins = collect_workflow_pins(workflows_dir)
    if go_wails:
        norm_go = normalize_semver(go_wails)
        for loc, pin in wails_pins:
            norm_pin = normalize_semver(pin)
            if norm_pin != norm_go:
                errors.append(
                    f"Workflow wails3 CLI mismatch at .github/workflows/{loc}: expected {norm_go}, found {norm_pin}"
                )

    # 2. Go toolchain <-> workflow go-version pins
    expected_go = go_info.get("toolchain") or go_info.get("go")
    if not expected_go:
        errors.append("app/go.mod is missing Go toolchain / go version directive")
    else:
        for loc, pin in go_pins:
            if pin != expected_go:
                errors.append(
                    f"Workflow go-version mismatch at .github/workflows/{loc}: app/go.mod toolchain is {expected_go}, found {pin}"
                )

    # 3. Coupled @deck.gl/* and @luma.gl/* major.minor families
    deck_pkgs = ("@deck.gl/core", "@deck.gl/layers", "@deck.gl/mapbox")
    deck_versions = {name: deps[name] for name in deck_pkgs if name in deps}
    if len(deck_versions) != len(deck_pkgs):
        missing = [name for name in deck_pkgs if name not in deps]
        errors.append(f"Missing required @deck.gl packages in package.json: {', '.join(missing)}")
    else:
        deck_mm = {name: major_minor(ver) for name, ver in deck_versions.items()}
        if len(set(deck_mm.values())) != 1:
            errors.append(f"@deck.gl/* major.minor lockstep mismatch: {deck_versions}")

    luma_pkgs = ("@luma.gl/core", "@luma.gl/webgpu")
    luma_versions = {name: deps[name] for name in luma_pkgs if name in deps}
    if len(luma_versions) != len(luma_pkgs):
        missing = [name for name in luma_pkgs if name not in deps]
        errors.append(f"Missing required @luma.gl packages in package.json: {', '.join(missing)}")
    else:
        luma_mm = {name: major_minor(ver) for name, ver in luma_versions.items()}
        if len(set(luma_mm.values())) != 1:
            errors.append(f"@luma.gl/* major.minor lockstep mismatch: {luma_versions}")

    # 4. Optional strict brand guard (Wave 3 readiness)
    if strict_brand:
        appicon = repo_root / "app" / "build" / "appicon.png"
        if not appicon.is_file():
            errors.append("Missing app/build/appicon.png")
        else:
            digest = hashlib.sha256(appicon.read_bytes()).hexdigest()
            if digest == STOCK_WAILS_APPICON_SHA256:
                errors.append("app/build/appicon.png still matches the stock Wails 'W' logo")
        stock_svg = repo_root / "app" / "build" / "appicon.icon" / "Assets" / "wails_icon_vector.svg"
        if stock_svg.exists():
            errors.append(f"Stock Wails SVG still present: {stock_svg.relative_to(repo_root)}")
        svelte_svg = repo_root / "app" / "frontend" / "public" / "svelte.svg"
        if svelte_svg.exists():
            errors.append(f"Stock Vite/Svelte SVG still present: {svelte_svg.relative_to(repo_root)}")

    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Monorepo root directory",
    )
    parser.add_argument(
        "--strict-brand",
        action="store_true",
        help="Also verify stock Wails 'W' and svelte.svg brand artifacts are absent",
    )
    args = parser.parse_args(argv)

    violations = check_lockstep(args.root.resolve(), strict_brand=args.strict_brand)
    if violations:
        for item in violations:
            print(f"ERROR: {item}", file=sys.stderr)
        return 1
    print("OK: Go, Wails v3, WebGPU/deck.gl, and workflow dependency pins are in lockstep.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
