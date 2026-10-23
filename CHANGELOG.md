# Changelog

Notable changes in each version. Format [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions [SemVer](https://semver.org/).

## [1.6.3] - 2026-10-23

The website is easier to find in search engines and looks better when shared: links to it now show a preview image and description. The app does not change.

### Added
- A preview image, title and description when the website is shared on Product Hunt, X, Slack, Messages and other sites.
- Details search engines use to show Prune as a free macOS app, and a site icon in browser tabs.

### Changed
- The website's title and description say what Prune is: a free, open-source Mac cleaner and uninstaller.

## [1.6.2] - 2026-10-23

The website now explains better why macOS asks before opening Prune the first time, and how to check the app for yourself. The app does not change.

### Changed
- The website's answer on why macOS blocks Prune explains that it is an open-source project without Apple notarization, and how to read the code, check your download and build the app yourself.

## [1.6.1] - 2026-10-23

The website now looks like the app: the same ivory and ink colours, the sage leaf, wide titles and rounded panels, with a scan ring around the Prune icon. The app does not change.

### Changed
- The website design follows the app's look: its colours, its icon, wide titles and panels like the app's modules, and a scan ring that fills when the page opens.

## [1.6.0] - 2026-10-23

The Prune website has a new look and is now online at https://viniciuslopesgit.github.io/prune/. The app does not change.

### Added
- The website is published on GitHub Pages and updates by itself whenever it changes.

### Changed
- A new website design: the Prune name cut like a pruned branch, a calmer leaf-green palette and an easier-to-scan list of features.

## [1.5.0] - 2026-10-23

Prune now has its own website, in English and Portuguese, with the features, how it keeps your files safe, the requirements and answers to common questions. The app does not change.

### Added
- A website for Prune (`site/` folder) with a download button for the latest version, light and dark mode, and a Portuguese version.

## [1.4.7] - 2026-10-23

A security alert from GitHub's code scanning resolved in the release tooling. The app does not change.

### Changed
- The release tooling no longer slows down on a CHANGELOG with many blank lines (GitHub code scanning alert).

## [1.4.6] - 2026-10-23

The self-test no longer crashes on macOS 14.

### Fixed
- The self-test (`--selftest`) and the other diagnostic tools could stop the app on macOS 14: they started their scans before the app was ready to handle events. They now start once it is.

## [1.4.5] - 2026-10-23

A new look for the project page, with a screenshot of the app and a quicker guide to get started. The app does not change.

### Changed
- The README now opens with a screenshot of Prune, a download button and a three-step guide to install it and run your first scan.

## [1.4.4] - 2026-10-23

More diagnosis for a self-test crash seen on GitHub's macOS 14 test machine. The app does not change.

### Changed
- The self-test announces each step before running it, and the automatic tests on GitHub record where the app stopped if it crashes.

## [1.4.3] - 2026-10-23

Better diagnosis when the app's self-test fails. The app does not change.

### Changed
- If the self-test fails, the check now shows the exit code and keeps macOS's crash report, and the self-test output survives a crash.

## [1.4.2] - 2026-10-23

Fix to the publishing scripts. The app does not change.

### Fixed
- Promoting the stable version to main no longer fails when the development branch differs a lot from that version (as after the translation to English in 1.4.0); the fix shipped in 1.4.1's scripts.
- The promotion no longer prints its success message twice, once in Portuguese.

## [1.4.1] - 2026-10-23

The automatic tests on GitHub now pass on macOS 14 too. The app does not change.

### Fixed
- The similar photos test is skipped, with the reason shown, on machines where macOS cannot run the image analysis (such as GitHub's macOS 14 test machine). Any other analysis error still fails it.
- Cleaning up the main branch no longer marks a version as the latest stable one when it does not meet the stability criteria.

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

[1.6.3]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.6.3
[1.6.2]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.6.2
[1.6.1]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.6.1
[1.6.0]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.6.0
[1.5.0]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.5.0
[1.4.7]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.4.7
[1.4.6]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.4.6
[1.4.5]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.4.5
[1.4.4]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.4.4
[1.4.3]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.4.3
[1.4.2]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.4.2
[1.4.1]: https://github.com/viniciuslopesgit/prune/releases/tag/v1.4.1
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
