"""Testes das regras de scripts/stable.py (python3 -m unittest discover -s scripts/tests)."""

import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from stable import (Release, changelog_sections, evaluate, excluded_paths, has_fixes, is_excluded,  # noqa: E402
                    load_patterns, main_status, mentions, parse_version, plist_version)  # noqa: E402

NOW = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)


def rel(version, hours_ago, **kw):
    kw.setdefault("assets", [f"Prune-{version}.dmg"])
    return Release(version=version, published=NOW - timedelta(hours=hours_ago), **kw)


def changelog(*sections):
    """sections: (versão, [títulos ###]) da mais recente para a mais antiga."""
    out = "# Changelog\n\nTexto.\n\n"
    for version, heads in sections:
        out += f"## [{version}] - 2026-10-30\n\nResumo.\n\n"
        for h in heads:
            out += f"### {h}\n- Uma alteração.\n\n"
    return out + "[1.0.0]: https://example.com\n"


class ParsingTests(unittest.TestCase):
    def test_parse_version(self):
        self.assertEqual(parse_version("v1.2.10"), (1, 2, 10))
        self.assertEqual(parse_version("1.2.3"), (1, 2, 3))
        self.assertIsNone(parse_version("v1.2"))
        self.assertIsNone(parse_version("nightly"))
        self.assertGreater(parse_version("1.10.0"), parse_version("1.9.9"))

    def test_sections(self):
        s = changelog_sections(changelog(("1.1.0", ["Adicionado"]), ("1.0.0", ["Corrigido"])))
        self.assertEqual(set(s), {"1.1.0", "1.0.0"})
        self.assertIn("### Adicionado", s["1.1.0"])
        self.assertNotIn("Corrigido", s["1.1.0"])

    def test_has_fixes(self):
        self.assertTrue(has_fixes("### Corrigido\n- Algo.\n"))
        self.assertTrue(has_fixes("Resumo\n\n### Corrigido\n\n- Algo.\n"))
        self.assertFalse(has_fixes("### Corrigido\n\n### Alterado\n- x\n"), "secção vazia não conta")
        self.assertFalse(has_fixes("### Adicionado\n- Corrigido o texto.\n"))
        self.assertFalse(has_fixes(None))

    def test_mentions(self):
        self.assertTrue(mentions("Falha na v1.2.6 ao limpar", "1.2.6"))
        self.assertTrue(mentions("versão 1.2.6", "1.2.6"))
        self.assertFalse(mentions("versão 1.2.60", "1.2.6"))
        self.assertFalse(mentions("versão 11.2.6", "1.2.6"))
        self.assertFalse(mentions("versão 1.2.6.1", "1.2.6"))


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
        self.assertIn("em observação", verdicts[0].reason)

    def test_soak_hours_configurable(self):
        rs = [rel("1.0.0", 100), rel("1.1.0", 2)]
        self.assertEqual(evaluate(rs, changelog(), "1.0.0", NOW, soak_hours=1)[0], "1.1.0")
        self.assertIsNone(evaluate(rs, changelog(), "1.0.0", NOW, soak_hours=3)[0])

    def test_later_fix_rejects_older_versions(self):
        # 1.2.1 corrige erros: 1.2.0 e anteriores ficam de fora; 1.2.1 ainda está em observação.
        rs = [rel("1.0.0", 200), rel("1.2.0", 100), rel("1.2.1", 5)]
        log = changelog(("1.2.1", ["Corrigido"]), ("1.2.0", ["Adicionado"]))
        cand, verdicts = evaluate(rs, log, "1.0.0", NOW)
        self.assertIsNone(cand)
        by = {v.version: v for v in verdicts}
        self.assertIn("corrigidos depois, na 1.2.1", by["1.2.0"].reason)
        self.assertIn("em observação", by["1.2.1"].reason)

    def test_fix_release_becomes_stable_after_soak(self):
        rs = [rel("1.0.0", 200), rel("1.2.0", 100), rel("1.2.1", 30)]
        log = changelog(("1.2.1", ["Corrigido"]), ("1.2.0", ["Adicionado"]))
        self.assertEqual(evaluate(rs, log, "1.0.0", NOW)[0], "1.2.1")

    def test_fix_in_own_section_does_not_reject_itself(self):
        rs = [rel("1.1.0", 50)]
        self.assertEqual(evaluate(rs, changelog(("1.1.0", ["Corrigido"])), "1.0.0", NOW)[0], "1.1.0")

    def test_unpublished_fix_does_not_count(self):
        # Uma Release em rascunho com correções ainda não diz nada sobre as anteriores.
        rs = [rel("1.1.0", 50), rel("1.1.1", 30, draft=True)]
        self.assertEqual(evaluate(rs, changelog(("1.1.1", ["Corrigido"])), "1.0.0", NOW)[0], "1.1.0")

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
            rel("2.0.0", 100, prerelease=True),
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
        self.assertIn("pré-lançamento", reasons["2.0.0"])
        self.assertIn("rascunho", reasons["1.9.0"])
        self.assertIn("Prune-1.8.0.dmg", reasons["1.8.0"])
        self.assertIn("Prune-1.7.0.dmg", reasons["1.7.0"])
        self.assertIn("histórico do dev", reasons["1.6.0"])
        self.assertIn(".mainignore", reasons["1.5.5"])

    def test_open_bug_issue_blocks_version(self):
        rs = [rel("1.1.0", 100), rel("1.2.0", 50)]
        bugs = [("Crash ao limpar", "Crash ao limpar\nAcontece na v1.2.0 desde ontem.")]
        cand, verdicts = evaluate(rs, changelog(), "1.0.0", NOW, bug_issues=bugs)
        self.assertEqual(cand, "1.1.0")
        self.assertIn("Crash ao limpar", verdicts[0].reason)

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
        self.assertIn("em observação", w)
        self.assertIn("última estável: 1.0.0", w)

    def test_warns_when_main_has_known_bugs(self):
        rs = [rel("1.0.0", 100), rel("1.0.1", 50)]
        _, verdicts = evaluate(rs, changelog(("1.0.1", ["Corrigido"])), "1.0.0", NOW)
        self.assertIn("corrigidos depois", main_status("1.0.0", verdicts))

    def test_main_without_release(self):
        _, verdicts = evaluate([rel("1.0.0", 100)], changelog(), "1.5.0", NOW)
        self.assertIn("não tem Release", main_status("1.5.0", verdicts))
        self.assertIsNone(main_status(None, verdicts))


