# Changelog

## 0.3.0 — 2026-11-08

- Added launch at login, operation progress and disabled action buttons while an operation is running.
- Release binaries now target Apple Silicon (arm64) only; Intel builds are no longer produced.
- The menu now distinguishes background services from UI-only state and reports a missing helper explicitly.
- Added `feilianctl help`, `version`, `doctor`, and an installed `feilianctl uninstall` entry point.
- Uninstall restores FeiLian by default so services are not accidentally left disabled; `--keep-state` is available explicitly.
- Added a copy button for authentication-mode commands and a diagnostic window in the menu bar app.
- Stop, restore, and UI-quit now report real failures instead of unconditionally claiming success.
- Installers verify the running helper and socket and fail visibly when setup is incomplete.
- Fixed a helper pipe-handling deadlock that could occur with large script output.
- Added side-effect-free CLI regression tests and 15 mocked launchd/Finder behavior cases; CI now also builds the package on every push and pull request.
- Moved privileged executables, scripts and authentication configuration from potentially user-writable `/usr/local` ancestors to root-owned `/Library/PrivilegedHelperTools/feilian-control`; valid settings are migrated and legacy files removed.
- Fixed long Finder Sync process matching with bounded full-command patterns, included the MDM Ruby process in detailed output, and refreshed launch-at-login state after external changes.
- Shared duplicated service-control logic in `service-common.sh`, handled spaces in home paths, and limited process matching to exact FeiLian process names.
- Missing, unreadable or invalid authentication configuration now cancels privileged actions instead of silently enabling one-click mode; diagnostics also check ownership, symlinks and write permissions.
- Added contributor/security documentation, GitHub issue/PR templates, EditorConfig and Git line-ending rules.
- Added release-tag/version validation, macOS 13 package requirements, CI timeouts and directly usable SHA-256 checksum files.
- Restore now fails when no background process appears, and stop still attempts bootout after a transient launchd query failure.
- Reinstall repairs invalid authentication configuration while preserving valid settings; CRLF configuration is handled consistently.
- Doctor performs a read-only helper ping, and uninstall supports legacy helper paths and unregisters the app login item before removal.
- The menu bar snapshot and CLI status now share one process-detection implementation.

## 0.2.0 — 2026-11-07

- Added a menu bar app (`飞连控制.app`) with stop / quit UI / restore / status.
- Added a prebuilt universal `.pkg` release (Apple Silicon + Intel); no compilation required for users.
- Added `AUTH_MODE` config:
  - `none` (default): one-click, no Touch ID.
  - `touchid`: verify with Touch ID before stop / restore.
- Added `feilianctl stop-ui` and `feilianctl auth`.
- Added pkg build, component plist, postinstall setup, and automatic GitHub Release workflow.
- `make apps` now installs the menu bar app; the three AppleScript apps moved to `make legacy-apps`.
- Updated README, security notes, and installer/uninstaller messages.

## 0.1.0 — 2026-11-07

- Initial public release.
- Three AppleScript apps: stop, restore, status.
- `feilianctl` CLI with `stop`, `start`, `status`.
- Touch ID-gated root helper (`com.feiliancontrol.helper`) with a Unix socket.
- Stop/restore covers:
  - `com.corplink.mdm.policy`
  - `com.volcengine.corplink.systemextension`
  - `com.volcengine.corplink.service`
  - `com.volcengine.corplink.agent`
  - `CorpLink`
  - Finder Sync extension
- Tested with FeiLian 3.2.16 (3.2.16.12794) on macOS 26.6.2 (Darwin 25.6.0).
