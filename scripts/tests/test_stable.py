"""Tests for the rules in scripts/stable.py (python3 -m unittest discover -s scripts/tests)."""

import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from stable import (Release, changelog_sections, ci_conclusions_ok, evaluate, excluded_paths, has_fixes, is_excluded,  # noqa: E402
                    load_patterns, main_status, mentions, parse_version, plist_version)  # noqa: E402

NOW = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)


def rel(version, hours_ago, **kw):
    kw.setdefault("assets", [f"Prune-{version}.dmg", "SHA256SUMS"])
    return Release(version=version, published=NOW - timedelta(hours=hours_ago), **kw)


def changelog(*sections):
    """sections: (version, [### headings]) from newest to oldest."""
    out = "# Changelog\n\nText.\n\n"
    for version, heads in sections:
        out += f"## [{version}] - 2026-10-30\n\nSummary.\n\n"
        for h in heads:
            out += f"### {h}\n- A change.\n\n"
    return out + "[1.0.0]: https://example.com\n"


class ParsingTests(unittest.TestCase):
    def test_parse_version(self):
        self.assertEqual(parse_version("v1.2.10"), (1, 2, 10))
        self.assertEqual(parse_version("1.2.3"), (1, 2, 3))
        self.assertIsNone(parse_version("v1.2"))
        self.assertIsNone(parse_version("nightly"))
        self.assertGreater(parse_version("1.10.0"), parse_version("1.9.9"))

    def test_sections(self):
        s = changelog_sections(changelog(("1.1.0", ["Added"]), ("1.0.0", ["Fixed"])))
        self.assertEqual(set(s), {"1.1.0", "1.0.0"})
        self.assertIn("### Added", s["1.1.0"])
        self.assertNotIn("Fixed", s["1.1.0"])

    def test_has_fixes(self):
        self.assertTrue(has_fixes("### Fixed\n- Something.\n"))
        self.assertTrue(has_fixes("Summary\n\n### Fixed\n\n- Something.\n"))
        self.assertTrue(has_fixes("### Corrigido\n- Algo.\n"), "sections written in Portuguese, up to 1.3.3")
        self.assertFalse(has_fixes("### Fixed\n\n### Changed\n- x\n"), "an empty section does not count")
        self.assertFalse(has_fixes("### Added\n- Fixed the text.\n"))
        self.assertFalse(has_fixes(None))
        self.assertTrue(has_fixes("### Fixed  \n \t\n\n- Something.\n"), "spaces on the heading and blank lines")

    def test_has_fixes_runs_in_linear_time(self):
        # Many blank lines and no list item: took more than 5 min with the old regex (CodeQL py/redos).
        import time
        start = time.monotonic()
        self.assertFalse(has_fixes("### Fixed" + " \n" * 50_000 + "x"))
        self.assertLess(time.monotonic() - start, 1.0)

    def test_mentions(self):
        self.assertTrue(mentions("Crash in v1.2.6 when cleaning", "1.2.6"))
        self.assertTrue(mentions("version 1.2.6", "1.2.6"))
        self.assertFalse(mentions("version 1.2.60", "1.2.6"))
        self.assertFalse(mentions("version 11.2.6", "1.2.6"))
        self.assertFalse(mentions("version 1.2.6.1", "1.2.6"))


