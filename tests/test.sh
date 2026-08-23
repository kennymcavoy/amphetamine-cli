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

test_guided_install_and_uninstall() {
  reset_fakes
  local portable_home=$TEST_TMP/guided-home
  local installed_binary=$portable_home/.local/bin/amphetamine
  local skill_store=$portable_home/.local/share/amphetamine-cli/skills/amphetamine
  local codex_link=$portable_home/.agents/skills/amphetamine
  local claude_link=$portable_home/.claude/skills/amphetamine
  local answers=$TEST_TMP/guided-answers
  local install_output install_status

  printf 'yes\nyes\n' > "$answers"
  install_output=$(make -s -C "$ROOT" install HOME="$portable_home" < "$answers" 2>&1)
  install_status=$?
  if [ "$install_status" -ne 0 ]; then
    printf '%s\n' "$install_output" >&2
    record_fail 'guided make install completes'
    return
  fi
  assert_contains "$install_output" 'Enable the Amphetamine skill for Codex?' 'installer asks about Codex' || return
  assert_contains "$install_output" 'Enable the Amphetamine skill for Claude Code?' 'installer asks about Claude Code' || return
  if [ -L "$installed_binary" ] || [ ! -x "$installed_binary" ]; then
    record_fail 'make install creates an executable copy'
    return
  fi
  if ! cmp -s "$CLI" "$installed_binary"; then
    record_fail 'make install preserves the binary contents'
    return
  fi
  if [ -L "$skill_store" ] || ! cmp -s "$ROOT/skill/SKILL.md" "$skill_store/SKILL.md"; then
    record_fail 'make install creates one self-contained canonical skill copy'
    return
  fi
  if [ ! -L "$codex_link" ] || [ "$(readlink "$codex_link")" != "$skill_store" ]; then
    record_fail 'guided install links Codex to the canonical skill'
    return
  fi
  if [ ! -L "$claude_link" ] || [ "$(readlink "$claude_link")" != "$skill_store" ]; then
    record_fail 'guided install links Claude Code to the canonical skill'
    return
  fi
  if ! make -s -C "$ROOT" install HOME="$portable_home" \
    INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=yes > /dev/null; then
    record_fail 'repeated guided installation is idempotent'
    return
  fi

  printf 'keep\n' > "$portable_home/.local/bin/keep-me"
  printf 'keep\n' > "$portable_home/.agents/skills/keep-me"
  printf 'keep\n' > "$portable_home/.claude/skills/keep-me"
  printf 'keep\n' > "$portable_home/.local/share/amphetamine-cli/keep-me"
  if ! make -s -C "$ROOT" uninstall HOME="$portable_home"; then
    record_fail 'make uninstall completes'
    return
  fi
  if [ -e "$installed_binary" ] ||
     [ -e "$skill_store/SKILL.md" ] ||
     [ -e "$skill_store/.installed-by-amphetamine-cli" ] ||
     [ -e "$codex_link" ] || [ -L "$codex_link" ] ||
     [ -e "$claude_link" ] || [ -L "$claude_link" ]; then
    record_fail 'make uninstall removes the CLI, canonical skill, and both discovery links'
    return
  fi
  if [ ! -f "$portable_home/.local/bin/keep-me" ] ||
     [ ! -f "$portable_home/.agents/skills/keep-me" ] ||
     [ ! -f "$portable_home/.claude/skills/keep-me" ] ||
     [ ! -f "$portable_home/.local/share/amphetamine-cli/keep-me" ]; then
    record_fail 'make uninstall preserves neighboring files'
    return
  fi
  record_pass 'guided install asks about both agents and uninstall removes both skills'
}

