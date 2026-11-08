#!/bin/bash
# launchd / Finder 控制逻辑的 mock 测试；不会访问或修改真实服务。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/service-common.sh"

CONSOLE_UID=501
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

reset_case() {
  local name="$1"
  LOG="$TMP/$name.log"
  PLIST="$TMP/$name.plist"
  : >"$LOG"
  failures=0
  matched_services=0
  MOCK_LOADED=false
  MOCK_PRINT_STATUS=0
  MOCK_RUNNING=false
  MOCK_ENABLE_STATUS=0
  MOCK_KICKSTART_STATUS=0
  MOCK_BOOTSTRAP_STATUS=0
  MOCK_LOAD_STATUS=0
  MOCK_DISABLE_STATUS=0
  MOCK_BOOTOUT_STATUS=0
  MOCK_UNLOAD_STATUS=0
}

service_launchctl() {
  local domain="$1"
  shift
  local action="${1:-}"
  printf '%s %s\n' "$domain" "$*" >>"$LOG"
  case "$action" in
    print)
      if (( MOCK_PRINT_STATUS != 0 )); then
        echo "mock launchd query failure" >&2
        return "$MOCK_PRINT_STATUS"
      fi
      [[ "$MOCK_LOADED" == true ]] || return 113
      if [[ "$MOCK_RUNNING" == true ]]; then
        echo "state = running"
      else
        echo "state = not running"
      fi
      ;;
    enable) return "$MOCK_ENABLE_STATUS" ;;
    kickstart) return "$MOCK_KICKSTART_STATUS" ;;
    bootstrap) return "$MOCK_BOOTSTRAP_STATUS" ;;
    load) return "$MOCK_LOAD_STATUS" ;;
    disable) return "$MOCK_DISABLE_STATUS" ;;
    bootout) return "$MOCK_BOOTOUT_STATUS" ;;
    unload) return "$MOCK_UNLOAD_STATUS" ;;
    *) return 64 ;;
  esac
}

assert_logged() {
  local expected="$1"
  if ! grep -Fq "$expected" "$LOG"; then
    echo "FAIL: 日志中缺少 $expected" >&2
    cat "$LOG" >&2
    return 1
  fi
}

assert_not_logged() {
  local unexpected="$1"
  if grep -Fq "$unexpected" "$LOG"; then
    echo "FAIL: 日志中不应出现 $unexpected" >&2
    cat "$LOG" >&2
    return 1
  fi
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$actual" == "$expected" ]] || {
    echo "FAIL: ${message}（期望 ${expected}，实际 ${actual}）" >&2
    return 1
  }
}

test_restore_kickstarts_loaded_stopped_service() (
  reset_case "restore-stopped"
  touch "$PLIST"
  MOCK_LOADED=true
  restore_service system example "$PLIST" >/dev/null
  assert_logged "enable system/example"
  assert_logged "kickstart system/example"
  assert_not_logged "bootstrap"
  assert_equal 0 "$failures" "启动已加载服务不应失败"
  assert_equal 1 "$matched_services" "应记录匹配的服务"
)

test_restore_leaves_running_service_alone() (
  reset_case "restore-running"
  touch "$PLIST"
  MOCK_LOADED=true
  MOCK_RUNNING=true
  restore_service system example "$PLIST" >/dev/null
  assert_not_logged "kickstart"
  assert_not_logged "bootstrap"
  assert_equal 0 "$failures" "运行中的服务不应失败"
)

test_restore_bootstraps_unloaded_service() (
  reset_case "restore-unloaded"
  touch "$PLIST"
  restore_service system example "$PLIST" >/dev/null
  assert_logged "bootstrap system $PLIST"
  assert_equal 0 "$failures" "bootstrap 成功不应失败"
)

test_restore_reports_enable_and_load_failures() (
  reset_case "restore-failures"
  touch "$PLIST"
  MOCK_ENABLE_STATUS=1
  MOCK_BOOTSTRAP_STATUS=1
  MOCK_LOAD_STATUS=1
  restore_service system example "$PLIST" >/dev/null 2>&1
  assert_logged "load -w $PLIST"
  assert_equal 2 "$failures" "enable 和加载失败都应计数"
)

test_restore_skips_unknown_service() (
  reset_case "restore-missing"
  restore_service system example "$PLIST" >/dev/null
  assert_equal 0 "$failures" "未安装的可选服务应跳过"
  assert_equal 0 "$matched_services" "未安装服务不应计入匹配数"
  assert_logged "print system/example"
  assert_not_logged "enable"
  assert_not_logged "bootstrap"
)

test_stop_reports_disable_failure_even_if_bootout_succeeds() (
  reset_case "stop-disable-failure"
  touch "$PLIST"
  MOCK_LOADED=true
  MOCK_DISABLE_STATUS=1
  stop_service system example "$PLIST" >/dev/null 2>&1
  assert_logged "bootout system/example"
  assert_equal 1 "$failures" "禁用失败必须计数"
)

