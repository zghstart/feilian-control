#!/bin/bash
# 无副作用的回归测试：不调用 stop/start/stop-ui，不修改本机状态。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/scripts/feilianctl"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local text="$1"
  local expected="$2"
  [[ "$text" == *"$expected"* ]] || fail "输出中缺少：$expected"
}

help_output="$("$CLI" help)"
assert_contains "$help_output" "feilianctl stop"
assert_contains "$help_output" "feilianctl doctor"
assert_contains "$help_output" "feilianctl uninstall"
[[ "$help_output" == "$("$CLI" --help)" ]] || fail "--help 与 help 输出不一致"
[[ "$help_output" == "$("$CLI")" ]] || fail "无参数时应显示帮助"

expected_version="$(awk -F' := ' '/^VERSION :=/{print $2; exit}' "$ROOT/Makefile")"
[[ -n "$expected_version" ]] || fail "无法读取 Makefile 版本"
[[ "$("$CLI" version)" == "FeiLian Control $expected_version" ]] || fail "CLI 与 Makefile 版本不一致"
[[ "$("$CLI" --version)" == "FeiLian Control $expected_version" ]] || fail "--version 输出不一致"

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/app/Info.plist")"
[[ "$app_version" == "$expected_version" ]] || fail "App 与 Makefile 版本不一致"

if "$CLI" definitely-not-a-command >"$TMP/invalid.out" 2>&1; then
  fail "未知命令不应成功"
else
  exit_code=$?
  [[ "$exit_code" -eq 64 ]] || fail "未知命令退出码应为 64，实际为 $exit_code"
fi
assert_contains "$(<"$TMP/invalid.out")" "未知命令"

if "$CLI" status unexpected >"$TMP/extra.out" 2>&1; then
  fail "status 不应接受额外参数"
else
  exit_code=$?
  [[ "$exit_code" -eq 64 ]] || fail "额外参数退出码应为 64，实际为 $exit_code"
fi

# 只替换测试副本的配置路径，验证真实 CLI 的配置解析和失败行为。
TEST_CONFIG="$TMP/auth.conf"
TEST_LIBEXEC="$TMP/libexec"
TEST_CLI="$TMP/feilianctl"
mkdir -p "$TEST_LIBEXEC"
cp "$ROOT/scripts/auth-common.sh" "$TEST_LIBEXEC/auth-common.sh"
while IFS= read -r line; do
  if [[ "$line" == LIBEXEC=* ]]; then
    printf 'LIBEXEC=%q\n' "$TEST_LIBEXEC"
  elif [[ "$line" == CONFIG=* ]]; then
    printf 'CONFIG=%q\n' "$TEST_CONFIG"
  else
    printf '%s\n' "$line"
  fi
done <"$CLI" >"$TEST_CLI"

printf '  AUTH_MODE=none  \n' >"$TEST_CONFIG"
[[ "$(/bin/bash "$TEST_CLI" auth)" == "AUTH_MODE=none" ]] || fail "none 配置解析错误"
printf 'AUTH_MODE=touchid\n' >"$TEST_CONFIG"
[[ "$(/bin/bash "$TEST_CLI" auth)" == "AUTH_MODE=touchid" ]] || fail "touchid 配置解析错误"
printf 'AUTH_MODE=none\r\n' >"$TEST_CONFIG"
[[ "$(/bin/bash "$TEST_CLI" auth)" == "AUTH_MODE=none" ]] || fail "CRLF 配置解析错误"
for invalid_config in 'OTHER=value' 'AUTH_MODE=' 'AUTH_MODE=none=unexpected'; do
  printf '%s\n' "$invalid_config" >"$TEST_CONFIG"
  if /bin/bash "$TEST_CLI" auth >"$TMP/auth-invalid.out" 2>&1; then
    fail "无效配置不应被接受：$invalid_config"
  else
    exit_code=$?
    [[ "$exit_code" -eq 65 ]] || fail "非法配置退出码应为 65，实际为 $exit_code"
  fi
done

rm -f "$TEST_CONFIG"
if /bin/bash "$TEST_CLI" auth >"$TMP/auth-missing.out" 2>&1; then
  fail "配置缺失时不应静默回退为一键模式"
else
  exit_code=$?
  [[ "$exit_code" -eq 66 ]] || fail "配置缺失退出码应为 66，实际为 $exit_code"
fi

# 安装 / 重装配置选择：保留合法设置，修复损坏配置，并优先迁移合法旧配置。
source "$ROOT/scripts/auth-common.sh"
OLD_TEST_CONFIG="$TMP/old-auth.conf"
rm -f "$TEST_CONFIG" "$OLD_TEST_CONFIG"
[[ "$(resolve_install_auth_mode "$TEST_CONFIG" "$OLD_TEST_CONFIG")" == "none" ]] || fail "全新安装应默认为一键模式"
printf 'AUTH_MODE=touchid\n' >"$TEST_CONFIG"
[[ "$(resolve_install_auth_mode "$TEST_CONFIG" "$OLD_TEST_CONFIG")" == "touchid" ]] || fail "重装应保留 Touch ID"
printf 'AUTH_MODE=\n' >"$TEST_CONFIG"
[[ "$(resolve_install_auth_mode "$TEST_CONFIG" "$OLD_TEST_CONFIG")" == "touchid" ]] || fail "损坏配置应修复为 Touch ID"
printf 'AUTH_MODE=none\r\n' >"$OLD_TEST_CONFIG"
[[ "$(resolve_install_auth_mode "$TEST_CONFIG" "$OLD_TEST_CONFIG")" == "none" ]] || fail "损坏的新配置应迁移合法旧配置"
printf 'AUTH_MODE=touchid\n' >"$TEST_CONFIG"
[[ "$(resolve_install_auth_mode "$TEST_CONFIG" "$OLD_TEST_CONFIG")" == "touchid" ]] || fail "合法新配置应优先于旧配置"

# 菜单栏使用的机器可读状态必须始终包含完整字段；此操作仅查询状态。
snapshot_output="$(/bin/bash "$ROOT/scripts/status.sh" --snapshot)"
for key in ui_running background_running helper_available; do
  grep -Eq "^${key}=(true|false)$" <<<"$snapshot_output" || fail "状态快照缺少有效字段：$key"
done
grep -Eq '^auth_mode=(none|touchid|invalid)$' <<<"$snapshot_output" || fail "状态快照缺少有效验证方式"

# doctor 在未安装环境中应明确返回 1，但无论本机是否安装都不能出现 shell 运行时错误。
if doctor_output="$(/bin/bash "$ROOT/scripts/doctor.sh" 2>&1)"; then
  doctor_code=0
else
  doctor_code=$?
  [[ "$doctor_code" -eq 1 ]] || fail "doctor 退出码异常：$doctor_code"
fi
assert_contains "$doctor_output" "诊断结果"
[[ "$doctor_output" != *"unbound variable"* ]] || fail "doctor 出现未绑定变量"
[[ "$doctor_output" != *"command not found"* ]] || fail "doctor 出现命令缺失"

echo "CLI regression tests passed."
