#!/bin/bash
# 停止飞连（CorpLink）界面及全部后台服务，并禁止它们自动恢复。
# 恢复请点击菜单栏“飞连控制”图标，或运行 feilianctl start。
# 只操作飞连自己的 launchd 任务和精确进程名，不触碰其他软件。
set -u
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/service-common.sh"; then
  echo "无法加载共享控制逻辑：$SCRIPT_DIR/service-common.sh。请重新安装。" >&2
  exit 1
fi

CONSOLE_USER="$(stat -f '%Su' /dev/console)"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" || "$CONSOLE_USER" == "loginwindow" ]]; then
  echo "未找到当前登录的图形用户，请登录桌面后再试。" >&2
  exit 1
fi
if ! CONSOLE_UID="$(id -u "$CONSOLE_USER")" || [[ ! "$CONSOLE_UID" =~ ^[0-9]+$ ]]; then
  echo "无法确定用户 $CONSOLE_USER 的 UID，未修改任何服务。" >&2
  exit 1
fi
CONSOLE_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | sed -n 's/^NFSHomeDirectory:[[:space:]]*//p')"
if [[ -z "$CONSOLE_HOME" ]]; then
  echo "无法确定用户 $CONSOLE_USER 的主目录。" >&2
  exit 1
fi

echo "==> 退出飞连界面"
pkill -TERM -x CorpLink 2>/dev/null || true
sleep 1

echo "==> 禁用 Finder 扩展"
set_finder_extension ignore
pkill -TERM -f "$FINDER_SYNC_PATTERN" 2>/dev/null || true

echo "==> 停止并禁用系统级守护进程"
for label in "${SYSTEM_LABELS[@]}"
do
  stop_service "system" "$label" "/Library/LaunchDaemons/$label.plist"
done

echo "==> 停止并禁用用户级后台进程"
for label in "${USER_LABELS[@]}"
do
  if [[ "$label" == "CorpLink" ]]; then
    plist="$CONSOLE_HOME/Library/LaunchAgents/CorpLink.plist"
  else
    plist="/Library/LaunchAgents/$label.plist"
  fi
  stop_service "gui/$CONSOLE_UID" "$label" "$plist"
done

sleep 1

echo "==> 清理残留进程"
for name in CorpLinkExtension corplink-service CorplinkNe clpolicy; do
  pkill -TERM -x "$name" 2>/dev/null || true
done
pkill -TERM -f "$FINDER_SYNC_PATTERN" 2>/dev/null || true
sleep 1
for name in CorpLinkExtension corplink-service CorplinkNe clpolicy CorpLink; do
  pkill -KILL -x "$name" 2>/dev/null || true
done
pkill -KILL -f "$FINDER_SYNC_PATTERN" 2>/dev/null || true

echo
echo "==> 检查结果"
if feilian_processes_running; then
  ps -axo pid,user,command | grep -iE 'CorpLink|corplink-service|CorplinkNe|CorpLinkExtension|clpolicy|corplink-mdm' | grep -v grep || true
  echo "上面仍有残留进程，停用未完成。" >&2
  exit 2
fi

if (( failures > 0 )); then
  echo "进程已停止，但 $failures 项禁用操作失败；重启后部分组件可能自动恢复。" >&2
  exit 1
fi

echo "已停止：没有发现飞连相关进程，已检测到的 launchd 任务也已禁用。"
echo
echo "恢复方法：点击菜单栏“飞连控制”图标 → 恢复飞连，或运行 feilianctl start"
echo "（也可以运行 sudo /Library/PrivilegedHelperTools/feilian-control/start.sh）"
