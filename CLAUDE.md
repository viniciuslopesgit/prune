# Prune

macOS app (SwiftUI, Swift Package, Command Line Tools only). Code, comments, documentation and commits in English. The interface is translated automatically according to the system language: texts are written in English in the code (`String(localized:)` or SwiftUI literals) and each one needs its translation in `Resources/pt-PT.lproj/Localizable.strings` (checked by `scripts/check_localization.py`).

## Mandatory user rule (in force until further notice)

Whenever you change code or project files, at the end and without asking:

1. Bump the version according to the change: `./scripts/bump_version.sh patch` (fixes, internal changes), `minor` (new feature) or `major` (incompatible change).
2. Fill in the version's section in `CHANGELOG.md`: a summary paragraph (goes at the top of the Release) and the `### Added / Changed / Fixed / Removed` lists, written for the people who use the app.
3. `./scripts/ship.sh "Message (X.Y.Z)"`: rigorous tests → commit **only if they pass** → push to **dev** → `vX.Y.Z` Release on GitHub with the DMG → if there is a stable version newer than `main`'s, it verifies it in a clean copy and promotes it to `main` through a Pull Request (`stable.sh --apply`).

If the tests fail, fix and repeat until they pass; never commit failing code, never `--no-verify`. Never push directly to `main`: `main` only gets the stable version, through the `stable.sh --apply` that `ship.sh` runs at the end (the pre-push hook refuses the rest). Install in `/Applications` (`--install`) only when the user asks. The Stop hook in `.claude/settings.json` does not let you finish with uncommitted changes or unpushed commits.

## Stability criteria

The states (alpha, beta, candidate, stable), gates and governance are in `docs/RELEASE_CRITERIA.md`; the risks in `docs/RISK_REGISTER.md`. When resolving a risk, update its state in the register in the same commit. Releases come out as betas (pre-releases) and only become Latest when promoted.

## What goes to main

`main` only has what is needed to build and distribute the stable version. Everything that is development-only (tests, hooks, publishing scripts, internal documentation) goes into the `.mainignore` list in the same commit in which it is created. `stable.sh` builds the filtered content before promoting it: if something essential is left out, the promotion fails.

## Mandatory tests

No change is committed or installed without passing the quality gate (`scripts/check.sh`).

- **New or changed feature → tests in `Tests/PruneTests`**, in the same commit. A new file in `Sources/` without new or changed tests blocks the commit. `ALLOW_NO_TESTS=1` only for pure interface code (views).
- Test the logic, not the interface: what decides what gets deleted, scanned or computed. If the logic is tied to a view or to the user's real folders, extract it into a function that takes the paths/data.
- Tests only touch temporary folders (`TempDir`). Never the real Trash, `~` or `/Applications`.
- For each bug fix, a test that failed before the fix.
- The coverage minimums in `scripts/check.sh` (`MIN_COVERAGE`) only go up. New files that delete or choose files go into the list.
- Every new interface text gets its Portuguese translation in the same commit.
- Never use `git commit --no-verify` or `git push --no-verify`.

## Commands

```bash
./scripts/test.sh                        # unit tests (--filter ShredderTests for one group)
./scripts/check.sh                       # quick check (the pre-commit hook runs this)
./scripts/check.sh --full                # + version/CHANGELOG, universal signed app and self-test
./scripts/check_localization.py          # every interface text translated, no unused translations
./scripts/bump_version.sh patch|minor|major     # new version + CHANGELOG section
./scripts/ship.sh "Message (X.Y.Z)"             # tests → commit → push dev → Release
./scripts/stable.sh [--apply | --check X.Y.Z]   # stable version to main (rules in scripts/stable.py)
```

Stable version = the most recent Release with a DMG, in dev's history, with no open `bug` issues mentioning it, published ≥ 24 h ago (`STABLE_SOAK_HOURS`) and with no fixes (`### Fixed`) in versions published after it. Tests of the rules in `scripts/tests` (run by `check.sh`).
