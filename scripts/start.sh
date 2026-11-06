#!/bin/bash
# 恢复飞连的后台服务并打开客户端。
# 对应 stop.sh，把被禁用的 launchd 任务重新启用并加载。
set -u

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

CONSOLE_USER="$(stat -f '%Su' /dev/console)"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" || "$CONSOLE_USER" == "loginwindow" ]]; then
  echo "未找到当前登录的图形用户。" >&2
  exit 1
fi
CONSOLE_UID="$(id -u "$CONSOLE_USER")"
CONSOLE_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')"

echo "==> 恢复系统级守护进程"
for label in \
  com.corplink.mdm.policy \
  com.volcengine.corplink.systemextension \
  com.volcengine.corplink.service
do
  plist="/Library/LaunchDaemons/$label.plist"
  launchctl enable "system/$label" 2>/dev/null || true
  launchctl bootstrap "system" "$plist" 2>/dev/null || launchctl load -w "$plist" 2>/dev/null || true
  echo "    $label"
done

echo "==> 恢复用户级后台进程"
for label in \
  com.volcengine.corplink.agent \
  CorpLink
do
  if [[ "$label" == "CorpLink" ]]; then
    plist="$CONSOLE_HOME/Library/LaunchAgents/CorpLink.plist"
  else
    plist="/Library/LaunchAgents/$label.plist"
  fi
  launchctl asuser "$CONSOLE_UID" launchctl enable "gui/$CONSOLE_UID/$label" 2>/dev/null || true
  launchctl asuser "$CONSOLE_UID" launchctl bootstrap "gui/$CONSOLE_UID" "$plist" 2>/dev/null || \
    launchctl asuser "$CONSOLE_UID" launchctl load -w "$plist" 2>/dev/null || true
  echo "    $label"
done

echo "==> 恢复 Finder 扩展"
launchctl asuser "$CONSOLE_UID" pluginkit -e use -i com.volcengine.corplink.networkextension-wrapper.FinderSync 2>/dev/null || true

sleep 1
echo "==> 打开飞连客户端"
launchctl asuser "$CONSOLE_UID" open -a "CorpLink" 2>/dev/null || true

echo
echo "==> 当前进程"
ps -axo pid,user,command | grep -iE 'CorpLink|corplink-service|CorplinkNe|CorpLinkExtension|clpolicy' | grep -v grep || echo "(未发现，可能还需要几秒)"

echo "完成。"