test_stop_reports_bootout_and_unload_failure() (
  reset_case "stop-failures"
  touch "$PLIST"
  MOCK_LOADED=true
  MOCK_BOOTOUT_STATUS=1
  MOCK_UNLOAD_STATUS=1
  stop_service system example "$PLIST" >/dev/null 2>&1
  assert_logged "unload -w $PLIST"
  assert_equal 1 "$failures" "停止失败必须计数"
)

test_stop_skips_unknown_service() (
  reset_case "stop-missing"
  stop_service system example "$PLIST" >/dev/null
  assert_equal 0 "$failures" "未安装服务应跳过"
  assert_logged "print system/example"
  assert_not_logged "disable"
  assert_not_logged "bootout"
)

test_stop_installed_but_unloaded_service_is_idempotent() (
  reset_case "stop-unloaded"
  touch "$PLIST"
  stop_service system example "$PLIST" >/dev/null
  assert_logged "disable system/example"
  assert_not_logged "bootout"
  assert_equal 0 "$failures" "已安装但未加载的服务不应导致停用失败"
)

test_stop_retries_bootout_after_transient_print_failure() (
  reset_case "stop-print-failure"
  touch "$PLIST"
  MOCK_LOADED=true
  MOCK_PRINT_STATUS=1
  stop_service system example "$PLIST" >/dev/null 2>&1
  assert_logged "disable system/example"
  assert_logged "bootout system/example"
  assert_equal 0 "$failures" "成功停止后不应仅因查询异常而失败"
)

test_stop_reports_failed_bootout_after_print_failure() (
  reset_case "stop-print-and-bootout-failure"
  touch "$PLIST"
  MOCK_LOADED=true
  MOCK_PRINT_STATUS=1
  MOCK_BOOTOUT_STATUS=1
  MOCK_UNLOAD_STATUS=1
  stop_service system example "$PLIST" >/dev/null 2>&1
  assert_logged "unload -w $PLIST"
  assert_equal 1 "$failures" "查询异常且停止失败必须计数"
)

test_finder_query_failure_is_not_absence() (
  reset_case "finder-query-failure"
  console_command() {
    echo "query unavailable" >&2
    return 1
  }
  set_finder_extension use >/dev/null 2>&1
  assert_equal 1 "$failures" "Finder 查询失败必须计数"
)

test_finder_extension_is_enabled_when_present() (
  reset_case "finder-present"
  console_command() {
    printf '%s\n' "$*" >>"$LOG"
    if [[ "${2:-}" == "-m" ]]; then
      echo "$FINDER_EXTENSION"
      return 0
    fi
    [[ "${2:-}" == "-e" ]]
  }
  set_finder_extension use >/dev/null
  assert_logged "-e use -i $FINDER_EXTENSION"
  assert_equal 0 "$failures" "Finder 恢复成功不应失败"
)

test_finder_absence_is_skipped() (
  reset_case "finder-absent"
  console_command() {
    printf '%s\n' "$*" >>"$LOG"
    [[ "${2:-}" == "-m" ]]
  }
  set_finder_extension ignore >/dev/null
  assert_equal 0 "$failures" "不存在的 Finder 扩展应跳过"
  assert_not_logged "-e"
)

test_finder_sync_pattern_respects_executable_boundaries() (
  [[ "CorpLink Finder Sync" =~ $FINDER_SYNC_PATTERN ]]
  [[ "/Applications/CorpLink.app/CorpLink Finder Sync --flag" =~ $FINDER_SYNC_PATTERN ]]
  [[ ! "/tmp/CorpLink Finder SyncHelper" =~ $FINDER_SYNC_PATTERN ]]
  [[ ! "/usr/bin/notes --file /tmp/CorpLinkFinderSync.txt" =~ $FINDER_SYNC_PATTERN ]]
)

tests=(
  test_restore_kickstarts_loaded_stopped_service
  test_restore_leaves_running_service_alone
  test_restore_bootstraps_unloaded_service
  test_restore_reports_enable_and_load_failures
  test_restore_skips_unknown_service
  test_stop_reports_disable_failure_even_if_bootout_succeeds
  test_stop_reports_bootout_and_unload_failure
  test_stop_skips_unknown_service
  test_stop_installed_but_unloaded_service_is_idempotent
  test_stop_retries_bootout_after_transient_print_failure
  test_stop_reports_failed_bootout_after_print_failure
  test_finder_query_failure_is_not_absence
  test_finder_extension_is_enabled_when_present
  test_finder_absence_is_skipped
  test_finder_sync_pattern_respects_executable_boundaries
)

for test_name in "${tests[@]}"; do
  "$test_name"
  echo "ok $test_name"
done

echo "Service control mock tests passed (${#tests[@]} cases)."