test_agent_selection_matrix() {
  reset_fakes
  local no_skill_home=$TEST_TMP/no-skill-home
  local codex_home=$TEST_TMP/codex-only-home
  local claude_home=$TEST_TMP/claude-only-home
  local skill_store codex_link claude_link

  if ! make -s -C "$ROOT" install HOME="$no_skill_home" \
    INSTALL_CODEX_SKILL=no INSTALL_CLAUDE_SKILL=no > /dev/null; then
    record_fail 'binary-only automated install completes'
    return
  fi
  if [ ! -x "$no_skill_home/.local/bin/amphetamine" ] ||
     [ -e "$no_skill_home/.local/share/amphetamine-cli/skills/amphetamine/SKILL.md" ] ||
     [ -e "$no_skill_home/.agents/skills/amphetamine" ] ||
     [ -e "$no_skill_home/.claude/skills/amphetamine" ]; then
    record_fail 'no/no selection installs only the CLI'
    return
  fi

  if ! make -s -C "$ROOT" install HOME="$codex_home" \
    INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=no > /dev/null; then
    record_fail 'Codex-only automated install completes'
    return
  fi
  skill_store=$codex_home/.local/share/amphetamine-cli/skills/amphetamine
  codex_link=$codex_home/.agents/skills/amphetamine
  claude_link=$codex_home/.claude/skills/amphetamine
  if [ ! -f "$skill_store/SKILL.md" ] ||
     [ ! -L "$codex_link" ] || [ "$(readlink "$codex_link")" != "$skill_store" ] ||
     [ -e "$claude_link" ] || [ -L "$claude_link" ]; then
    record_fail 'yes/no selection enables only Codex discovery'
    return
  fi
  if ! make -s -C "$ROOT" install-claude-skill HOME="$codex_home" > /dev/null; then
    record_fail 'standalone Claude skill installation completes'
    return
  fi
  if [ ! -L "$codex_link" ] || [ ! -L "$claude_link" ]; then
    record_fail 'adding Claude Code discovery preserves existing Codex discovery'
    return
  fi

  if ! make -s -C "$ROOT" install HOME="$claude_home" \
    INSTALL_CODEX_SKILL=no INSTALL_CLAUDE_SKILL=yes > /dev/null; then
    record_fail 'Claude-only automated install completes'
    return
  fi
  skill_store=$claude_home/.local/share/amphetamine-cli/skills/amphetamine
  codex_link=$claude_home/.agents/skills/amphetamine
  claude_link=$claude_home/.claude/skills/amphetamine
  if [ ! -f "$skill_store/SKILL.md" ] ||
     [ -e "$codex_link" ] || [ -L "$codex_link" ] ||
     [ ! -L "$claude_link" ] || [ "$(readlink "$claude_link")" != "$skill_store" ]; then
    record_fail 'no/yes selection enables only Claude Code discovery'
    return
  fi

  record_pass 'automation choices independently control and safely extend agent discovery'
}

test_install_requires_explicit_choices() {
  reset_fakes
  local prompt_home=$TEST_TMP/prompt-eof-home
  local invalid_home=$TEST_TMP/invalid-choice-home

  if make -s -C "$ROOT" install HOME="$prompt_home" < /dev/null \
    > /dev/null 2>"$TEST_TMP/prompt-eof.err"; then
    record_fail 'installer rejects missing non-interactive choices'
    return
  fi
  if [ -e "$prompt_home/.local/bin/amphetamine" ] ||
     ! assert_contains "$(<"$TEST_TMP/prompt-eof.err")" 'INSTALL_CODEX_SKILL=yes or no' \
       'installer explains the non-interactive Codex choice'; then
    return
  fi

  if make -s -C "$ROOT" install HOME="$invalid_home" \
    INSTALL_CODEX_SKILL=maybe INSTALL_CLAUDE_SKILL=no \
    > /dev/null 2>"$TEST_TMP/invalid-choice.err"; then
    record_fail 'installer rejects an invalid automated choice'
    return
  fi
  if [ -e "$invalid_home/.local/bin/amphetamine" ]; then
    record_fail 'invalid automated choice makes no installation changes'
    return
  fi
  record_pass 'non-interactive installs require explicit valid agent choices'
}

test_custom_prefix_install() {
  reset_fakes
  local custom_home=$TEST_TMP/custom-home
  local custom_prefix=$TEST_TMP/custom-prefix

  if ! make -s -C "$ROOT" install HOME="$custom_home" PREFIX="$custom_prefix" \
    INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=no > /dev/null; then
    record_fail 'custom-prefix install completes'
    return
  fi
  if [ ! -x "$custom_prefix/bin/amphetamine" ] ||
     [ ! -L "$custom_home/.agents/skills/amphetamine" ] ||
     [ ! -f "$custom_home/.local/share/amphetamine-cli/skills/amphetamine/SKILL.md" ]; then
    record_fail 'custom-prefix install separates binary and user skill destinations'
    return
  fi
  if ! make -s -C "$ROOT" uninstall HOME="$custom_home" PREFIX="$custom_prefix"; then
    record_fail 'custom-prefix uninstall completes'
    return
  fi
  if [ -e "$custom_prefix/bin/amphetamine" ] ||
     [ -e "$custom_home/.local/share/amphetamine-cli/skills/amphetamine/SKILL.md" ] ||
     [ -L "$custom_home/.agents/skills/amphetamine" ]; then
    record_fail 'custom-prefix uninstall removes both installed artifacts'
    return
  fi
  record_pass 'custom PREFIX changes the binary destination without losing skill discovery'
}

test_selected_skill_conflict() {
  reset_fakes
  local conflict_home=$TEST_TMP/conflict-home
  local conflict_path=$conflict_home/.claude/skills/amphetamine
  local skill_store=$conflict_home/.local/share/amphetamine-cli/skills/amphetamine

  mkdir -p "$conflict_path"
  printf 'owned elsewhere\n' > "$conflict_path/keep-me"
  if make -s -C "$ROOT" install HOME="$conflict_home" \
    INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=yes \
    > /dev/null 2>"$TEST_TMP/claude-conflict.err"; then
    record_fail 'Claude skill installation rejects an existing destination'
    return
  fi
  if [ ! -f "$conflict_path/keep-me" ] ||
     [ -e "$skill_store/SKILL.md" ] ||
     [ -e "$conflict_home/.agents/skills/amphetamine" ] ||
     [ -e "$conflict_home/.local/bin/amphetamine" ]; then
    record_fail 'selected skill conflict preserves existing state without partial installation'
    return
  fi
  if ! make -s -C "$ROOT" install HOME="$conflict_home" \
    INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=no > /dev/null; then
    record_fail 'an unselected unrelated skill does not block installation'
    return
  fi
  if [ ! -L "$conflict_home/.agents/skills/amphetamine" ] ||
     [ ! -f "$conflict_path/keep-me" ]; then
    record_fail 'unselected unrelated skill is preserved'
    return
  fi
  record_pass 'selected conflicts fail closed while unselected unrelated skills are preserved'
}

