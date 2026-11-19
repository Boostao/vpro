import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


def load_module():
    script_path = Path(__file__).resolve().parents[1] / "check-dep-lockstep.py"
    spec = importlib.util.spec_from_file_location("check_dep_lockstep", script_path)
    mod = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod


MOD = load_module()


def make_fixture_repo(tmp: Path, *, go_wails="v3.1.0", npm_wails="3.1.0", wf_wails="v3.1.0",
                      go_toolchain="1.27.4", wf_go="1.27.4", deck_layers="^9.4.1") -> Path:
    (tmp / "app" / "frontend").mkdir(parents=True)
    (tmp / ".github" / "workflows").mkdir(parents=True)
    (tmp / "app" / "go.mod").write_text(
        f"module example.com/app\n\ngo 1.27.0\n\ntoolchain go{go_toolchain}\n\n"
        f"require (\n\tgithub.com/wailsapp/wails/v3 {go_wails}\n)\n",
        encoding="utf-8",
    )
    (tmp / "app" / "frontend" / "package.json").write_text(
        json.dumps({
            "dependencies": {
                "@wailsio/runtime": npm_wails,
                "@deck.gl/core": "^9.4.1",
                "@deck.gl/layers": deck_layers,
                "@deck.gl/mapbox": "^9.4.1",
                "@luma.gl/core": "^9.4.2",
                "@luma.gl/webgpu": "^9.4.2",
            }
        }),
        encoding="utf-8",
    )
    (tmp / ".github" / "workflows" / "ci.yml").write_text(
        f"steps:\n  - uses: actions/setup-go@v7\n    with:\n      go-version: '{wf_go}'\n"
        f"  - run: go install github.com/wailsapp/wails/v3/cmd/wails3@{wf_wails}\n",
        encoding="utf-8",
    )
    return tmp


class DepLockstepTests(unittest.TestCase):
    def test_real_repo_passes_default_lockstep(self):
        repo_root = Path(__file__).resolve().parents[2]
        self.assertEqual(MOD.check_lockstep(repo_root, strict_brand=False), [])

    def test_detects_wails_runtime_drift(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td), npm_wails="3.0.0-beta.26")
            errs = MOD.check_lockstep(root)
            self.assertTrue(any("Wails v3 runtime mismatch" in e for e in errs), errs)

    def test_detects_workflow_wails_cli_drift(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td), wf_wails="v3.0.9")
            errs = MOD.check_lockstep(root)
            self.assertTrue(any("Workflow wails3 CLI mismatch" in e for e in errs), errs)

    def test_detects_go_toolchain_drift(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td), wf_go="1.26.2")
            errs = MOD.check_lockstep(root)
            self.assertTrue(any("Workflow go-version mismatch" in e for e in errs), errs)

    def test_detects_deckgl_minor_drift(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td), deck_layers="^9.5.0")
            errs = MOD.check_lockstep(root)
            self.assertTrue(any("@deck.gl/* major.minor lockstep mismatch" in e for e in errs), errs)

    def test_pruned_direct_deckgl_without_unused_luma_passes(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td))
            pkg_path = root / "app" / "frontend" / "package.json"
            pkg_path.write_text(
                json.dumps({
                    "dependencies": {
                        "@wailsio/runtime": "3.1.0",
                        "@deck.gl/layers": "^9.4.1",
                        "@deck.gl/mapbox": "^9.4.1",
                    }
                }),
                encoding="utf-8",
            )
            self.assertEqual(MOD.check_lockstep(root), [])

    def test_real_repo_passes_strict_brand(self):
        repo_root = Path(__file__).resolve().parents[2]
        self.assertEqual(MOD.check_lockstep(repo_root, strict_brand=True), [])

    def test_strict_brand_detects_stock_wails_and_passes_custom(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td))
            (root / "app" / "build" / "appicon.icon" / "Assets").mkdir(parents=True)
            (root / "app" / "build" / "windows").mkdir(parents=True)
            (root / "app" / "build" / "darwin").mkdir(parents=True)
            (root / "app" / "frontend" / "public").mkdir(parents=True)

            synthetic_stock = b"synthetic-stock-wails-w-png"
            synthetic_sha = hashlib.sha256(synthetic_stock).hexdigest()
            (root / "app" / "build" / "appicon.png").write_bytes(synthetic_stock)
            (root / "app" / "build" / "appicon.icon" / "Assets" / "wails_icon_vector.svg").write_text("<svg/>")
            (root / "app" / "frontend" / "public" / "svelte.svg").write_text("<svg/>")
            (root / "app" / "frontend" / "public" / "wails.png").write_bytes(b"png")
            (root / "app" / "frontend" / "public" / "style.css").write_text("body{}")

            synthetic_ico = b"synthetic-stock-wails-ico"
            synthetic_ico_sha = hashlib.sha256(synthetic_ico).hexdigest()
            (root / "app" / "build" / "windows" / "icon.ico").write_bytes(synthetic_ico)

            synthetic_car = b"BOMStore\x00wails\x00data"
            (root / "app" / "build" / "darwin" / "Assets.car").write_bytes(synthetic_car)

            guarded = (
                ("app/build/windows/icon.ico", synthetic_ico_sha, "app/build/windows/icon.ico stock"),
            )
            with mock.patch.object(MOD, "STOCK_WAILS_APPICON_SHA256", synthetic_sha), \
                 mock.patch.object(MOD, "STOCK_BRAND_SHA256_GUARD", guarded):
                errs = MOD.check_lockstep(root, strict_brand=True)
                self.assertEqual(len(errs), 7, errs)

                # Replace with custom branded assets and remove template clutter -> should pass
                (root / "app" / "build" / "appicon.png").write_bytes(b"custom-bcgov-vpro-png")
                (root / "app" / "build" / "windows" / "icon.ico").write_bytes(b"custom-bcgov-vpro-ico")
                (root / "app" / "build" / "darwin" / "Assets.car").unlink()
                for dead in (
                    root / "app" / "build" / "appicon.icon" / "Assets" / "wails_icon_vector.svg",
                    root / "app" / "frontend" / "public" / "svelte.svg",
                    root / "app" / "frontend" / "public" / "wails.png",
                    root / "app" / "frontend" / "public" / "style.css",
                ):
                    dead.unlink()
                self.assertEqual(MOD.check_lockstep(root, strict_brand=True), [])


if __name__ == "__main__":
    unittest.main()
