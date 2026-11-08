#!/bin/bash
# start.sh / stop.sh 共用的 launchd 与 Finder 扩展操作。
# 本文件不自行切换权限或修改全局 shell 选项，便于独立做 mock 测试。

FINDER_EXTENSION="com.volcengine.corplink.networkextension-wrapper.FinderSync"
# macOS 的 -x 不支持超过 19 字符的进程名；用完整命令行中的可执行文件边界匹配。
FINDER_SYNC_PATTERN='(^|/)CorpLink Finder Sync([[:space:]]|$)'
SYSTEM_LABELS=(
  com.corplink.mdm.policy
  com.volcengine.corplink.systemextension
  com.volcengine.corplink.service
)
USER_LABELS=(
  com.volcengine.corplink.agent
  CorpLink
)
failures=0
matched_services=0

record_failure() {
  echo "    错误：$1" >&2
  failures=$((failures + 1))
}

console_command() {
  launchctl asuser "$CONSOLE_UID" "$@"
}

service_launchctl() {
  local domain="$1"
  shift
  if [[ "$domain" == "system" ]]; then
    launchctl "$@"
  else
    console_command launchctl "$@"
  fi
}

restore_service() {
  local domain="$1"
  local label="$2"
  local plist="$3"
  local target="$domain/$label"
  local service_info

  if [[ ! -f "$plist" ]] && ! service_launchctl "$domain" print "$target" >/dev/null 2>&1; then
    echo "    ${label}（未安装，跳过）"
    return
  fi

  matched_services=$((matched_services + 1))
  echo "    $label"
  if ! service_launchctl "$domain" enable "$target"; then
    record_failure "无法启用 $target"
  fi

  if service_info="$(service_launchctl "$domain" print "$target" 2>/dev/null)"; then
    if grep -q 'state = running' <<<"$service_info"; then
      echo "      已运行"
    elif service_launchctl "$domain" kickstart "$target"; then
      echo "      已启动已加载的服务"
    else
      record_failure "服务已加载但无法启动 $target"
    fi
    return
  fi

  if ! service_launchctl "$domain" bootstrap "$domain" "$plist" && \
     ! service_launchctl "$domain" load -w "$plist"; then
    record_failure "无法加载 ${target}（plist：${plist}）"
  fi
}

stop_service() {
  local domain="$1"
  local label="$2"
  local plist="$3"
  local target="$domain/$label"
  local loaded=false
  local service_info
  local print_status=0

  if service_info="$(service_launchctl "$domain" print "$target" 2>&1)"; then
    loaded=true
  else
    print_status=$?
    if [[ ! -f "$plist" ]]; then
      echo "    ${label}（未安装，跳过）"
      return
    elif (( print_status != 113 )) && ! grep -q 'Could not find service' <<<"$service_info"; then
      # 查询异常不等于未加载：仍尝试停止，避免 KeepAlive 服务被遗留。
      echo "    警告：无法确认 $target 的加载状态，仍将尝试停止" >&2
      loaded=true
    fi
  fi

  echo "    $label"
  if ! service_launchctl "$domain" disable "$target"; then
    record_failure "无法禁用 ${target}；重新启动后它可能自动恢复"
  fi

  if [[ "$loaded" == true ]]; then
    if ! service_launchctl "$domain" bootout "$target" && \
       ! service_launchctl "$domain" unload -w "$plist"; then
      record_failure "无法停止 $target"
    fi
  fi
}

set_finder_extension() {
  local action="$1"
  local action_text="恢复"
  local extension_info
  local extension_status
  if [[ "$action" == "ignore" ]]; then
    action_text="禁用"
  fi

  if extension_info="$(console_command pluginkit -m -i "$FINDER_EXTENSION" 2>&1)"; then
    extension_status=0
  else
    extension_status=$?
  fi
  if (( extension_status != 0 )); then
    [[ -z "$extension_info" ]] || echo "    $extension_info" >&2
    record_failure "无法查询 Finder 扩展 $FINDER_EXTENSION"
  elif grep -q "$FINDER_EXTENSION" <<<"$extension_info"; then
    if ! console_command pluginkit -e "$action" -i "$FINDER_EXTENSION"; then
      record_failure "无法${action_text} Finder 扩展 $FINDER_EXTENSION"
    else
      echo "    $FINDER_EXTENSION"
    fi
  else
    echo "    未检测到 Finder 扩展，跳过"
  fi
}

feilian_background_processes_running() {
  local name
  for name in CorpLinkExtension corplink-service CorplinkNe clpolicy; do
    if /usr/bin/pgrep -x "$name" >/dev/null 2>&1; then
      return 0
    fi
  done
  if /usr/bin/pgrep -f "$FINDER_SYNC_PATTERN" >/dev/null 2>&1; then
    return 0
  fi
  /usr/bin/pgrep -f '/corplink-mdm/policy/bin/ruby' >/dev/null 2>&1
}

feilian_processes_running() {
  /usr/bin/pgrep -x CorpLink >/dev/null 2>&1 || feilian_background_processes_running
}