class EvaluateTests(unittest.TestCase):
    def test_newest_soaked_release_wins(self):
        rs = [rel("1.0.0", 100), rel("1.1.0", 48), rel("1.2.0", 30)]
        cand, verdicts = evaluate(rs, changelog(), "1.0.0", NOW)
        self.assertEqual(cand, "1.2.0")
        self.assertEqual([v.version for v in verdicts], ["1.2.0", "1.1.0", "1.0.0"])

    def test_soak_period_holds_back_new_release(self):
        rs = [rel("1.0.0", 100), rel("1.1.0", 48), rel("1.2.0", 2)]
        cand, verdicts = evaluate(rs, changelog(), "1.0.0", NOW)
        self.assertEqual(cand, "1.1.0")
        self.assertIn("soaking", verdicts[0].reason)

    def test_soak_hours_configurable(self):
        rs = [rel("1.0.0", 100), rel("1.1.0", 2)]
        self.assertEqual(evaluate(rs, changelog(), "1.0.0", NOW, soak_hours=1)[0], "1.1.0")
        self.assertIsNone(evaluate(rs, changelog(), "1.0.0", NOW, soak_hours=3)[0])

    def test_later_fix_rejects_older_versions(self):
        # 1.2.1 fixes bugs: 1.2.0 and earlier are left out; 1.2.1 is still soaking.
        rs = [rel("1.0.0", 200), rel("1.2.0", 100), rel("1.2.1", 5)]
        log = changelog(("1.2.1", ["Fixed"]), ("1.2.0", ["Added"]))
        cand, verdicts = evaluate(rs, log, "1.0.0", NOW)
        self.assertIsNone(cand)
        by = {v.version: v for v in verdicts}
        self.assertIn("fixed later, in 1.2.1", by["1.2.0"].reason)
        self.assertIn("soaking", by["1.2.1"].reason)

    def test_fix_release_becomes_stable_after_soak(self):
        rs = [rel("1.0.0", 200), rel("1.2.0", 100), rel("1.2.1", 30)]
        log = changelog(("1.2.1", ["Fixed"]), ("1.2.0", ["Added"]))
        self.assertEqual(evaluate(rs, log, "1.0.0", NOW)[0], "1.2.1")

    def test_fix_in_own_section_does_not_reject_itself(self):
        rs = [rel("1.1.0", 50)]
        self.assertEqual(evaluate(rs, changelog(("1.1.0", ["Fixed"])), "1.0.0", NOW)[0], "1.1.0")

    def test_unpublished_fix_does_not_count(self):
        # A draft Release with fixes does not say anything about the earlier ones yet.
        rs = [rel("1.1.0", 50), rel("1.1.1", 30, draft=True)]
        self.assertEqual(evaluate(rs, changelog(("1.1.1", ["Fixed"])), "1.0.0", NOW)[0], "1.1.0")

    def test_main_already_stable(self):
        rs = [rel("1.0.0", 100), rel("1.1.0", 48)]
        cand, verdicts = evaluate(rs, changelog(), "1.1.0", NOW)
        self.assertIsNone(cand)
        self.assertTrue(verdicts[0].ok)

    def test_never_promotes_older_than_main(self):
        rs = [rel("1.0.0", 100), rel("1.1.0", 2)]
        self.assertIsNone(evaluate(rs, changelog(), "1.1.0", NOW)[0])

    def test_main_without_version(self):
        self.assertEqual(evaluate([rel("1.0.0", 100)], changelog(), None, NOW)[0], "1.0.0")

    def test_rejections(self):
        rs = [
            rel("1.9.5", 100, ci_ok=False),
            rel("1.9.2", 100, assets=["Prune-1.9.2.dmg"]),
            rel("1.9.0", 100, draft=True),
            rel("1.8.0", 100, assets=[]),
            rel("1.7.0", 100, assets=["Prune-1.6.0.dmg"]),
            rel("1.6.0", 100, on_dev=False),
            rel("1.5.5", 100, main_ready=False),
            rel("1.5.0", 100),
        ]
        cand, verdicts = evaluate(rs, changelog(), "1.0.0", NOW)
        self.assertEqual(cand, "1.5.0")
        reasons = {v.version: v.reason for v in verdicts}
        self.assertIn("no green CI", reasons["1.9.5"])
        self.assertIn("SHA256SUMS", reasons["1.9.2"])
        self.assertIn("draft", reasons["1.9.0"])
        self.assertIn("Prune-1.8.0.dmg", reasons["1.8.0"])
        self.assertIn("Prune-1.7.0.dmg", reasons["1.7.0"])
        self.assertIn("dev's history", reasons["1.6.0"])
        self.assertIn(".mainignore", reasons["1.5.5"])

    def test_prerelease_is_a_beta_and_can_be_promoted(self):
        self.assertEqual(evaluate([rel("1.1.0", 50, prerelease=True)], changelog(), "1.0.0", NOW)[0], "1.1.0")

    def test_old_releases_without_checksums_are_judged_by_main_ready(self):
        r = rel("1.0.5", 50, assets=["Prune-1.0.5.dmg"], main_ready=False)
        _, verdicts = evaluate([r], changelog(), "1.0.0", NOW)
        self.assertIn(".mainignore", verdicts[0].reason)

    def test_major_needs_explicit_approval(self):
        rs = [rel("1.5.0", 100), rel("2.0.0", 50)]
        cand, verdicts = evaluate(rs, changelog(), "1.4.0", NOW)
        self.assertEqual(cand, "1.5.0")
        self.assertIn("STABLE_APPROVE=2.0.0", verdicts[0].reason)
        self.assertEqual(evaluate(rs, changelog(), "1.4.0", NOW, approved={"2.0.0"})[0], "2.0.0")

    def test_minor_and_patch_need_no_approval(self):
        self.assertEqual(evaluate([rel("1.5.1", 50)], changelog(), "1.4.0", NOW)[0], "1.5.1")

    def test_ci_conclusions(self):
        self.assertTrue(ci_conclusions_ok(["success", "success"]))
        self.assertTrue(ci_conclusions_ok(["success", "skipped"]))
        self.assertFalse(ci_conclusions_ok([]), "no CI is not green CI")
        self.assertFalse(ci_conclusions_ok(["success", "failure"]))
        self.assertFalse(ci_conclusions_ok(["success", None]), "still running")
        self.assertFalse(ci_conclusions_ok(["cancelled"]))

    def test_open_bug_issue_blocks_version(self):
        rs = [rel("1.1.0", 100), rel("1.2.0", 50)]
        bugs = [("Crash when cleaning", "Crash when cleaning\nHappens in v1.2.0 since yesterday.")]
        cand, verdicts = evaluate(rs, changelog(), "1.0.0", NOW, bug_issues=bugs)
        self.assertEqual(cand, "1.1.0")
        self.assertIn("Crash when cleaning", verdicts[0].reason)

    def test_non_semver_tags_ignored(self):
        rs = [Release(version="nightly", published=NOW - timedelta(hours=100)), rel("1.1.0", 50)]
        cand, verdicts = evaluate(rs, changelog(), "1.0.0", NOW)
        self.assertEqual(cand, "1.1.0")
        self.assertFalse(verdicts[-1].ok)

    def test_numeric_ordering(self):
        rs = [rel("1.9.0", 100), rel("1.10.0", 50)]
        self.assertEqual(evaluate(rs, changelog(), "1.0.0", NOW)[0], "1.10.0")


