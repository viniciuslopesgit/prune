# Release and stability criteria

A Prune version is only **stable** when there is verifiable evidence of it. Building, passing the tests or working on the author's Mac is not enough: Prune deletes files, and a bug can cost its users data.

This document defines the states of a version, what it takes to move from one to the next, how it is measured and who decides. The automatic rules are in [`scripts/stable.py`](../scripts/stable.py) (with tests in `scripts/tests`) and the checks in [`scripts/check.sh`](../scripts/check.sh). Known risks are in the [risk register](RISK_REGISTER.md).

## 1. Four different things

| Claim | What it proves | What it does **not** prove |
|---|---|---|
| The tests pass | The tested behaviour is as expected on the machines where they ran | That there are no bugs; what is not tested (e.g. each scan's rules) |
| Functionally correct | Each feature does what it promises, including edge cases and errors | That it works on other macOS versions, with other permissions or in the long run |
| Operationally reliable | Works on several machines and versions, recovers from failures, no memory leaks | That it is safe for people who do not know what they are deleting |
| Safe for the public | Nothing is deleted without consent, nothing critical can be deleted, failures do not leave the system in a bad state | Total absence of defects |

## 2. States of a version

| State | Where it is | How it gets there | Who decides |
|---|---|---|---|
| **Alpha** | Untagged commits on `dev`; local builds | Quick check in pre-commit | Whoever commits |
| **Beta** | GitHub Release marked as pre-release, with DMG and `SHA256SUMS` | `scripts/ship.sh`: local full check → commit → push `dev` → `vX.Y.Z` tag | Automatic |
| **Candidate (RC)** | The beta that `stable.sh` points to as candidate | Every automatic criterion in section 3.3 met | Automatic |
| **Stable** | "Prune X.Y.Z (stable version)" commit on `main`; Release marked **Latest** | `scripts/stable.sh --apply`: new full check in a clean copy of the tag, build and self-test of `main`'s content, Pull Request with merge | Automatic for patch and minor; **human approval** for major |

The README's "Download the latest version" link points to **Latest**, which is always the latest stable. Betas only show to those who look for them.

### Version types (SemVer)

| Type | When | Requires |
|---|---|---|
| Patch `X.Y.Z+1` | Fixes and internal changes, no new feature | Automatic criteria |
| Minor `X.Y+1.0` | Compatible new feature | Automatic criteria + tests of the new feature in the same commit |
| Major `X+1.0.0` | Incompatible change (settings, default deletion behaviour, system requirements) | Automatic criteria + `STABLE_APPROVE=X.Y.Z` + decision recorded in the Pull Request |

## 3. Quality gates

**B** = blocks, **W** = warning only. "Evidence" column: what is kept to justify the decision.

### 3.1 On every commit (`check.sh`, pre-commit hook)

| # | Check | Type | Evidence |
|---|---|---|---|
| Q1 | Syntax and execute permission of every script and hook | B | Check output |
| Q2 | Tests of the publishing scripts (`scripts/tests`) | B | Check output |
| Q3 | No `analytics.env` key in the changes; no ignored file tracked | B | Check output |
| Q4 | A new file in `Sources/` requires new or changed tests | B | Check output |
| Q5 | Warning-free build (`-warnings-as-errors`) | B | `.build/check-build-debug.log` |
| Q6 | Unit tests, 100% passing, serially | B | `.build/check-tests.log` |
| Q7 | Minimum line coverage of the files that delete or choose what is deleted (`MIN_COVERAGE`) | B | `llvm-cov` report |
| Q8 | Every interface text has a translation and every translation is used, with the same placeholders (`scripts/check_localization.py`) | B | Check output |
| Q9 | Penetration tests in an isolated environment (`scripts/pentest.sh`): the sandbox is first proven to block the network, osascript and writes outside its folder; deleting, administrator and shell calls only in reviewed files; the `Security` suite passes inside it | B | `.build/pentest.log` |

### 3.2 Before each beta (`check.sh --full`, `ship.sh`, pre-push hook)

| # | Check | Type | Evidence |
|---|---|---|---|
| R1 | Everything in section 3.1 | B | — |
| R2 | `X.Y.Z` version in `Info.plist`, with a filled-in CHANGELOG section | B | CHANGELOG |
| R3 | Universal app (arm64 + x86_64), signed, right version | B | `lipo`, `codesign --verify` |
| R4 | Self-test of the built app: every scan runs read-only and 6 checks give the expected result | B | `.build/check-selftest.log` |
| R5 | What is tested is exactly what is pushed (git tree comparison) | B | `.build/check-passed` |
| R6 | DMG and `SHA256SUMS` attached to the Release | B | GitHub Release |

### 3.3 Before stable (`stable.py`, `stable.sh`)

| # | Criterion | Type | Why this limit |
|---|---|---|---|
| S1 | Published Release, with DMG and `SHA256SUMS` | B | Whoever downloads must be able to verify the file |
| S2 | Tag in `dev`'s history, with `.mainignore` | B | `main` only builds from 1.2.9 on |
| S3 | **Green CI on the tag's commit** on macOS 14 and 15, and the macOS 12 pipeline (build for 12.0 and self-test with the macOS 12 interface; on macOS 12 itself when a self-hosted runner exists, R23) | B | It is the only evidence of compatibility outside the publisher's machine |
| S4 | No open issue labelled `bug` mentioning the version | B | For an app that deletes files, a reported and unresolved bug blocks. To keep a minor bug from blocking, do not give it the `bug` label and explain why in the issue |
| S5 | No version published later brings `### Fixed` | B | If there was a fix, the earlier version had a known defect |
| S6 | Published at least 24 h ago (`STABLE_SOAK_HOURS`) | B | It is a waiting time, **not proof of reliability**: with few users, 24 h without complaints means nothing. It lets the maintainer use the beta and CI run |
| S7 | Major only with `STABLE_APPROVE=X.Y.Z` | B | Incompatible changes need a human decision |
| S8 | New full check in a clean copy of the tag | B | Rules out caches and local changes |
| S9 | `main`'s content (without development files) builds, is signed and passes the self-test | B | `main` must build for whoever clones it |

### 3.4 What is not measured yet

These indicators are not checked today. Each one has an entry in the [risk register](RISK_REGISTER.md).

| Indicator | State | Proposal |
|---|---|---|
| Each scan's rules (what is junk) | **No tests** | Tests with temporary folders that mimic `~/Library` (risk R1) |
| Running on Intel | Built only | Manual test on Intel for each major (W) |
| Memory and time of each scan | `--bench` exists, no limits | Warning if a scan's peak memory rises more than 50% over the previous version (W) |
| Crash rate | Not measured (no crash reports, for privacy) | Issues only; an optional crash reporter would be a separate privacy decision |
| Install, update and uninstall tests | Manual | Checklist in section 6 |

## 4. Safety of operations that delete

These rules apply to all code that removes, moves, overwrites or runs as administrator.

1. **Preview first.** Each scan shows the list of what will be removed before removing it. Nothing is deleted without an explicit user action.
2. **Confirmation.** Removing user files, apps, login items and privileged tasks asks for confirmation, with the number of items and the size.
3. **Protection list.** Everything goes through `SafetyGuard.canDelete`: system folders and personal folders can never be deleted, paths are normalized and the parent folder is resolved (`/var`, `/tmp`, `/etc`).
4. **Symbolic links.** Deleting a link never touches its target; the Shredder never overwrites through a link.
5. **Reversible by default.** Personal files and apps go to the Trash. Only caches and logs are deleted directly.
6. **Least privilege.** Asks for the administrator password only when the operation fails without it, once per batch, and only for paths that passed `SafetyGuard`.
7. **Tests only in disposable folders.** Tests use `TempDir` and never touch `~`, the real Trash or `/Applications`. No destructive operation is tested directly on the developer's Mac.
8. **A cleanup that goes well does not prove it is safe.** Tests also check what must **not** change: a link's target file stays the same; shredded data really disappears, through a hard link; protected folders are still there.

## 5. Governance

| Situation | Who or what | Record |
|---|---|---|
| Beta | `ship.sh`, after the full check passes | Commit, tag, Release |
| Stable patch/minor | `stable.sh --apply` (runs at the end of every `ship.sh` and every day at 23:30) | Pull Request to `main`, with the criteria table and the evidence |
| Stable major | Maintainer, with `STABLE_APPROVE=X.Y.Z ./scripts/stable.sh --apply` | The same Pull Request, with the justification of the approval |
| Exception to a criterion (e.g. urgent security fix without the 24 h) | Maintainer: `STABLE_SOAK_HOURS=0 ./scripts/stable.sh --apply` | Reason written in the Pull Request and a line in the CHANGELOG |
| Accepted risk | Maintainer | Entry in the [risk register](RISK_REGISTER.md), with date and reason |

**There is never an exception** for Q5–Q7, Q9, R3–R5, S3, S8 or S9. These are the checks that stop a version that deletes wrongly from reaching anyone.

### Regressions and withdrawing a version

1. Open an issue labelled `bug` mentioning `vX.Y.Z`. The version immediately can no longer be promoted (S4).
2. If the version is already stable and the bug can cause data loss: edit the Release to pre-release with the note "⚠️ Withdrawn: see #N" and, on `main`, `git revert` the version's commit through a Pull Request. Since `main` has one commit per version, this restores the previous stable.
3. Publish the fix (`### Fixed`). Earlier versions are automatically rejected (S5) and the fix follows the normal path.

### Vulnerabilities

See [SECURITY.md](../SECURITY.md).

## 6. Manual checklist (each minor and major)

On a Mac or a test account that is not the main one:

- [ ] Clean install from the DMG; `shasum -a 256 -c SHA256SUMS` confirms the DMG.
- [ ] Update over the previous version: settings are kept and Full Disk Access stays granted.
- [ ] Without Full Disk Access: scans do not fail and explain what is missing.
- [ ] Cancel the administrator password prompt: nothing is deleted and the interface explains why.
- [ ] Interface in English and in Portuguese (System Settings ▸ General ▸ Language & Region ▸ Applications ▸ Prune): no untranslated or cut-off texts.
- [ ] Uninstall Prune with another app's uninstaller and through the Finder: no agents or processes are left.
- [ ] On Intel (major only): open, run Smart Scan and a cache cleanup.
- [ ] On macOS 12 (until a self-hosted macOS 12 runner exists, R23): open, the menu bar monitor shows, run Smart Scan, close and reopen the window from the menu bar.
- [ ] Similar photos on a physical Mac with macOS 14: a folder with two copies of the same photo and one different photo gives one group (CI skips this test on macOS 14, see R16).

## 7. Criteria for the first "certified GA" version

Prune's numbering is already past 1.0.0 (there are published `v1.x` tags, which are not reused). So the first version that meets **all** of these criteria should come out as **2.0.0**, with explicit approval. Until then, "stable" means: it meets the automatic criteria and has no known defects.

| # | Criterion | Required for 2.0.0 | How it is checked |
|---|---|---|---|
| G1 | Every automatic gate (section 3) met | Yes | Promotion Pull Request |
| G2 | Each scan's rules with tests and ≥ 80% coverage in the scanners (R1) | Yes | `MIN_COVERAGE` includes the scanners |
| G3 | Removal as administrator without a race between checking and deleting (R2) | Yes (1.6.4) | `SecurityTests`: the parent and grandparent folders swapped for links after the check |
| G4 | Confirmation on every destructive and privileged action (R4) | Yes | Review of the views; list in section 4 |
| G5 | Distribution without asking to disable quarantine: Developer ID and notarization, **or** an accepted risk recorded with a documented alternative (e.g. building from source) (R3) | Yes | `spctl -a -vv` accepts the app, or an entry in the risk register |
| G6 | `main` branch protection on GitHub: Pull Request only, no force-push (R10) | Yes | Repository settings |
| G7 | Private vulnerability reporting turned on in GitHub | Yes | Repository settings |
| G8 | Manual list in section 6 done and attached to the Pull Request | Yes | Pull Request |
| G9 | Pilot programme: the beta used by at least 5 people, on at least 2 macOS versions, for 7 days, with no open `bug` issues | Yes | Pilot issue with the answers |
| G10 | Memory limits per scan (section 3.4) | No (warning) | `--bench` |
| G11 | Local log of what was deleted | No, but recommended | — |
