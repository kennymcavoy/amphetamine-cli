#!/usr/bin/env bash

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI=$ROOT/bin/amphetamine
FIXTURE_BIN=$ROOT/tests/fixtures/bin
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/amphetamine-tests.XXXXXX")
AMPHETAMINE_TEST_LOG=$TEST_TMP/osascript.log
AMPHETAMINE_TEST_EFFECT_LOG=$TEST_TMP/effects.log
AMPHETAMINE_APP_PATH=$TEST_TMP/Amphetamine.app
STDERR_FILE=$TEST_TMP/stderr
PATH=$FIXTURE_BIN:/usr/bin:/bin

export AMPHETAMINE_TEST_LOG AMPHETAMINE_TEST_EFFECT_LOG AMPHETAMINE_APP_PATH PATH

passed=0
failed=0
RUN_OUTPUT=
RUN_STATUS=0

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$AMPHETAMINE_APP_PATH"

record_pass() {
  passed=$((passed + 1))
  printf 'ok %d - %s\n' "$passed" "$1"
}

record_fail() {
  failed=$((failed + 1))
  printf 'not ok - %s\n' "$1" >&2
}

assert_eq() {
  local expected=$1 actual=$2 message=$3
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  printf '  expected: %s\n  actual:   %s\n' "$expected" "$actual" >&2
  record_fail "$message"
  return 1
}

assert_contains() {
  local haystack=$1 needle=$2 message=$3
  case "$haystack" in
    *"$needle"*) return 0 ;;
    *)
      printf '  missing: %s\n' "$needle" >&2
      record_fail "$message"
      return 1
      ;;
  esac
}

assert_not_contains() {
  local haystack=$1 needle=$2 message=$3
  case "$haystack" in
    *"$needle"*)
      printf '  unexpected: %s\n' "$needle" >&2
      record_fail "$message"
      return 1
      ;;
    *) return 0 ;;
  esac
}

reset_fakes() {
  : > "$AMPHETAMINE_TEST_LOG"
  : > "$AMPHETAMINE_TEST_EFFECT_LOG"
  : > "$STDERR_FILE"
  AMPHETAMINE_APP_PATH=$TEST_TMP/Amphetamine.app
  FAKE_ACTIVE=true
  FAKE_STATUS='true\t9000\ttrue\ttrue\tfalse'
  FAKE_DISPLAY_PREF=1
  FAKE_DEFAULTS_FAIL=false
  FAKE_OSASCRIPT_FAIL_MATCH=
  FAKE_DISPLAY_ACTIVE=true
  FAKE_EXPIRE_BEFORE_DISPLAY_ACTION=false
  export AMPHETAMINE_APP_PATH FAKE_ACTIVE FAKE_STATUS FAKE_DISPLAY_PREF FAKE_DEFAULTS_FAIL
  export FAKE_OSASCRIPT_FAIL_MATCH
  export FAKE_DISPLAY_ACTIVE FAKE_EXPIRE_BEFORE_DISPLAY_ACTION
}

run_cli() {
  RUN_OUTPUT=$(/bin/bash "$CLI" "$@" 2>"$STDERR_FILE")
  RUN_STATUS=$?
}

log_contents() {
  LOG_CONTENTS=$(<"$AMPHETAMINE_TEST_LOG")
}

effect_contents() {
  EFFECT_CONTENTS=$(<"$AMPHETAMINE_TEST_EFFECT_LOG")
}

test_version_without_app() {
  reset_fakes
  AMPHETAMINE_APP_PATH=$TEST_TMP/Missing.app
  export AMPHETAMINE_APP_PATH
  run_cli version
  log_contents
  assert_eq 0 "$RUN_STATUS" 'version exits successfully without Amphetamine installed' || return
  assert_eq 'amphetamine 1.0.0' "$RUN_OUTPUT" 'version prints the release identifier' || return
  assert_eq '' "$LOG_CONTENTS" 'version does not invoke system tools' || return
  record_pass 'version reports release 1.0.0 without requiring Amphetamine'
}

