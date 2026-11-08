#!/bin/bash
# 安装 / 升级特权助手。需要以 root 运行。
# 默认一键模式（AUTH_MODE=none）；可在 /Library/PrivilegedHelperTools/feilian-control/auth.conf 改为 touchid。
# 用法：sudo ./scripts/install-helper.sh [build目录]
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "请用管理员权限运行：sudo $0" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$ROOT/build}"
DEST="/Library/PrivilegedHelperTools/feilian-control"
HELPER_PARENT="$(dirname "$DEST")"
OLD_DEST="/usr/local/libexec/feilian"
LABEL="com.feiliancontrol.helper"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
CONFIG="/Library/PrivilegedHelperTools/feilian-control/auth.conf"
OLD_CONFIG="/usr/local/etc/feilian-control.conf"

if [[ ! -x "$BUILD/feilian-daemon" || ! -x "$BUILD/feilian-auth" ]]; then
  echo "找不到编译好的助手，请先运行：make build" >&2
  exit 1
fi

if [[ -L "$HELPER_PARENT" || -L "$DEST" ]]; then
  echo "特权助手目录不能是符号链接：$HELPER_PARENT / $DEST" >&2
  exit 1
fi
mkdir -p "$HELPER_PARENT" "$DEST" /usr/local/bin
chown root:wheel "$HELPER_PARENT" "$DEST"
chmod 755 "$HELPER_PARENT" "$DEST"

install -m 755 "$BUILD/feilian-daemon" "$DEST/feilian-daemon"
install -m 755 "$BUILD/feilian-auth" "$DEST/feilian-auth"
install -m 755 "$ROOT/scripts/auth-common.sh" "$DEST/auth-common.sh"
install -m 755 "$ROOT/scripts/service-common.sh" "$DEST/service-common.sh"
install -m 755 "$ROOT/scripts/stop.sh" "$DEST/stop.sh"
install -m 755 "$ROOT/scripts/start.sh" "$DEST/start.sh"
install -m 755 "$ROOT/scripts/status.sh" "$DEST/status.sh"
install -m 755 "$ROOT/scripts/doctor.sh" "$DEST/doctor.sh"
install -m 755 "$ROOT/scripts/uninstall-helper.sh" "$DEST/uninstall-helper.sh"
install -m 755 "$ROOT/scripts/feilianctl" /usr/local/bin/feilianctl
install -m 644 "$ROOT/launchd/$LABEL.plist" "$PLIST"

if [[ -L "$CONFIG" ]] || [[ -e "$CONFIG" && ! -f "$CONFIG" ]]; then
  echo "验证配置必须是普通文件且不能是符号链接：$CONFIG" >&2
  exit 1
fi
if ! source "$ROOT/scripts/auth-common.sh"; then
  echo "无法加载验证配置解析：$ROOT/scripts/auth-common.sh" >&2
  exit 1
fi
new_mode="$(resolve_install_auth_mode "$CONFIG" "$OLD_CONFIG")"
printf 'AUTH_MODE=%s\n' "$new_mode" > "$CONFIG"

chown -R root:wheel "$DEST" /usr/local/bin/feilianctl "$PLIST" "$CONFIG"
chmod 644 "$CONFIG"

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -rf "$OLD_DEST"
rm -f "$OLD_CONFIG"
rm -f "/var/run/$LABEL.sock"
launchctl enable "system/$LABEL"
launchctl bootstrap system "$PLIST"

ready=false
for _ in {1..10}; do
  if helper_info="$(launchctl print "system/$LABEL" 2>/dev/null)" && \
     grep -q 'state = running' <<<"$helper_info" && \
     [[ -S "/var/run/$LABEL.sock" ]]; then
    ready=true
    break
  fi
  sleep 1
done

if [[ "$ready" != true ]]; then
  echo "helper failed to start; check /var/log/feilian-control-helper.log" >&2
  exit 1
fi

if /bin/bash "$DEST/doctor.sh"; then
  echo "飞连控制安装完成，助手已运行。可运行 feilianctl help 查看用法。"
else
  echo "安装自检失败，请根据上方诊断修复。" >&2
  exit 1
fi
