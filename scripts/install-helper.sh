#!/bin/bash
# 安装 / 升级特权助手。需要以 root 运行。
# 默认一键模式（AUTH_MODE=none）；可在 /usr/local/etc/feilian-control.conf 改为 touchid。
# 用法：sudo ./scripts/install-helper.sh [build目录]
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "请用管理员权限运行：sudo $0" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$ROOT/build}"
DEST="/usr/local/libexec/feilian"
LABEL="com.feiliancontrol.helper"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
CONFIG="/usr/local/etc/feilian-control.conf"

if [[ ! -x "$BUILD/feilian-daemon" || ! -x "$BUILD/feilian-auth" ]]; then
  echo "找不到编译好的助手，请先运行：make build" >&2
  exit 1
fi

mkdir -p "$DEST" /usr/local/bin /usr/local/etc

install -m 755 "$BUILD/feilian-daemon" "$DEST/feilian-daemon"
install -m 755 "$BUILD/feilian-auth" "$DEST/feilian-auth"
install -m 755 "$ROOT/scripts/stop.sh" "$DEST/stop.sh"
install -m 755 "$ROOT/scripts/start.sh" "$DEST/start.sh"
install -m 755 "$ROOT/scripts/status.sh" "$DEST/status.sh"
install -m 755 "$ROOT/scripts/feilianctl" /usr/local/bin/feilianctl
install -m 644 "$ROOT/launchd/$LABEL.plist" "$PLIST"

if [[ ! -f "$CONFIG" ]]; then
  printf 'AUTH_MODE=none\n' > "$CONFIG"
fi

chown -R root:wheel "$DEST" /usr/local/bin/feilianctl "$PLIST" "$CONFIG"
chmod 644 "$CONFIG"

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/var/run/$LABEL.sock"
launchctl enable "system/$LABEL"
launchctl bootstrap system "$PLIST"

sleep 1
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
  echo "helper installed and loaded"
else
  echo "helper failed to load; check /var/log/feilian-control-helper.log" >&2
  exit 1
fi
