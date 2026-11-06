# Changelog

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
