#!/bin/bash
# 查看飞连当前是否还在运行、launchd 任务是否被禁用。只读，不修改状态。
# --snapshot 为菜单栏 App 提供稳定的机器可读摘要，复用同一套检测逻辑。
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for dependency in service-common.sh auth-common.sh; do
  if ! source "$SCRIPT_DIR/$dependency"; then
    echo "无法加载共享逻辑：$SCRIPT_DIR/$dependency。请重新安装。" >&2
    exit 1
  fi
done

snapshot=false
if [[ "${1:-}" == "--snapshot" && "$#" -eq 1 ]]; then
  snapshot=true
elif (( $# > 0 )); then
  echo "用法：status.sh [--snapshot]" >&2
  exit 64
fi

LABEL="com.feiliancontrol.helper"
ui_running=false
background_running=false
helper_available=false

if /usr/bin/pgrep -x CorpLink >/dev/null 2>&1; then
  ui_running=true
fi
if feilian_background_processes_running; then
  background_running=true
fi
if helper_info="$(launchctl print "system/$LABEL" 2>/dev/null)" && \
   grep -q 'state = running' <<<"$helper_info" && \
   [[ -S "/var/run/$LABEL.sock" ]]; then
  helper_available=true
fi

config="$SCRIPT_DIR/auth.conf"
auth_mode=invalid
if [[ -r "$config" ]]; then
  mode="$(read_auth_mode "$config")"
  case "$mode" in
    none|touchid) auth_mode="$mode" ;;
  esac
fi

if [[ "$snapshot" == true ]]; then
  printf 'ui_running=%s\n' "$ui_running"
  printf 'background_running=%s\n' "$background_running"
  printf 'helper_available=%s\n' "$helper_available"
  printf 'auth_mode=%s\n' "$auth_mode"
  exit 0
fi

echo "== 状态摘要 =="
if [[ "$background_running" == true ]]; then
  echo "飞连后台：运行中"
else
  echo "飞连后台：未发现运行进程"
fi
if [[ "$ui_running" == true ]]; then
  echo "飞连界面：运行中"
else
  echo "飞连界面：未运行"
fi
if [[ "$background_running" == false && "$ui_running" == true ]]; then
  echo "提示：当前是“仅界面运行”状态，不等于全部后台已恢复。"
fi

echo
echo "== 飞连相关进程 =="
ps -axo pid,user,command | grep -iE 'CorpLink|corplink-service|CorplinkNe|CorpLinkExtension|clpolicy|corplink-mdm' | grep -v grep || echo "(无)"

echo
echo "== 用户级 launchd 任务（第一列是 PID，- 表示未运行）=="
launchctl list | grep -iE 'corplink|feilian' || echo "(无)"

echo
echo "== 系统级任务的启用状态 =="
launchctl print-disabled system 2>/dev/null | grep -iE 'corplink|com\.feiliancontrol\.helper' || echo "(无记录)"

echo
echo "== 飞连控制助手 =="
if [[ "$helper_available" == true ]]; then
  echo "运行中，socket 已创建（响应检查请运行 feilianctl doctor）"
else
  echo "未运行或 socket 不存在（请运行 feilianctl doctor 查看安装问题）"
fi

case "$auth_mode" in
  none) echo "验证方式：一键（不验证）" ;;
  touchid) echo "验证方式：Touch ID" ;;
  *)
    if [[ -r "$config" ]]; then
      echo "验证方式：配置无效（AUTH_MODE=${mode}）"
    else
      echo "验证方式：配置不存在或不可读（stop/start 将拒绝执行）"
    fi
    ;;
esac
