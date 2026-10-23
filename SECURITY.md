# Security

Prune deletes files and, for some tasks, runs commands as administrator. A security bug here can cost data. Thank you for helping to find them.

## Supported versions

| Version | Security fixes |
|---|---|
| Latest stable ([Latest](https://github.com/viniciuslopesgit/prune/releases/latest)) | Yes |
| Latest beta (pre-release) | Yes |
| Older | No: update to the latest stable |

## How to report

**Do not open a public issue** for a vulnerability.

Use **Security ▸ Report a vulnerability** in the [repository](https://github.com/viniciuslopesgit/prune/security). If that option does not show, open an issue titled only "Security contact", without details, and the maintainer will reply with a private channel.

Include, if you can:

- the Prune and macOS versions, and whether it is Apple silicon or Intel;
- the steps to reproduce, preferably in a test folder and not on real data;
- the impact: what can be deleted, read or run, and with what privileges.

## What counts as a vulnerability

- Deleting, moving or overwriting anything outside what the user chose: protected folders, the target of symbolic links, other volumes.
- Running commands as administrator with paths or arguments that someone can control.
- Sending data off the Mac without consent, or sending more than [described in the README](README.md#security-and-privacy).
- Reading or exposing passwords, cookies or browsing data beyond what is needed to clean them.

## Timelines

Timelines of a single-maintainer project, met as far as possible:

| Step | Timeline |
|---|---|
| Acknowledge receipt | 3 days |
| Initial assessment and severity | 7 days |
| Fix for high or critical severity | 30 days |

The fix comes out as a patch, with `### Fixed` in the CHANGELOG, which automatically takes the affected versions off the path to stable. In urgent cases the 24 h waiting period can be waived, with the reason recorded (see the [release criteria](docs/RELEASE_CRITERIA.md#5-governance)). Once the fix is published, the report is disclosed with credit to whoever sent it, if they wish.

## What Prune does to limit the risk

- A list of protected folders that are never deleted, with normalized paths and parent-folder links resolved.
- Personal files and apps go to the Trash; only caches and logs are deleted directly.
- The administrator password is only asked for when it is needed, and only for paths that went through the protection list.
- Telemetry off until there is consent, without names of files, folders or apps.
- No third-party dependencies.

Known and still unresolved risks are in the [risk register](https://github.com/viniciuslopesgit/prune/blob/dev/docs/RISK_REGISTER.md).
