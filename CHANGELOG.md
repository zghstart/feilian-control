# Changelog

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
