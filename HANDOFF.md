# Handoff: implement v1

This repo is a scaffold. You implement the CLI. The design is closed; do not re-grill Kenny.

**Done when:** `bin/amphetamine` exists, `make install` copies it to `$(HOME)/.local/bin/amphetamine`, stub tests + `shellcheck` pass, a live run against Amphetamine.app on this Mac prints status after `start` / `stop` / `display`, `skill/SKILL.md` is written, `README.md` is the user-facing doc (replace the stub). Do **not** `gh repo create` or push; first GitHub push is a later human step once the tool works.

## What this is

Unofficial bash 3.2 wrapper around Amphetamine’s AppleScript dictionary. Public later so someone else with the same need can use it. Quality bar is “works well,” not Homebrew or community-health files.

Kenny’s own workflow: timed session, close the lid, drive agents from a phone. Amphetamine closed-display mode (already in *his* Preferences) is what makes lid-close work. `caffeinate` does not survive lid-close. This CLI must not fight that: **never call enable/disable closed display mode**.

## Names

| | |
|---|---|
| Directory / git / eventual GitHub | `~/Projects/amphetamine-cli` → `kennymcavoy/amphetamine-cli` |
| Command | `amphetamine` |
| Language | `/usr/bin/env bash`, written for macOS Bash 3.2 |
| License | `LICENSE` already MIT. One README line: unofficial, needs the App Store app. No SECURITY.md, CoC, Formula, changelog ritual |

## v1 commands

```text
amphetamine                         # same as status
amphetamine status
amphetamine status --json
amphetamine start                   # no AppleScript options; full Preferences
amphetamine start --indefinite
amphetamine start 2h
amphetamine start 45m
amphetamine start 2h30m
amphetamine start 2h --display-sleep
amphetamine start 2h --no-display-sleep
amphetamine display sleep
amphetamine display no-sleep
amphetamine stop
amphetamine help
amphetamine -h
amphetamine --help
```

`--json` is allowed on `start` / `stop` / `display` / `status` and **replaces** human stdout (same schema).

### Duration

- Accept (case-insensitive): `2h`, `45m`, `2h30m`.
- Combined form: `NhMm` only (`2h30m`). Reject `2h30`.
- Reject: `0h`, `0m`, `0h0m`, bare `90`, `1.5h`.
- `--indefinite` is the only zero-length session (`duration:0, interval:0`).
- `2h30m` → `{duration:150, interval:minutes, ...}`.
- `2h` → `{duration:2, interval:hours, ...}`.
- `45m` → `{duration:45, interval:minutes, ...}`.

### Defaults vs session

Amphetamine Preferences are the default. The CLI only changes **this session**, and only when asked.

- `start` with no duration/flags: `tell application "Amphetamine" to start new session` (no `with options`).
- `start <duration>` or `start --indefinite`: must send the full options record (Amphetamine’s record is all-or-nothing). Fill `displaySleepAllowed` from **Preferences**, not from a running session, unless `--display-sleep` / `--no-display-sleep` is present.
- Read the pref with `defaults read com.if.Amphetamine "Allow Display Sleep"` (`1`/`0`). Do **not** use AppleScript `display sleep allowed` for this fill if a session might already be active — that getter returns the *session* value, which would leak a previous override into the next session.
- `display sleep` / `display no-sleep`: current session only. If no session: print an error, exit `2`, do not call `allow display sleep` / `prevent display sleep` (those write global prefs when idle).
- `start` while a session is active: Amphetamine replaces it. No prompt. Print the new status.
- `stop` with no session: exit `0`, print inactive status.
- Do not expose CDM, triggers, clock-time, wrap-a-command, or `give molecule`.

## Output

Every mutating command and `status` print this human block (labels stable enough; wording may match this):

```text
session:     active
remaining:   2h 30m
display:     sleep allowed
lid-close:   keep awake
trigger:     no
```

Inactive:

```text
session:     inactive
```