class MainStatusTests(unittest.TestCase):
    def test_no_warning_when_main_is_stable(self):
        _, verdicts = evaluate([rel("1.0.0", 100)], changelog(), "1.0.0", NOW)
        self.assertIsNone(main_status("1.0.0", verdicts))

    def test_warns_when_main_got_ahead_of_soak(self):
        _, verdicts = evaluate([rel("1.0.0", 100), rel("1.1.0", 2)], changelog(), "1.1.0", NOW)
        w = main_status("1.1.0", verdicts)
        self.assertIn("1.1.0", w)
        self.assertIn("soaking", w)
        self.assertIn("latest stable: 1.0.0", w)

    def test_warns_when_main_has_known_bugs(self):
        rs = [rel("1.0.0", 100), rel("1.0.1", 50)]
        _, verdicts = evaluate(rs, changelog(("1.0.1", ["Fixed"])), "1.0.0", NOW)
        self.assertIn("fixed later", main_status("1.0.0", verdicts))

    def test_main_without_release(self):
        _, verdicts = evaluate([rel("1.0.0", 100)], changelog(), "1.5.0", NOW)
        self.assertIn("has no published Release", main_status("1.5.0", verdicts))
        self.assertIsNone(main_status(None, verdicts))


class MainFilesTests(unittest.TestCase):
    PATTERNS = load_patterns("""
        # comment
        .claude/
        Tests/
        CLAUDE.md
        scripts/check.sh
        scripts/tests/
        docs/*.draft
    """)

    def test_load_patterns(self):
        self.assertEqual(self.PATTERNS[0], ".claude/")
        self.assertNotIn("# comment", self.PATTERNS)
        self.assertEqual(len(self.PATTERNS), 6)

    def test_folders_exact_files_and_globs(self):
        for p in [".claude/settings.json", ".claude/hooks/a.sh", "Tests/PruneTests/X.swift", "CLAUDE.md",
                  "scripts/check.sh", "scripts/tests/test_stable.py", "docs/notes.draft"]:
            self.assertTrue(is_excluded(p, self.PATTERNS), p)

    def test_essential_files_stay(self):
        for p in ["Sources/Prune/App/PruneApp.swift", "Package.swift", "README.md", "LICENSE",
                  "scripts/build_app.sh", "scripts/check.sh.bak", "TestsExtra/a", "src/Tests/a",
                  "docs/guide.md", "CLAUDE.md.txt", ".claudeignore"]:
            self.assertFalse(is_excluded(p, self.PATTERNS), p)

    def test_excluded_paths_keeps_order(self):
        paths = ["CLAUDE.md", "Package.swift", "Tests/a.swift", "Sources/b.swift"]
        self.assertEqual(excluded_paths(paths, self.PATTERNS), ["CLAUDE.md", "Tests/a.swift"])

    def test_repository_mainignore_keeps_what_builds_the_app(self):
        root = os.path.join(os.path.dirname(__file__), "..", "..")
        patterns = load_patterns(open(os.path.join(root, ".mainignore"), encoding="utf-8").read())
        for essential in ["Package.swift", "Sources/Prune/App/PruneApp.swift", "Resources/Info.plist",
                          "Resources/How to open.txt", "Resources/pt-PT.lproj/Localizable.strings",
                          "Resources/en.lproj/InfoPlist.strings", "scripts/build_app.sh", "scripts/make_dmg.sh",
                          "scripts/make_icon.swift", "scripts/make_dmg_background.swift", "scripts/install.sh",
                          "scripts/setup_signing.sh", "README.md", "CHANGELOG.md", "LICENSE", ".gitignore",
                          "SECURITY.md", "CONTRIBUTING.md"]:
            self.assertFalse(is_excluded(essential, patterns), essential)
        for dev_only in [".mainignore", "CLAUDE.md", ".claude/settings.json", ".githooks/pre-push",
                         "Tests/PruneTests/ShredderTests.swift", "scripts/test.sh", "scripts/ship.sh",
                         "scripts/stable.py", "scripts/tests/test_stable.py", "scripts/check_localization.py",
                         "docs/RELEASE_CRITERIA.md",
                         ".github/workflows/ci.yml"]:
            self.assertTrue(is_excluded(dev_only, patterns), dev_only)

    def test_plist_version(self):
        import plistlib
        self.assertEqual(plist_version(plistlib.dumps({"CFBundleShortVersionString": "1.2.6"})), "1.2.6")
        self.assertIsNone(plist_version(b""))
        self.assertIsNone(plist_version(b"not a plist"))


if __name__ == "__main__":
    unittest.main()
