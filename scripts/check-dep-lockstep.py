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

STOCK_WAILS_WINDOWS_ICO_SHA256 = (
    "ce3eb2bc9f464e659b12746da912ffa8e0383ae2cbcce1c057b20d8dc8043dd2"
)

STOCK_BRAND_SHA256_GUARD: tuple[tuple[str, str, str], ...] = (
    (
        "app/build/windows/icon.ico",
        STOCK_WAILS_WINDOWS_ICO_SHA256,
        "app/build/windows/icon.ico still matches the stock Wails 'W' icon",
    ),
    (
        "app/frontend/public/favicon.ico",
        STOCK_WAILS_WINDOWS_ICO_SHA256,
        "app/frontend/public/favicon.ico still matches the stock Wails 'W' icon",
    ),
    (
        "site/favicon.ico",
        STOCK_WAILS_WINDOWS_ICO_SHA256,
        "site/favicon.ico still matches the stock Wails 'W' icon",
    ),
    (
        "app/build/darwin/dmg-background.png",
        "5f07c1d4eafd111b76316b7d25ab50906848cf468d6862b1b101c20a89a920df",
        "app/build/darwin/dmg-background.png still matches the stock Wails red-dragon banner",
    ),
    (
        "app/build/darwin/dmg-file-icon.png",
        "4e04ec7f61f6ffabd86a581b43a6c0768c28a81c84c7704d054d010e3af0731a",
        "app/build/darwin/dmg-file-icon.png still matches the stock Wails red-dragon icon",
    ),
    (
        "app/build/darwin/dmg-file-icon.icns",
        "cc1162fd1d662437e5aa50b99fc5b2aea164cf5b9f8390f492e2508e7bd2bf60",
        "app/build/darwin/dmg-file-icon.icns still matches the stock Wails red-dragon icon",
    ),
    (
        "app/build/darwin/Assets.car",
        "48e5c620766a4fe70274c57fa43c74f39b9c2e20f3c3976adc415e768e01e635",
        "app/build/darwin/Assets.car still matches the stock Wails asset catalog",
    ),
)

FORBIDDEN_BRAND_FILES: tuple[tuple[str, str], ...] = (
    ("app/build/appicon.icon/Assets/wails_icon_vector.svg", "Stock Wails SVG still present"),
    ("app/frontend/public/svelte.svg", "Stock Vite/Svelte SVG still present"),
    ("app/frontend/public/wails.png", "Stock Wails template PNG still present"),
    ("app/frontend/public/style.css", "Unused template stylesheet still present"),
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

    # 3. Coupled @deck.gl/* and (optional) @luma.gl/* major.minor families
    required_deck_pkgs = ("@deck.gl/layers", "@deck.gl/mapbox")
    missing_deck = [name for name in required_deck_pkgs if name not in deps]
    if missing_deck:
        errors.append(f"Missing required @deck.gl packages in package.json: {', '.join(missing_deck)}")
    deck_versions = {name: ver for name, ver in sorted(deps.items()) if name.startswith("@deck.gl/")}
    if len(deck_versions) >= 2:
        deck_mm = {name: major_minor(ver) for name, ver in deck_versions.items()}
        if len(set(deck_mm.values())) != 1:
            errors.append(f"@deck.gl/* major.minor lockstep mismatch: {deck_versions}")

    luma_versions = {name: ver for name, ver in sorted(deps.items()) if name.startswith("@luma.gl/")}
    if len(luma_versions) >= 2:
        luma_mm = {name: major_minor(ver) for name, ver in luma_versions.items()}
        if len(set(luma_mm.values())) != 1:
            errors.append(f"@luma.gl/* major.minor lockstep mismatch: {luma_versions}")

    # 4. Optional strict brand guard (Wave 3 readiness)
    if strict_brand:
        appicon = repo_root / "app" / "build" / "appicon.png"
        if not appicon.is_file():
            errors.append("Missing app/build/appicon.png")
        elif hashlib.sha256(appicon.read_bytes()).hexdigest() == STOCK_WAILS_APPICON_SHA256:
            errors.append("app/build/appicon.png still matches the stock Wails 'W' logo")

        for rel_path, stock_sha, message in STOCK_BRAND_SHA256_GUARD:
            asset = repo_root / rel_path
            if asset.is_file() and hashlib.sha256(asset.read_bytes()).hexdigest() == stock_sha:
                errors.append(message)

        assets_car = repo_root / "app" / "build" / "darwin" / "Assets.car"
        if assets_car.is_file():
            car_bytes = assets_car.read_bytes()
            if b"wails_icon_vector" in car_bytes or b"\x00wails\x00" in car_bytes.lower():
                errors.append("app/build/darwin/Assets.car contains stock Wails layer symbols")

        for rel_path, prefix in FORBIDDEN_BRAND_FILES:
            target = repo_root / rel_path
            if target.exists():
                errors.append(f"{prefix}: {rel_path}")

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
