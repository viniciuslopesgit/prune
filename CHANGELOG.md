# Changelog

Notable changes in each version. Format [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions [SemVer](https://semver.org/).

## [1.4.0] - 2026-10-22

Prune now speaks your language: the interface follows the language of your Mac, in English or Portuguese. The whole project (code, documentation and history) is now written in English.

### Added
- Automatic translation: the app shows in Portuguese on a Mac set to Portuguese (Portugal or Brazil) and in English in every other language. You can choose a language for Prune alone in System Settings ▸ General ▸ Language & Region ▸ Applications.
- Dates and "last opened" times follow the language of the interface.

### Changed
- English is the app's default language, and the installer, its instructions and the Release notes are in English.
- The README, the contribution guide, the security policy and this CHANGELOG are in English.

## [1.3.3] - 2026-10-22

More complete diagnostics for the tests on GitHub. The app does not change.

### Fixed
- The logs of the tests on GitHub are now kept and show the cause of each failure.

## [1.3.2] - 2026-10-22

Similar photos no longer fails silently.

### Fixed
- Similar photos: when the Mac cannot analyze the images, the app now warns you, instead of saying there is nothing similar. Damaged images are counted and reported.

## [1.3.1] - 2026-10-22

A fix found by the new tests on GitHub.

### Fixed
- The app builds again with Xcode 16 (Swift 6.0), used on macOS 14: image thumbnails caused a build error.

## [1.3.0] - 2026-10-22

A version only becomes stable with evidence: tests on several macOS versions, no reported bugs and verified again before it reaches main. The app does not change.

### Added
- Each Release comes with a SHA256SUMS file to confirm the downloaded DMG was not altered.
- Release criteria, risk register, security policy (SECURITY.md) and contribution guide (CONTRIBUTING.md).
- Automated tests on GitHub on macOS 14 and 15 for every change.

### Changed
- New versions come out as betas (pre-releases). "Download the latest version" now always gives the latest stable.
- For a version to become stable, the tests on GitHub must have passed. A major version needs explicit approval.

## [1.2.9] - 2026-10-22

The main branch now only has what is needed to build the stable version. The app does not change.

### Changed
- main no longer has the tests, hooks and publishing scripts, which stay only on the dev branch. Each stable version reaches main as a single commit, after being built and tested without those files.

### Fixed
- Python cache files are no longer stored in the repository.
- Publishing no longer stops with "the folder changed" when a file is removed from the repository.

## [1.2.8] - 2026-10-22

The stable version now reaches main on its own. The app does not change.

### Changed
- Each publication checks whether there is a stable version newer than main's and, if so, tests it again and takes it to main.

## [1.2.7] - 2026-10-22

main now only gets stable versions, chosen and verified automatically. The app does not change.

### Added
- Automatic selection of the stable version for main: the most recent one published at least 24 hours ago, with the installer, no reported bugs and no fixes in later versions. Before reaching main, it is tested again in a clean copy.

## [1.2.6] - 2026-10-22

Every version now goes through automated tests before being published. The app does not change.

### Added
- Automated tests for the parts that delete or choose files: folder protection, Shredder, cleanup, duplicates, similar photos and Space Lens.
- Each version is only committed and published if it passes the tests, builds without warnings and the app's self-test runs without failures.

## [1.2.5] - 2026-10-22

### Fixed
- Shredder: symbolic links inside a folder no longer cause the original file, outside the folder, to be overwritten.
- Shredder: a write failure (full disk, locked file) no longer crashes the app.
- System folder protection: now resolves links such as /var and /tmp.
- Duplicates: at least one copy of each file is always kept.
- App leftovers: system settings (printing, iCloud) and Prune's own no longer show up.
- Space Lens: items inside folders that are also marked are no longer counted twice.
- Cleanup: empty categories leave the list after cleaning.

### Changed
- Shorter, more direct app texts, README and installation instructions, with correct plurals.
- The "Speed" section is now called "System".

## [1.2.4] - 2026-10-22

First public version.

### Added
- GPL-3.0 license, this CHANGELOG and installation instructions in the README.

## [1.2.3] - 2026-10-22

### Fixed
- Signing, installation and the README work again after the name change; the project only uses the name Prune.

## [1.2.2] - 2026-10-22

### Changed
- A single leaf throughout the app (the icon's): completion screen, consent and menu bar.

## [1.2.1] - 2026-10-22

### Changed
- Code reorganized by feature; removed what was not used.

## [1.2.0] - 2026-10-22

### Removed
- RAM management: the "Speed" card in Smart Scan and the Quit/Force Quit buttons in heavy consumers. macOS manages memory on its own; the metrics stay.

## [1.1.1] - 2026-10-22

### Fixed
- The Full Disk Access assistant no longer checks the permission on its own every 1.5 s.

## [1.1.0] - 2026-10-22

### Changed
- New name, Prune, new icon (a leaf) and a new ivory-and-ink design, with light and dark mode.

### Added
- Anonymous, optional usage statistics, with a consent prompt on first launch.

## [1.0.0] - 2026-10-22

- First version: Smart Scan, Dashboard, cleanup, privacy, optimization, maintenance, uninstaller, updater, extensions, Space Lens, large files, duplicates and shredder.

[1.4.0]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.4.0
[1.3.3]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.3.3
[1.3.2]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.3.2
[1.3.1]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.3.1
[1.3.0]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.3.0
[1.2.9]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.9
[1.2.8]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.8
[1.2.7]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.7
[1.2.6]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.6
[1.2.5]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.5
[1.2.4]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.2.4
