#!/bin/bash
# 卸载特权助手（一次性操作，需要管理员权限）。
# 不会删除飞连本身；会移除 pkg 安装到 /Applications 的菜单栏 App。
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$@"
fi

LABEL="com.feiliancontrol.helper"
DEST="/Library/PrivilegedHelperTools/feilian-control"
OLD_DEST="/usr/local/libexec/feilian"
APP="/Applications/飞连控制.app"
mode="${1:---restore}"
if [[ "$mode" != "--restore" && "$mode" != "--keep-state" ]] || [[ "$#" -gt 1 ]]; then
  echo "用法：feilianctl uninstall [--keep-state]" >&2
  echo "默认先恢复飞连；--keep-state 会保留当前停用状态。" >&2
  exit 64
fi

if [[ "$mode" == "--restore" ]]; then
  echo "卸载前先恢复飞连，避免后台服务保持禁用状态。"
  start_script="$DEST/start.sh"
  if [[ ! -x "$start_script" && -x "$OLD_DEST/start.sh" ]]; then
    start_script="$OLD_DEST/start.sh"
  fi
  if [[ ! -x "$start_script" ]] || ! "$start_script"; then
    echo "飞连未能完整恢复，已中止卸载。请修复后重试。" >&2
    echo "如已确认要保留当前状态，可运行：feilianctl uninstall --keep-state" >&2
    exit 1
  fi
fi

# 先让 App 注销 SMAppService 登录项，再删除 bundle，避免遗留失效登录项。
app_executable="$APP/Contents/MacOS/FeiLianControl"
if [[ -x "$app_executable" ]]; then
  app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  # 0.2.0 尚无登录项功能，也不支持 --unregister-login-item。
  if [[ -n "$app_version" && "$app_version" != "0.2.0" ]]; then
    console_user="$(stat -f '%Su' /dev/console)"
    if ! console_uid="$(id -u "$console_user")" || [[ ! "$console_uid" =~ ^[0-9]+$ ]]; then
      echo "无法确定当前图形用户，不能安全注销登录项；已中止卸载。" >&2
      exit 1
    fi
    if ! launchctl asuser "$console_uid" "$app_executable" --unregister-login-item; then
      echo "无法注销菜单栏 App 的登录项；已中止卸载。请先在菜单中关闭“登录时自动启动”。" >&2
      exit 1
    fi
  fi
fi

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist"
rm -f "/var/run/$LABEL.sock"

rm -rf "$DEST" "$OLD_DEST"
rm -f /usr/local/bin/feilianctl
rm -f /usr/local/etc/feilian-control.conf
rm -f /var/log/feilian-control-helper.log
pkill -TERM -x FeiLianControl 2>/dev/null || true
rm -rf "/Applications/飞连控制.app"

echo "飞连控制已卸载；未删除飞连本身及其配置。"
if [[ "$mode" == "--keep-state" ]]; then
  echo "注意：已按要求保留飞连当前状态；如果它处于停用状态，请使用官方方式恢复。"
fi
echo "如需重新使用控制工具，请重新安装 Release 中的 pkg。"
