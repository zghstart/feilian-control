#!/bin/bash
# Shell 工具共用的 AUTH_MODE 解析；只接受每行第一个 AUTH_MODE 的 none / touchid。
# 本文件不修改全局 shell 选项，也不写入配置。

read_auth_mode() {
  local config="$1"
  [[ -r "$config" ]] || return 1
  /usr/bin/awk '{line=$0; sub(/^[[:space:]]*/, "", line); if (line ~ /^AUTH_MODE=/) {sub(/^AUTH_MODE=/, "", line); gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); print line; exit}}' "$config"
}

resolve_install_auth_mode() {
  local config="$1"
  local old_config="$2"
  local current_mode=""
  local old_mode=""

  if [[ -f "$config" ]]; then
    current_mode="$(read_auth_mode "$config")" || current_mode=""
  fi
  if [[ -r "$old_config" ]]; then
    old_mode="$(read_auth_mode "$old_config")" || old_mode=""
  fi

  case "$current_mode" in
    none|touchid)
      printf '%s\n' "$current_mode"
      ;;
    *)
      case "$old_mode" in
        none|touchid)
          printf '%s\n' "$old_mode"
          ;;
        *)
          if [[ -e "$config" || -r "$old_config" ]]; then
            printf 'touchid\n'
          else
            printf 'none\n'
          fi
          ;;
      esac
      ;;
  esac
}
