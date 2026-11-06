#!/bin/bash
# 停止飞连（CorpLink）界面及全部后台服务，并禁止它们自动恢复。
# 恢复请点击菜单栏“飞连控制”图标，或运行 feilianctl start。
# 只操作飞连自己的 launchd 任务和进程路径，不触碰其他软件。
set -u

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

CONSOLE_USER="$(stat -f '%Su' /dev/console)"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" || "$CONSOLE_USER" == "loginwindow" ]]; then
  echo "未找到当前登录的图形用户，无法定位用户级服务。" >&2
  exit 1
fi
CONSOLE_UID="$(id -u "$CONSOLE_USER")"
CONSOLE_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')"

echo "==> 退出飞连界面"
pkill -TERM -x CorpLink 2>/dev/null || true
sleep 1

echo "==> 禁用 Finder 扩展"
launchctl asuser "$CONSOLE_UID" pluginkit -e ignore -i com.volcengine.corplink.networkextension-wrapper.FinderSync 2>/dev/null || true
pkill -TERM -f 'CorpLink Finder Sync' 2>/dev/null || true

echo "==> 停止并禁用系统级守护进程"
for label in \
  com.corplink.mdm.policy \
  com.volcengine.corplink.systemextension \
  com.volcengine.corplink.service
do
  launchctl disable "system/$label" 2>/dev/null || true
  launchctl bootout "system/$label" 2>/dev/null || true
  launchctl unload -w "/Library/LaunchDaemons/$label.plist" 2>/dev/null || true
  echo "    $label"
done

echo "==> 停止并禁用用户级后台进程"
for label in \
  com.volcengine.corplink.agent \
  CorpLink
do
  if [[ "$label" == "CorpLink" ]]; then
    plist="$CONSOLE_HOME/Library/LaunchAgents/CorpLink.plist"
  else
    plist="/Library/LaunchAgents/$label.plist"
  fi
  launchctl asuser "$CONSOLE_UID" launchctl disable "gui/$CONSOLE_UID/$label" 2>/dev/null || true
  launchctl asuser "$CONSOLE_UID" launchctl bootout "gui/$CONSOLE_UID/$label" 2>/dev/null || true
  launchctl asuser "$CONSOLE_UID" launchctl unload -w "$plist" 2>/dev/null || true
  echo "    $label"
done

sleep 1

echo "==> 清理残留进程"
for name in CorpLinkExtension corplink-service CorplinkNe clpolicy; do
  pkill -TERM -x "$name" 2>/dev/null || true
done
pkill -TERM -x 'CorpLink Finder Sync' 2>/dev/null || true
sleep 1
for name in CorpLinkExtension corplink-service CorplinkNe clpolicy CorpLink; do
  pkill -KILL -x "$name" 2>/dev/null || true
done
pkill -KILL -x 'CorpLink Finder Sync' 2>/dev/null || true

echo
echo "==> 检查结果"
if ps -axo pid,user,command | grep -iE 'CorpLink|corplink-service|CorplinkNe|CorpLinkExtension|clpolicy' | grep -v grep; then
  echo "上面仍有残留进程。" >&2
  exit 2
else
  echo "已停止：没有发现飞连相关进程。"
fi
echo
echo "恢复方法：点击菜单栏“飞连控制”图标 → 恢复飞连，或运行 feilianctl start"
echo "（也可以运行 sudo /usr/local/libexec/feilian/start.sh）"