test_start_duration() {
  reset_fakes
  FAKE_DISPLAY_PREF=0
  export FAKE_DISPLAY_PREF
  run_cli start 2h
  log_contents
  assert_eq 0 "$RUN_STATUS" 'start 2h exits successfully' || return
  assert_contains "$LOG_CONTENTS" 'start new session with options' 'start 2h uses options' || return
  assert_contains "$LOG_CONTENTS" 'duration:2' 'start 2h uses duration 2' || return
  assert_contains "$LOG_CONTENTS" 'interval:hours' 'start 2h uses hours' || return
  assert_contains "$LOG_CONTENTS" 'displaySleepAllowed:false' 'start 2h uses the preference' || return
  record_pass 'start 2h sends complete options with preference display state'
}

test_bare_start() {
  reset_fakes
  run_cli start
  log_contents
  assert_eq 0 "$RUN_STATUS" 'bare start exits successfully' || return
  assert_contains "$LOG_CONTENTS" 'to start new session' 'bare start starts a session' || return
  assert_not_contains "$LOG_CONTENTS" 'with options' 'bare start omits options' || return
  assert_not_contains "$LOG_CONTENTS" 'defaults read' 'bare start does not read preferences' || return
  record_pass 'bare start uses Amphetamine Preferences without an options record'
}

test_indefinite() {
  reset_fakes
  run_cli start --indefinite
  log_contents
  assert_eq 0 "$RUN_STATUS" 'indefinite start exits successfully' || return
  assert_contains "$LOG_CONTENTS" 'duration:0' 'indefinite start uses duration zero' || return
  assert_contains "$LOG_CONTENTS" 'interval:0' 'indefinite start uses interval zero' || return
  record_pass 'indefinite start uses the documented zero values'
}

test_stop() {
  reset_fakes
  FAKE_STATUS='false\t-3\ttrue\ttrue\tfalse'
  export FAKE_STATUS
  run_cli stop
  log_contents
  assert_eq 0 "$RUN_STATUS" 'stop exits successfully' || return
  assert_contains "$LOG_CONTENTS" 'to end session' 'stop ends the session' || return
  assert_eq 'session:     inactive' "$RUN_OUTPUT" 'stop prints inactive status' || return
  record_pass 'stop ends the session and reports inactive'
}

test_display_active() {
  reset_fakes
  run_cli display sleep
  effect_contents
  assert_eq 0 "$RUN_STATUS" 'display sleep exits successfully' || return
  assert_eq 'allow display sleep' "$EFFECT_CONTENTS" 'display sleep changes the active session' || return

  reset_fakes
  run_cli display no-sleep
  effect_contents
  assert_eq 0 "$RUN_STATUS" 'display no-sleep exits successfully' || return
  assert_eq 'prevent display sleep' "$EFFECT_CONTENTS" 'display no-sleep changes the active session' || return
  record_pass 'display modes mutate only an active session'
}

test_display_inactive() {
  reset_fakes
  FAKE_ACTIVE=false
  FAKE_DISPLAY_ACTIVE=false
  export FAKE_ACTIVE FAKE_DISPLAY_ACTIVE
  run_cli display sleep
  effect_contents
  assert_eq 2 "$RUN_STATUS" 'inactive display exits 2' || return
  assert_eq '' "$EFFECT_CONTENTS" 'inactive display does not change preferences' || return
  record_pass 'display refuses an inactive session without changing Preferences'
}

test_display_session_expiry() {
  reset_fakes
  FAKE_ACTIVE=true
  FAKE_DISPLAY_ACTIVE=false
  FAKE_EXPIRE_BEFORE_DISPLAY_ACTION=true
  FAKE_STATUS='false\t-3\ttrue\ttrue\tfalse'
  export FAKE_ACTIVE FAKE_DISPLAY_ACTIVE FAKE_EXPIRE_BEFORE_DISPLAY_ACTION FAKE_STATUS
  run_cli display no-sleep
  effect_contents
  assert_eq 2 "$RUN_STATUS" 'expired display session exits 2' || return
  assert_eq '' "$EFFECT_CONTENTS" 'expired display session does not change global preferences' || return
  record_pass 'display handles session expiry without changing Preferences'
}