Decode `session time remaining` for humans: `n>0` → `Xh Ym`; `0` → `indefinite`; `-1` → trigger (still `session: active`); `-2` → `until time/app`; `-3` → inactive.

`--json` (stdout, nothing else):

```json
{
  "active": true,
  "remaining_seconds": 9000,
  "display_sleep_allowed": true,
  "lid_close_keep_awake": true,
  "trigger": false
}
```

Sentinels on `remaining_seconds` are Amphetamine’s: `0` indefinite, `-1` trigger, `-2` until-time/app, `-3` no session. No human remaining string in JSON. When inactive, the two booleans are Preferences (read-only; the AppleScript getters do that).

`lid_close_keep_awake` is AppleScript `closed display mode enabled`. Print it so the user can confirm lid-close. Never set it.

On AppleScript/osascript failure: error on stderr, non-zero exit, **no** status block that looks like success.

## Exit codes

| Code | When |
|---|---|
| `0` | Success, including `stop` when already inactive |
| `2` | Bad argv, unknown command, `display` with no session |
| `1` | Amphetamine missing, osascript failed, Automation/TCC denied |

## Install

`Makefile`: `make install` copies `bin/amphetamine` to `$(PREFIX)/bin/amphetamine`. Default `PREFIX=$(HOME)/.local`. Not a symlink.

## Tests / CI

GitHub-hosted runners will not have Amphetamine.app. Put a fake `osascript` earlier on `PATH` that records the script text and returns canned values.

Assert at least:

- `start 2h` emits `start new session with options` including `duration:2`, `interval:hours`, and `displaySleepAllowed:` from the stubbed pref
- `start` (no args) emits `start new session` **without** `with options`
- `start --indefinite` uses `duration:0` and `interval:0`
- `stop` emits `end session`
- `display sleep` / `no-sleep` emit `allow display sleep` / `prevent display sleep` only when the stub says a session is active
- `display sleep` with inactive session: exit `2`, no allow/prevent call
- duration parser accepts `2h30m` as 150 minutes; rejects `90` and `0h`
- `--json` is valid JSON with the keys above

`shellcheck` on `bin/amphetamine`. A GitHub Actions workflow on `ubuntu-latest` is enough (stub + shellcheck). Live verification on Kenny’s Mac is the gate for “it actually talks to Amphetamine.”

## Live verification (this Mac)

Amphetamine is installed at `/Applications/Amphetamine.app`. Dictionary: `/Applications/Amphetamine.app/Contents/Resources/Amphetamine.sdef`. This Grok/Herdr pane has already successfully scripted it (Automation allowed for that parent). Other terminals may prompt once.

```applescript
tell application "Amphetamine"
  session is active
  session time remaining
  display sleep allowed
  closed display mode enabled
  session is Trigger
  start new session
  start new session with options {duration:2, interval:hours, displaySleepAllowed:true}
  end session
  allow display sleep
  prevent display sleep
end tell
```

Do not run `enable closed display mode` / `disable closed display mode` / `enable Triggers` / `give molecule`.

Live check: `start 1h`, confirm human status (active, ~60m, display from prefs, lid-close keep awake), `display no-sleep` then `status`, `display sleep`, `stop`, `status` inactive, `display sleep` exits 2.

## Files to add

```text
bin/amphetamine          # the tool
Makefile                 # install
tests/…                  # stub osascript + assertions
.github/workflows/ci.yml
skill/SKILL.md           # for coding agents: use this binary; do not hand-write osascript
README.md                # replace stub: install, commands, one unofficial line, TCC once
```

`skill/SKILL.md` trigger: controlling Amphetamine / keep-awake / lid-close sessions from an agent. Body: the command table, session-only rule, `--json`, “do not raw osascript.”

## Out of scope (do not add)

Homebrew tap/Formula, CDM flags, trigger enable/disable, until-clock-time, wrapping a command like `caffeinate make`, `give molecule`, GitHub repo creation, renaming the binary to `amphetamine-cli`.
