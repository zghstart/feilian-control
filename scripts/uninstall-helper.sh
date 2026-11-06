#!/bin/bash
# 卸载特权助手（一次性操作，需要管理员权限）。
# 不会删除飞连本身；会移除 pkg 安装到 /Applications 的菜单栏 App。
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

LABEL="com.feiliancontrol.helper"

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist"
rm -f "/var/run/$LABEL.sock"

rm -rf /usr/local/libexec/feilian
rm -f /usr/local/bin/feilianctl
rm -f /usr/local/etc/feilian-control.conf
rm -f /var/log/feilian-control-helper.log
rm -rf "/Applications/飞连控制.app"

echo "特权助手已卸载。"
echo "注意：此后“飞连控制”菜单栏 App 和 feilianctl 将无法使用。"
echo "可改用仓库中的脚本：sudo ./scripts/stop.sh 或 sudo ./scripts/start.sh"