test_duration_parser() {
  reset_fakes
  run_cli start 2h30m
  log_contents
  assert_eq 0 "$RUN_STATUS" 'combined duration exits successfully' || return
  assert_contains "$LOG_CONTENTS" 'duration:150' 'combined duration becomes 150' || return
  assert_contains "$LOG_CONTENTS" 'interval:minutes' 'combined duration uses minutes' || return

  reset_fakes
  run_cli start 2H30M
  log_contents
  assert_eq 0 "$RUN_STATUS" 'uppercase combined duration exits successfully' || return
  assert_contains "$LOG_CONTENTS" 'duration:150' 'uppercase combined duration becomes 150' || return

  reset_fakes
  run_cli start 90
  assert_eq 2 "$RUN_STATUS" 'bare duration exits 2' || return
  log_contents
  assert_eq '' "$LOG_CONTENTS" 'bare duration does not invoke tools' || return

  reset_fakes
  run_cli start 0h
  assert_eq 2 "$RUN_STATUS" 'zero hours exits 2' || return
  log_contents
  assert_eq '' "$LOG_CONTENTS" 'zero hours does not invoke tools' || return

  reset_fakes
  run_cli start 2h --indefinite
  assert_eq 2 "$RUN_STATUS" 'conflicting durations exit 2' || return
  log_contents
  assert_eq '' "$LOG_CONTENTS" 'conflicting durations do not invoke tools' || return
  record_pass 'duration parser accepts case-insensitive forms and rejects invalid combinations'
}

test_json() {
  reset_fakes
  run_cli status --json
  assert_eq 0 "$RUN_STATUS" 'JSON status exits successfully' || return
  assert_eq '' "$(<"$STDERR_FILE")" 'JSON status keeps stderr empty' || return
  if ! printf '%s' "$RUN_OUTPUT" | python3 -c '
import json, sys
value = json.load(sys.stdin)
assert list(value) == ["active", "remaining_seconds", "display_sleep_allowed", "lid_close_keep_awake", "trigger"]
assert value == {
    "active": True,
    "remaining_seconds": 9000,
    "display_sleep_allowed": True,
    "lid_close_keep_awake": True,
    "trigger": False,
}
'; then
    record_fail 'JSON output parses with the documented schema'
    return
  fi
  record_pass 'JSON output parses with the documented schema'
}

test_failure_has_no_success_status() {
  reset_fakes
  FAKE_OSASCRIPT_FAIL_MATCH='start new session'
  export FAKE_OSASCRIPT_FAIL_MATCH
  run_cli start
  assert_eq 1 "$RUN_STATUS" 'AppleScript failure exits 1' || return
  assert_eq '' "$RUN_OUTPUT" 'AppleScript failure has no stdout status' || return
  assert_not_contains "$(<"$STDERR_FILE")" 'session:' 'AppleScript failure has no success-like status' || return
  record_pass 'AppleScript failures do not print a success-like status block'
}

test_missing_app_failure() {
  reset_fakes
  AMPHETAMINE_APP_PATH=$TEST_TMP/Missing.app
  export AMPHETAMINE_APP_PATH
  run_cli status
  log_contents
  assert_eq 1 "$RUN_STATUS" 'missing app exits 1' || return
  assert_eq '' "$RUN_OUTPUT" 'missing app has no stdout status' || return
  assert_eq '' "$LOG_CONTENTS" 'missing app does not invoke system tools' || return
  record_pass 'missing app fails without success-like output'
}

test_defaults_failure() {
  reset_fakes
  FAKE_DEFAULTS_FAIL=true
  export FAKE_DEFAULTS_FAIL
  run_cli start 2h
  log_contents
  assert_eq 1 "$RUN_STATUS" 'defaults failure exits 1' || return
  assert_eq '' "$RUN_OUTPUT" 'defaults failure has no stdout status' || return
  assert_not_contains "$LOG_CONTENTS" 'start new session' 'defaults failure does not start a session' || return
  record_pass 'preference-read failure prevents session creation'
}

