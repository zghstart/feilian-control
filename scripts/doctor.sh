#!/bin/bash
# 只读诊断：检查飞连控制的安装、配置和 root 助手，不修改任何状态。
set -u

LABEL="com.feiliancontrol.helper"
DEST="/Library/PrivilegedHelperTools/feilian-control"
HELPER_PARENT="/Library/PrivilegedHelperTools"
OLD_DEST="/usr/local/libexec/feilian"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SOCKET="/var/run/$LABEL.sock"
CONFIG="/Library/PrivilegedHelperTools/feilian-control/auth.conf"
OLD_CONFIG="/usr/local/etc/feilian-control.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/auth-common.sh"; then
  echo "✗ 无法加载验证配置解析：$SCRIPT_DIR/auth-common.sh"
  exit 1
fi
failures=0
warnings=0

ok() {
  echo "✓ $1"
}

warn() {
  echo "! $1"
  warnings=$((warnings + 1))
}

fail() {
  echo "✗ $1"
  failures=$((failures + 1))
}

check_secure_permissions() {
  local path="$1"
  local owner
  local mode
  [[ -e "$path" || -L "$path" ]] || return
  if [[ -L "$path" ]]; then
    fail "安装文件不应是符号链接：$path"
    return
  fi
  owner="$(/usr/bin/stat -f '%Su' "$path")"
  mode="$(/usr/bin/stat -f '%Lp' "$path")"
  if [[ "$owner" != "root" ]]; then
    fail "安装文件必须由 root 所有：${path}（当前为 ${owner}）"
  elif (( (8#$mode & 022) != 0 )); then
    fail "安装文件不能被其他用户写入：${path}（权限 ${mode}）"
  else
    ok "权限安全：${path}（root，${mode}）"
  fi
}

check_executable() {
  local path="$1"
  local description="$2"
  if [[ -x "$path" ]]; then
    ok "${description}：$path"
    check_secure_permissions "$path"
  else
    fail "${description}缺失或不可执行：$path"
  fi
}

echo "== 飞连控制安装诊断 =="
check_secure_permissions "$HELPER_PARENT"
check_secure_permissions "$DEST"
if [[ -e "$OLD_DEST" || -L "$OLD_DEST" || -e "$OLD_CONFIG" || -L "$OLD_CONFIG" ]]; then
  fail "检测到旧版可写目录中的文件；请重新安装以完成迁移：$OLD_DEST / $OLD_CONFIG"
fi
check_executable "$DEST/feilian-daemon" "root 助手"
check_executable "$DEST/feilian-auth" "用户态客户端"
check_executable "/usr/local/bin/feilianctl" "命令行工具"

for script in auth-common.sh service-common.sh stop.sh start.sh status.sh doctor.sh uninstall-helper.sh; do
  check_executable "$DEST/$script" "控制脚本 $script"
done

if [[ -f "$PLIST" ]]; then
  ok "LaunchDaemon 配置：$PLIST"
  check_secure_permissions "$PLIST"
else
  fail "缺少 LaunchDaemon 配置：$PLIST"
fi

if [[ -r "$CONFIG" ]]; then
  check_secure_permissions "$CONFIG"
  mode="$(read_auth_mode "$CONFIG")"
  case "$mode" in
    none)
      ok "验证方式：一键（不验证）"
      ;;
    touchid)
      ok "验证方式：Touch ID"
      ;;
    "")
      fail "配置文件 $CONFIG 中没有有效的 AUTH_MODE（应为 none 或 touchid）"
      ;;
    *)
      fail "配置文件 $CONFIG 中的 AUTH_MODE=$mode 无效（应为 none 或 touchid）"
      ;;
  esac
else
  fail "配置文件不存在或不可读：$CONFIG"
fi

if helper_info="$(/bin/launchctl print "system/$LABEL" 2>&1)"; then
  if /usr/bin/grep -q 'state = running' <<<"$helper_info"; then
    ok "root 助手服务正在运行"
  else
    fail "root 助手服务已加载，但不处于 running 状态"
  fi
else
  fail "root 助手服务未加载：system/$LABEL"
fi

if [[ -S "$SOCKET" ]]; then
  ok "助手 socket 已创建：$SOCKET"
  if [[ -x "$DEST/feilian-auth" ]]; then
    if ping_response="$("$DEST/feilian-auth" ping 2>&1)" && \
       grep -q '^status=0' <<<"$ping_response"; then
      ok "助手连接与响应正常"
    else
      fail "助手 socket 未返回正常响应：${ping_response:-无返回内容}"
    fi
  fi
else
  fail "助手 socket 不存在：$SOCKET"
fi

if [[ -d "/Applications/飞连控制.app" || -d "${HOME:-}/Applications/飞连控制.app" ]]; then
  ok "菜单栏 App 已安装"
else
  warn "未发现菜单栏 App；源码安装可运行 make apps（不影响 CLI）"
fi

if [[ -d "/Applications/CorpLink.app" ]] || /usr/bin/pgrep -x CorpLink >/dev/null 2>&1; then
  ok "已发现飞连客户端"
else
  warn "未发现 /Applications/CorpLink.app；若飞连尚未安装或位于其他目录，可忽略此项"
fi

echo
if (( failures > 0 )); then
  echo "诊断结果：发现 $failures 个需要修复的问题，$warnings 个提醒。"
  echo "建议重新安装最新 pkg；源码用户可运行 make build && sudo make install。"
  echo "助手日志：/var/log/feilian-control-helper.log"
  exit 1
fi

echo "诊断结果：飞连控制安装正常（$warnings 个提醒）。"
echo "提示：此项只检查控制工具本身，不代表飞连已连接或企业网络可用。"
