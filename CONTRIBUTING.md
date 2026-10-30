# Contributing

Thank you for your interest. Prune deletes files, so the priority is that it never deletes what it should not. Before speed or new features.

## Branches

- **`dev`**: where the work happens. Pull Requests go here.
- **`main`**: only the stable version, with what is needed to build it. Updated automatically; does not accept direct Pull Requests.

## Setup

Requires macOS 12 or later and the Xcode Command Line Tools (`xcode-select --install`), or Xcode.

```bash
git clone -b dev https://github.com/viniciuslopesgit/prune.git
cd prune
./scripts/setup_hooks.sh   # check before each commit and each push
./scripts/test.sh          # unit tests
./scripts/check.sh         # quick check (the same as the pre-commit hook)
./scripts/pentest.sh       # penetration tests, in an isolated environment
```

## Rules for changes

1. **Tests in the same Pull Request.** A new or changed feature comes with tests in `Tests/PruneTests`. A fix comes with a test that failed before it. A new file in `Sources/` without tests blocks the commit.
2. **Everything that deletes goes through `SafetyGuard.canDelete`.** Never call `FileManager.removeItem`, `trashItem` or `rm` directly on paths that have not gone through it. Code that deletes, runs as administrator or runs a shell only lives in the files listed in `scripts/pentest.sh`; a new place needs its own attack test in `Tests/PruneTests/SecurityTests.swift`.
3. **Test destructive operations only in disposable folders** (`TempDir` in the tests). Never in your `~`, the real Trash or `/Applications`.
4. **Check what must not change**, as well as what changes: a link's target stays intact, a protected folder is still there.
5. **Destructive or privileged actions ask for confirmation** and show what is going to happen.
6. **No new dependencies** without discussing them first in an issue (GPL-3.0-compatible license, maintenance, real need).
7. **Privacy:** nothing leaves the Mac without consent; telemetry never includes paths, file names or app names.
8. **Code, comments, commits and CHANGELOG in English.** Interface texts are written in English with `String(localized:)` or as SwiftUI literals, and each one gets its translation in `Resources/pt-PT.lproj/Localizable.strings` (`scripts/check_localization.py` checks it).

CI runs `./scripts/check.sh --full` on macOS 14 and 15 on every Pull Request to `dev`, and it must pass. The macOS 12 pipeline (`.github/workflows/macos12.yml`) builds the app for macOS 12, runs it with the macOS 12 interface and, when a self-hosted macOS 12 runner is registered, runs it on macOS 12 itself.

## Reporting bugs

Open an issue with the Prune and macOS versions, Apple silicon or Intel, the steps to reproduce, and what you expected. Bugs that can delete data get the `bug` label and block the version from being promoted to stable.

Vulnerabilities: do **not** use public issues, see [SECURITY.md](SECURITY.md).

## Publishing

The maintainer publishes with `./scripts/ship.sh` (beta) and `./scripts/stable.sh` promotes to `main` when the [release criteria](https://github.com/viniciuslopesgit/prune/blob/dev/docs/RELEASE_CRITERIA.md) are met.