test_malformed_status_failure() {
  reset_fakes
  FAKE_STATUS='malformed status'
  export FAKE_STATUS
  run_cli status
  assert_eq 1 "$RUN_STATUS" 'malformed status exits 1' || return
  assert_eq '' "$RUN_OUTPUT" 'malformed status has no stdout status' || return
  record_pass 'malformed AppleScript status fails closed'
}

json_matches_status() {
  local value=$1 expected_active=$2 expected_remaining=$3
  printf '%s' "$value" | python3 -c '
import json, sys
value = json.load(sys.stdin)
assert list(value) == ["active", "remaining_seconds", "display_sleep_allowed", "lid_close_keep_awake", "trigger"]
assert value["active"] is (sys.argv[1] == "true")
assert value["remaining_seconds"] == int(sys.argv[2])
assert isinstance(value["display_sleep_allowed"], bool)
assert isinstance(value["lid_close_keep_awake"], bool)
assert isinstance(value["trigger"], bool)
' "$expected_active" "$expected_remaining"
}

test_mutating_json_contract() {
  reset_fakes
  run_cli start 2h --json
  assert_eq 0 "$RUN_STATUS" 'JSON start exits successfully' || return
  json_matches_status "$RUN_OUTPUT" true 9000 || { record_fail 'start returns the JSON status contract'; return; }

  reset_fakes
  FAKE_STATUS='false\t-3\ttrue\ttrue\tfalse'
  export FAKE_STATUS
  run_cli stop --json
  assert_eq 0 "$RUN_STATUS" 'JSON stop exits successfully' || return
  json_matches_status "$RUN_OUTPUT" false -3 || { record_fail 'stop returns the JSON status contract'; return; }

  reset_fakes
  run_cli display sleep --json
  assert_eq 0 "$RUN_STATUS" 'JSON display exits successfully' || return
  json_matches_status "$RUN_OUTPUT" true 9000 || { record_fail 'display returns the JSON status contract'; return; }
  record_pass 'all mutating commands return the JSON status contract'
}

test_install_and_uninstall() {
  reset_fakes
  if ! make -s -C "$ROOT" install PREFIX="$TEST_TMP/install"; then
    record_fail 'make install completes'
    return
  fi
  if [ -L "$TEST_TMP/install/bin/amphetamine" ] || [ ! -x "$TEST_TMP/install/bin/amphetamine" ]; then
    record_fail 'make install creates an executable copy'
    return
  fi
  if ! cmp -s "$CLI" "$TEST_TMP/install/bin/amphetamine"; then
    record_fail 'make install preserves the binary contents'
    return
  fi
  printf 'keep\n' > "$TEST_TMP/install/bin/keep-me"
  if ! make -s -C "$ROOT" uninstall PREFIX="$TEST_TMP/install"; then
    record_fail 'make uninstall completes'
    return
  fi
  if [ -e "$TEST_TMP/install/bin/amphetamine" ]; then
    record_fail 'make uninstall removes the installed binary'
    return
  fi
  if [ ! -f "$TEST_TMP/install/bin/keep-me" ]; then
    record_fail 'make uninstall preserves neighboring files'
    return
  fi
  record_pass 'install copies the binary and uninstall removes only that binary'
}

test_version_without_app
test_start_duration
test_bare_start
test_indefinite
test_stop
test_display_active
test_display_inactive
test_display_session_expiry
test_duration_parser
test_json
test_failure_has_no_success_status
test_missing_app_failure
test_defaults_failure
test_malformed_status_failure
test_mutating_json_contract
test_install_and_uninstall

if [ "$failed" -ne 0 ]; then
  printf '%d test(s) failed; %d passed\n' "$failed" "$passed" >&2
  exit 1
fi

printf '1..%d\n' "$passed"
