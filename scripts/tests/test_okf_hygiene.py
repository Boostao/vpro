import importlib.util
from pathlib import Path
import tempfile
import unittest


def load_module():
    script_path = Path(__file__).resolve().parents[1] / "check-okf-hygiene.py"
    spec = importlib.util.spec_from_file_location("check_okf_hygiene", script_path)
    mod = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod


MOD = load_module()


def make_fixture_repo(tmp: Path, *, export_count: int = 89, claimed_exports: int = 89) -> Path:
    (tmp / "app").mkdir(parents=True)
    (tmp / "r").mkdir(parents=True)
    (tmp / ".github").mkdir(parents=True)
    (tmp / ".agents" / "skills" / "okf-curator").mkdir(parents=True)
    (tmp / "okf" / "01_history_and_evolution").mkdir(parents=True)
    (tmp / "okf" / "02_present_state" / "oracles").mkdir(parents=True)
    (tmp / "okf" / "03_future_architecture").mkdir(parents=True)
    (tmp / "okf" / "04_evidence_and_sources").mkdir(parents=True)
    (tmp / "okf" / "05_engineering_and_agents").mkdir(parents=True)
    (tmp / "archive" / "sep2026-r-prototype-notes").mkdir(parents=True)

    (tmp / "README.md").write_text("# VPro\n", encoding="utf-8")
    (tmp / "AGENTS.md").write_text(
        "# Root\nSee [okf/AGENTS.md](./okf/AGENTS.md) and [okf/00_index.md](./okf/00_index.md).\n",
        encoding="utf-8",
    )
    (tmp / "app" / "AGENTS.md").write_text("# App\nSee [../AGENTS.md](../AGENTS.md).\n", encoding="utf-8")
    (tmp / "r" / "AGENTS.md").write_text("# R\nSee [../AGENTS.md](../AGENTS.md).\n", encoding="utf-8")
    (tmp / "okf" / "AGENTS.md").write_text("# OKF\nSee [00_index.md](./00_index.md).\n", encoding="utf-8")
    (tmp / ".github" / "copilot-instructions.md").write_text(
        "# Copilot\nSee [AGENTS.md](../AGENTS.md).\n", encoding="utf-8"
    )
    (tmp / ".agents" / "skills" / "okf-curator" / "SKILL.md").write_text("---\nname: okf-curator\n---\n", encoding="utf-8")

    (tmp / "okf" / "01_history_and_evolution" / "version_matrix.md").write_text(
        "# History\nHistorical mention of vpro_wails is permitted in 01_history_and_evolution.\n",
        encoding="utf-8",
    )
    (tmp / "okf" / "02_present_state" / "oracles" / "VEGETATION_OPTIMIZATION_POLICY.md").write_text(
        "# Deterministic Vegetation Optimization & Duplicate Diagnosis Policy\n"
        "**Status: approved and implemented (`app/internal/projectops/optimizeveg.go`, 2026-11-15).**\n",
        encoding="utf-8",
    )
    (tmp / "okf" / "04_evidence_and_sources" / "decisions_and_gaps.md").write_text("# Decisions\n", encoding="utf-8")
    (tmp / "okf" / "05_engineering_and_agents" / "r_sdk_engineering.md").write_text("# R SDK\n", encoding="utf-8")

    (tmp / "okf" / "00_index.md").write_text(
        f"# Index\n"
        f"**Audit Baseline Date:** `2026-11-15` (`{claimed_exports}` exports)\n\n"
        "- [OKF Rules](./AGENTS.md)\n"
        "- [Version Matrix](./01_history_and_evolution/version_matrix.md)\n"
        "- [Veg Optimization](./02_present_state/oracles/VEGETATION_OPTIMIZATION_POLICY.md)\n"
        "- [Decisions](./04_evidence_and_sources/decisions_and_gaps.md)\n"
        "- [R SDK](./05_engineering_and_agents/r_sdk_engineering.md)\n",
        encoding="utf-8",
    )

    ns_lines = [f"export(fn_{i})" for i in range(export_count)]
    (tmp / "r" / "NAMESPACE").write_text("\n".join(ns_lines) + "\n", encoding="utf-8")

    return tmp


class OkfHygieneTests(unittest.TestCase):
    def test_real_repo_passes_okf_hygiene(self):
        repo_root = Path(__file__).resolve().parents[2]
        self.assertEqual(MOD.check_hygiene(repo_root), [])

    def test_fixture_passes_cleanly(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td))
            self.assertEqual(MOD.check_hygiene(root), [])

    def test_detects_stray_markdown_file(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td))
            (root / "r" / "data-raw" / "projects").mkdir(parents=True)
            (root / "r" / "data-raw" / "projects" / "STRAY_NOTES.md").write_text(
                "# Stray\n", encoding="utf-8"
            )
            errs = MOD.check_hygiene(root)
            self.assertTrue(
                any("Disallowed markdown file outside allowlist: r/data-raw/projects/STRAY_NOTES.md" in e for e in errs),
                errs,
            )

    def test_detects_unindexed_okf_document(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td))
            (root / "okf" / "02_present_state" / "NEW_UNINDEXED.md").write_text(
                "# New Spec\n", encoding="utf-8"
            )
            errs = MOD.check_hygiene(root)
            self.assertTrue(
                any("Unindexed OKF document missing from okf/00_index.md: okf/02_present_state/NEW_UNINDEXED.md" in e for e in errs),
                errs,
            )

    def test_detects_broken_relative_link_and_ignores_fences_and_external(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td))
            (root / "okf" / "05_engineering_and_agents" / "r_sdk_engineering.md").write_text(
                "# R SDK\n"
                "```markdown\n"
                "[ignored_inside_fence](./missing_in_fence.md)\n"
                "```\n"
                "[external](https://example.com/ok)\n"
                "[anchor](#section)\n"
                "[broken](./does_not_exist.md#frag)\n",
                encoding="utf-8",
            )
            errs = MOD.check_hygiene(root)
            self.assertEqual(len(errs), 1, errs)
            self.assertIn("Broken relative link in okf/05_engineering_and_agents/r_sdk_engineering.md", errs[0])

    def test_detects_rule_budget_exceeded(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td))
            (root / "AGENTS.md").write_text("x" * 24000, encoding="utf-8")
            errs = MOD.check_hygiene(root)
            self.assertTrue(any("AGENTS.md is 24000 bytes" in e for e in errs), errs)

    def test_detects_anti_drift_regressions(self):
        with tempfile.TemporaryDirectory() as td:
            root = make_fixture_repo(Path(td), export_count=90, claimed_exports=89)
            (root / "okf" / "02_present_state" / "oracles" / "VEGETATION_OPTIMIZATION_POLICY.md").write_text(
                "**Status: design proposal, not approved or implemented.**\n",
                encoding="utf-8",
            )
            (root / "okf" / "05_engineering_and_agents" / "r_sdk_engineering.md").write_text(
                "Migrated from vpro_wails.\n",
                encoding="utf-8",
            )
            errs = MOD.check_hygiene(root)
            self.assertTrue(any("not approved or implemented" in e for e in errs), errs)
            self.assertTrue(any("vpro_wails" in e for e in errs), errs)
            self.assertTrue(any("R export count mismatch" in e for e in errs), errs)


if __name__ == "__main__":
    unittest.main()