test_canonical_store_conflict() {
  reset_fakes
  local conflict_home=$TEST_TMP/canonical-conflict-home
  local conflict_skill=$conflict_home/.local/share/amphetamine-cli/skills/amphetamine/SKILL.md
  local symlink_home=$TEST_TMP/symlink-store-home
  local external_store=$TEST_TMP/external-skill-store
  local symlink_store=$symlink_home/.local/share/amphetamine-cli/skills/amphetamine

  mkdir -p "${conflict_skill%/*}"
  printf 'owned elsewhere\n' > "$conflict_skill"
  if make -s -C "$ROOT" install HOME="$conflict_home" \
    INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=no \
    > /dev/null 2>"$TEST_TMP/canonical-conflict.err"; then
    record_fail 'canonical skill installation rejects an unowned destination'
    return
  fi
  if [ "$(<"$conflict_skill")" != 'owned elsewhere' ] ||
     [ -e "$conflict_home/.local/bin/amphetamine" ]; then
    record_fail 'canonical skill conflict preserves existing state without a partial binary install'
    return
  fi
  if make -s -C "$ROOT" uninstall HOME="$conflict_home" > /dev/null 2>"$TEST_TMP/canonical-uninstall-conflict.err"; then
    record_fail 'canonical skill uninstall rejects an unowned destination'
    return
  fi
  if [ ! -f "$conflict_skill" ]; then
    record_fail 'canonical skill uninstall preserves an unowned skill'
    return
  fi

  mkdir -p "$external_store" "${symlink_store%/*}"
  cp "$ROOT/skill/SKILL.md" "$external_store/SKILL.md"
  : > "$external_store/.installed-by-amphetamine-cli"
  ln -s "$external_store" "$symlink_store"
  if make -s -C "$ROOT" uninstall HOME="$symlink_home" \
    > /dev/null 2>"$TEST_TMP/symlink-store-uninstall.err"; then
    record_fail 'uninstall rejects a symlinked canonical store'
    return
  fi
  if [ ! -f "$external_store/SKILL.md" ] || [ ! -L "$symlink_store" ]; then
    record_fail 'symlinked canonical store rejection preserves external files'
    return
  fi
  record_pass 'canonical skill install and uninstall refuse unowned state without partial changes'
}

test_legacy_skill_migration() {
  reset_fakes
  local legacy_home=$TEST_TMP/legacy-home
  local legacy_codex=$legacy_home/.agents/skills/amphetamine
  local legacy_claude=$legacy_home/.claude/skills/amphetamine
  local skill_store=$legacy_home/.local/share/amphetamine-cli/skills/amphetamine

  mkdir -p "$legacy_codex" "${legacy_claude%/*}"
  cp "$ROOT/skill/SKILL.md" "$legacy_codex/SKILL.md"
  : > "$legacy_codex/.installed-by-amphetamine-cli"
  ln -s "$legacy_codex" "$legacy_claude"

  if ! make -s -C "$ROOT" install HOME="$legacy_home" \
    INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=yes > /dev/null; then
    record_fail 'legacy skill layout migrates during guided install'
    return
  fi
  if [ ! -f "$skill_store/SKILL.md" ] ||
     [ ! -L "$legacy_codex" ] || [ "$(readlink "$legacy_codex")" != "$skill_store" ] ||
     [ ! -L "$legacy_claude" ] || [ "$(readlink "$legacy_claude")" != "$skill_store" ]; then
    record_fail 'legacy skill migration produces the neutral canonical layout'
    return
  fi
  if ! make -s -C "$ROOT" uninstall HOME="$legacy_home" > /dev/null; then
    record_fail 'migrated layout uninstalls cleanly'
    return
  fi
  if [ -e "$skill_store/SKILL.md" ] || [ -L "$legacy_codex" ] || [ -L "$legacy_claude" ]; then
    record_fail 'uninstall removes both migrated discovery links and canonical skill'
    return
  fi
  record_pass 'existing v1 skill installs migrate and uninstall cleanly'
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
test_guided_install_and_uninstall
test_agent_selection_matrix
test_install_requires_explicit_choices
test_custom_prefix_install
test_selected_skill_conflict
test_canonical_store_conflict
test_legacy_skill_migration

if [ "$failed" -ne 0 ]; then
  printf '%d test(s) failed; %d passed\n' "$failed" "$passed" >&2
  exit 1
fi

printf '1..%d\n' "$passed"