class MainFilesTests(unittest.TestCase):
    PATTERNS = load_patterns("""
        # comentário
        .claude/
        Tests/
        CLAUDE.md
        scripts/check.sh
        scripts/tests/
        docs/*.draft
    """)

    def test_load_patterns(self):
        self.assertEqual(self.PATTERNS[0], ".claude/")
        self.assertNotIn("# comentário", self.PATTERNS)
        self.assertEqual(len(self.PATTERNS), 6)

    def test_folders_exact_files_and_globs(self):
        for p in [".claude/settings.json", ".claude/hooks/a.sh", "Tests/PruneTests/X.swift", "CLAUDE.md",
                  "scripts/check.sh", "scripts/tests/test_stable.py", "docs/notas.draft"]:
            self.assertTrue(is_excluded(p, self.PATTERNS), p)

    def test_essential_files_stay(self):
        for p in ["Sources/Prune/App/PruneApp.swift", "Package.swift", "README.md", "LICENSE",
                  "scripts/build_app.sh", "scripts/check.sh.bak", "TestsExtra/a", "src/Tests/a",
                  "docs/guia.md", "CLAUDE.md.txt", ".claudeignore"]:
            self.assertFalse(is_excluded(p, self.PATTERNS), p)

    def test_excluded_paths_keeps_order(self):
        paths = ["CLAUDE.md", "Package.swift", "Tests/a.swift", "Sources/b.swift"]
        self.assertEqual(excluded_paths(paths, self.PATTERNS), ["CLAUDE.md", "Tests/a.swift"])

    def test_repository_mainignore_keeps_what_builds_the_app(self):
        root = os.path.join(os.path.dirname(__file__), "..", "..")
        patterns = load_patterns(open(os.path.join(root, ".mainignore"), encoding="utf-8").read())
        for essential in ["Package.swift", "Sources/Prune/App/PruneApp.swift", "Resources/Info.plist",
                          "Resources/Como abrir.txt", "scripts/build_app.sh", "scripts/make_dmg.sh",
                          "scripts/make_icon.swift", "scripts/make_dmg_background.swift", "scripts/install.sh",
                          "scripts/setup_signing.sh", "README.md", "CHANGELOG.md", "LICENSE", ".gitignore"]:
            self.assertFalse(is_excluded(essential, patterns), essential)
        for dev_only in [".mainignore", "CLAUDE.md", ".claude/settings.json", ".githooks/pre-push",
                         "Tests/PruneTests/ShredderTests.swift", "scripts/test.sh", "scripts/ship.sh",
                         "scripts/stable.py", "scripts/tests/test_stable.py"]:
            self.assertTrue(is_excluded(dev_only, patterns), dev_only)

    def test_plist_version(self):
        import plistlib
        self.assertEqual(plist_version(plistlib.dumps({"CFBundleShortVersionString": "1.2.6"})), "1.2.6")
        self.assertIsNone(plist_version(b""))
        self.assertIsNone(plist_version(b"not a plist"))


if __name__ == "__main__":
    unittest.main()
