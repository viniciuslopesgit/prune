"""Escolhe a versão estável que deve estar no main.

Uma versão publicada é estável quando, por esta ordem:
  1. é uma Release publicada (nem rascunho nem pré-lançamento) com o DMG;
  2. a tag está no histórico do dev;
  3. não tem issues abertas com a etiqueta "bug" que a mencionem (vX.Y.Z ou X.Y.Z);
  4. já está publicada há pelo menos SOAK horas (período de observação) sem problemas;
  5. nenhuma versão publicada depois dela traz correções (### Corrigido no CHANGELOG):
     se trouxer, a versão tinha erros conhecidos e a estável passa a ser a da correção,
     quando esta também cumprir as regras.
A candidata é a versão mais recente que cumpre tudo; só é promovida se for mais nova do que a do main.
Depois, o scripts/stable.sh volta a correr a verificação completa no commit da tag antes de a promover.

Uso: python3 scripts/stable.py [--json]   (dados do GitHub via gh e do git)
"""

import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

DEFAULT_SOAK_HOURS = 24


@dataclass
class Release:
    version: str
    published: datetime
    draft: bool = False
    prerelease: bool = False
    assets: list = field(default_factory=list)
    on_dev: bool = True


@dataclass
class Verdict:
    version: str
    ok: bool
    reason: str


def parse_version(v):
    """'v1.2.10' → (1, 2, 10). Devolve None para tags que não são X.Y.Z."""
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", v.strip())
    return tuple(int(x) for x in m.groups()) if m else None


def changelog_sections(text):
    """{versão: texto da secção} a partir do CHANGELOG."""
    sections = {}
    for m in re.finditer(r"^## \[(\d+\.\d+\.\d+)\][^\n]*\n(.*?)(?=^## \[|^\[\d|\Z)", text, re.M | re.S):
        sections[m.group(1)] = m.group(2)
    return sections


def has_fixes(section):
    return re.search(r"^### Corrigido\s*$\n(?:\s*\n)*- \S", section or "", re.M) is not None


def mentions(issue_text, version):
    return re.search(rf"(?<![\d.])v?{re.escape(version)}(?![\d.])", issue_text) is not None


def main_status(main_version, verdicts):
    """Aviso quando o main tem uma versão que não cumpre as regras (None se estiver tudo bem)."""
    v = next((v for v in verdicts if v.version == main_version), None)
    if main_version is None or (v and v.ok):
        return None
    reason = v.reason if v else "não tem Release publicada"
    stable = next((x.version for x in verdicts if x.ok and parse_version(x.version) < parse_version(main_version)), None)
    return f"o main tem a {main_version}, que ainda não é estável ({reason}); última estável: {stable or 'nenhuma'}"


def evaluate(releases, changelog, main_version, now, soak_hours=DEFAULT_SOAK_HOURS, bug_issues=()):
    """Devolve (candidata ou None, [Verdict] da mais recente para a mais antiga)."""
    sections = changelog_sections(changelog)
    main_key = parse_version(main_version) if main_version else None
    published = sorted(
        (r for r in releases if parse_version(r.version) and not r.draft and not r.prerelease),
        key=lambda r: parse_version(r.version),
        reverse=True,
    )
    verdicts = []
    for r in sorted(releases, key=lambda r: parse_version(r.version) or (-1,), reverse=True):
        key = parse_version(r.version)
        if key is None:
            verdicts.append(Verdict(r.version, False, "não é uma versão X.Y.Z"))
            continue
        if r.draft or r.prerelease:
            verdicts.append(Verdict(r.version, False, "rascunho ou pré-lançamento"))
            continue
        if f"Prune-{r.version}.dmg" not in r.assets:
            verdicts.append(Verdict(r.version, False, f"a Release não tem o Prune-{r.version}.dmg"))
            continue
        if not r.on_dev:
            verdicts.append(Verdict(r.version, False, "a tag não está no histórico do dev"))
            continue
        bugs = [title for title, text in bug_issues if mentions(text, r.version)]
        if bugs:
            verdicts.append(Verdict(r.version, False, f"issue de bug aberta: {bugs[0]}"))
            continue
        fixed_by = [n.version for n in published if parse_version(n.version) > key and has_fixes(sections.get(n.version))]
        if fixed_by:
            verdicts.append(Verdict(r.version, False, f"tem erros corrigidos depois, na {fixed_by[-1]}"))
            continue
        age = now - r.published
        if age < timedelta(hours=soak_hours):
            until = (r.published + timedelta(hours=soak_hours)).astimezone().strftime("%d/%m %H:%M")
            verdicts.append(Verdict(r.version, False, f"em observação até {until} ({soak_hours:g} h)"))
            continue
        verdicts.append(Verdict(r.version, True, "estável"))

    candidate = next((v.version for v in verdicts if v.ok), None)
    if candidate and main_key and parse_version(candidate) <= main_key:
        candidate = None
    return candidate, verdicts


# ---- Recolha de dados (git e gh) -------------------------------------------------------------

def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def gather():
    run("git", "fetch", "-q", "--tags", "origin", "dev", "main")
    data = json.loads(run("gh", "release", "list", "--limit", "100", "--json",
                          "tagName,publishedAt,isDraft,isPrerelease"))
    releases = []
    for d in data:
        tag = d["tagName"]
        assets = json.loads(run("gh", "release", "view", tag, "--json", "assets"))["assets"]
        on_dev = subprocess.run(["git", "merge-base", "--is-ancestor", f"refs/tags/{tag}", "origin/dev"]).returncode == 0
        releases.append(Release(
            version=tag.lstrip("v"),
            published=datetime.fromisoformat(d["publishedAt"].replace("Z", "+00:00")),
            draft=d["isDraft"], prerelease=d["isPrerelease"],
            assets=[a["name"] for a in assets], on_dev=on_dev,
        ))
    issues = json.loads(run("gh", "issue", "list", "--state", "open", "--label", "bug", "--limit", "200",
                            "--json", "title,body"))
    bug_issues = [(i["title"], i["title"] + "\n" + (i["body"] or "")) for i in issues]
    changelog = run("git", "show", "origin/dev:CHANGELOG.md")
    main_tag = subprocess.run(["git", "describe", "--tags", "--abbrev=0", "--match", "v*", "origin/main"],
                              capture_output=True, text=True).stdout.strip()
    return releases, changelog, main_tag.lstrip("v") or None, bug_issues


def main():
    import os
    soak = float(os.environ.get("STABLE_SOAK_HOURS", DEFAULT_SOAK_HOURS))
    releases, changelog, main_version, bug_issues = gather()
    candidate, verdicts = evaluate(releases, changelog, main_version, datetime.now(timezone.utc), soak, bug_issues)
    warning = main_status(main_version, verdicts)
    if "--json" in sys.argv:
        print(json.dumps({"main": main_version, "candidate": candidate, "main_warning": warning,
                          "verdicts": [v.__dict__ for v in verdicts]}, ensure_ascii=False))
        return
    print(f"main: {main_version or '(sem versão)'}")
    for v in verdicts:
        mark = "✓" if v.ok else "·"
        here = "  ← main" if v.version == main_version else ""
        print(f"  {mark} {v.version:<8} {v.reason}{here}")
    if warning:
        print(f"⚠️  Atenção: {warning}.")
    if candidate:
        print(f"Candidata a estável: {candidate} (mais nova do que o main)")
    elif not warning:
        print("Nenhuma versão para promover: o main já tem a estável mais recente.")
    else:
        print("Nenhuma versão para promover agora.")


if __name__ == "__main__":
    main()
