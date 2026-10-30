# Tests and publishing

Nothing is committed or installed without passing the tests.

```bash
./scripts/setup_hooks.sh               # once: turns on the git hooks
./scripts/test.sh                      # unit tests (Tests/PruneTests)
./scripts/check.sh                     # quick check
./scripts/check.sh --full              # full check
./scripts/bump_version.sh patch        # new version (patch, minor or major) and its CHANGELOG section
./scripts/ship.sh "Commit message"     # full check → commit → push dev → Release
```

- **Quick check** (before each commit, through the `pre-commit` hook): script syntax, no `analytics.env` key in the changes, every interface text translated (`scripts/check_localization.py`), new files in `Sources/` come with tests, warning-free build, unit tests and minimum coverage of the files that delete or choose files.
- **Full check** (before each push, through the `pre-push` hook, and in `ship.sh`): all of the above, the version's CHANGELOG section filled in, a universal signed app, and the self-test of the built app.
- `./scripts/stable.sh` tells which stable version should be on `main`: the most recent Release with the DMG, with no open `bug` issues mentioning it, published at least 24 h ago and with no fixes in later versions. `--apply` verifies it again in a clean copy and promotes it to `main` through a Pull Request; `--check X.Y.Z` only verifies.
- `ship.sh` publishes the `vX.Y.Z` Release with the DMG and the notes taken from the CHANGELOG and, at the end, promotes the stable version to `main` (`stable.sh --apply`) if there is a newer one. Accepts `--install` (installs in /Applications), `--no-release` and `--no-promote`.

## Translations

The interface is written in English in the code. Every text passed to `String(localized:)` or as a literal to a SwiftUI view (`Text("…")`, `Button("…")`, `.help("…")`…) is looked up in `Resources/<language>.lproj/Localizable.strings` at runtime, and macOS picks the language that matches the system (English when there is no match). Interpolations become placeholders in the key: `String(localized: "Cleaning \(name)…")` is `"Cleaning %@…"`, an `Int` is `%lld`. Translations can reorder them with `%1$@`, `%2$@`.

To add a language, create `Resources/<code>.lproj/` with `Localizable.strings` and `InfoPlist.strings` and add the code to `CFBundleLocalizations` in `Resources/Info.plist`. `scripts/check_localization.py` (run by `check.sh`) fails when a text has no translation, a translation is no longer used, or the placeholders differ.

## What goes to main

`main` only has what is needed to build and distribute the stable version: no tests, hooks or publishing scripts. The list of what is left out is in [`.mainignore`](../.mainignore). Each stable version reaches `main` as a single "Prune X.Y.Z (stable version)" commit, with the content of the `vX.Y.Z` tag without those files, through a Pull Request.

## Criteria and risks

- [RELEASE_CRITERIA.md](RELEASE_CRITERIA.md): states of a version (alpha, beta, candidate, stable), quality gates, governance and the criteria for the first "certified GA" version.
- [RISK_REGISTER.md](RISK_REGISTER.md): known risks, priority and state.
- CI (`.github/workflows/ci.yml`) runs `./scripts/check.sh --full` on macOS 14 and 15 on every push and Pull Request to `dev`.
- The "Tests and security" pipeline (`.github/workflows/security.yml`, every push and Pull Request to `dev` and every Monday): component tests with a JUnit report and per-file coverage in the job summary; the same tests under the address, undefined-behavior and thread sanitizers; `scripts/pentest.sh`; and `scripts/security_audit.sh` plus the self-test (both interfaces) on the universal app.
- Scanner rules are tested on a fake home: `ScanRoot.$home.withValue(tempFolder) { … }` (helper `inFakeHome` in `ScannerTests.swift`). `SafetyGuard` keeps protecting the real home.
- The macOS 12 pipeline (`.github/workflows/macos12.yml`): GitHub no longer has macOS 12 runners, so it builds the universal app on macOS 15, checks that both architectures ask for macOS 12.0 and runs the self-test with the macOS 12 interface (`PRUNE_LEGACY_UI=1`). With the repository variable `MACOS12_RUNNER=true` and a self-hosted runner labelled `macos-12` (a Mac with macOS 12, the runner started from a logged-in session so the app can open its window), it also runs that app on macOS 12 itself.
