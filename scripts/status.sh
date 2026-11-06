#!/bin/bash
# 查看飞连当前是否还在运行、launchd 任务是否被禁用。
set -u

echo "== 飞连相关进程 =="
ps -axo pid,user,command | grep -iE 'CorpLink|corplink-service|CorplinkNe|CorpLinkExtension|clpolicy' | grep -v grep || echo "(无)"

echo
echo "== 用户级 launchd 任务（第一列是 PID，- 表示未运行）=="
launchctl list | grep -iE 'corplink|feilian' || echo "(无)"

echo
echo "== 系统级任务的启用状态 =="
launchctl print-disabled system 2>/dev/null | grep -iE 'corplink|com\.feiliancontrol\.helper' || echo "(无记录)"

echo
echo "== 飞连控制助手 =="
if launchctl print system/com.feiliancontrol.helper >/dev/null 2>&1; then
  echo "运行中"
  config="/usr/local/etc/feilian-control.conf"
  if [[ -r "$config" ]]; then
    mode="$(/usr/bin/awk -F= '/^AUTH_MODE=/{print $2; exit}' "$config")"
    echo "验证方式：${mode:-touchid}"
  fi
else
  echo "未运行（安装：sudo make install 或重新安装 pkg）"
fi
