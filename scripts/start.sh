#!/bin/bash
# 恢复飞连的后台服务并打开客户端。
# 对应 stop.sh，把被禁用的 launchd 任务重新启用并加载。
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

echo "==> 恢复系统级守护进程"
for label in "${SYSTEM_LABELS[@]}"
do
  restore_service "system" "$label" "/Library/LaunchDaemons/$label.plist"
done

echo "==> 恢复用户级后台进程"
for label in "${USER_LABELS[@]}"
do
  if [[ "$label" == "CorpLink" ]]; then
    plist="$CONSOLE_HOME/Library/LaunchAgents/CorpLink.plist"
  else
    plist="/Library/LaunchAgents/$label.plist"
  fi
  restore_service "gui/$CONSOLE_UID" "$label" "$plist"
done

if (( matched_services == 0 )); then
  record_failure "未找到任何已知的飞连 launchd 服务；飞连版本可能不受支持"
fi

echo "==> 恢复 Finder 扩展"
set_finder_extension use

echo "==> 打开飞连客户端"
if console_command open -a "CorpLink"; then
  echo "    已请求打开 CorpLink"
else
  record_failure "无法打开 CorpLink，请确认飞连仍已安装"
fi

background_ready=false
for _ in {1..10}; do
  if feilian_background_processes_running; then
    background_ready=true
    break
  fi
  sleep 1
done
if [[ "$background_ready" != true ]]; then
  record_failure "恢复后仍未检测到飞连后台进程；服务可能启动失败或当前版本不受支持"
fi

echo
echo "==> 当前进程"
ps -axo pid,user,command | grep -iE 'CorpLink|corplink-service|CorplinkNe|CorpLinkExtension|clpolicy|corplink-mdm' | grep -v grep || echo "(未发现，可能还需要几秒)"

echo
if (( failures > 0 )); then
  echo "恢复未完成：$failures 项操作失败。请查看上方错误，或运行 feilianctl doctor。" >&2
  exit 1
fi

echo "恢复完成。若客户端尚未出现，请稍等几秒。"
