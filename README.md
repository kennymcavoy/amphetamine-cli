# amphetamine-cli

Control [Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704) sessions from a terminal or coding agent.

This is an unofficial CLI and requires the Amphetamine app from the Mac App Store.

## Install

```sh
make install
```

This copies `bin/amphetamine` to `~/.local/bin/amphetamine`. Set `PREFIX` to install elsewhere:

```sh
make install PREFIX=/your/prefix
```

Make sure the selected `bin` directory is on `PATH`. On the first command, macOS may ask the calling terminal or agent app for permission to control Amphetamine; allow it under System Settings → Privacy & Security → Automation.

## Uninstall

From the source directory, remove the default installation with:

```sh
make uninstall
```

If you installed with a custom prefix, pass the same value when uninstalling:

```sh
make uninstall PREFIX=/your/prefix
```

Without the source directory, the equivalent default removal is:

```sh
rm -f "$HOME/.local/bin/amphetamine"
```

Uninstall removes only the `amphetamine` executable. It leaves the containing `bin` directory, Amphetamine.app, Amphetamine Preferences, and macOS Automation permissions unchanged.

## Commands

| # | Command | Effect |
|---:|---|---|
| 1 | `amphetamine` | Show status |
| 2 | `amphetamine status` | Show status |
| 3 | `amphetamine status --json` | Show machine-readable status |
| 4 | `amphetamine start` | Start using Amphetamine's Preferences |
| 5 | `amphetamine start --indefinite` | Start an indefinite session |
| 6 | `amphetamine start 2h` | Start a two-hour session |
| 7 | `amphetamine start 45m` | Start a 45-minute session |
| 8 | `amphetamine start 2h30m` | Start a 150-minute session |
| 9 | `amphetamine start 2h --display-sleep` | Start and allow display sleep for this session |
| 10 | `amphetamine start 2h --no-display-sleep` | Start and prevent display sleep for this session |
| 11 | `amphetamine display sleep` | Allow display sleep for the current session |
| 12 | `amphetamine display no-sleep` | Prevent display sleep for the current session |
| 13 | `amphetamine stop` | End the current session |
| 14 | `amphetamine help` | Show CLI help |

Durations are case-insensitive. The accepted forms are `Nh`, `Nm`, and `NhMm`; use `--indefinite` for a session with no time limit.

Add `--json` to `start`, `stop`, or `display` to replace the human-readable result with the same JSON returned by `status --json`.

## Session behavior

A bare `start` leaves all choices to Amphetamine's Preferences. A timed or indefinite start sends a complete session record, using the display-sleep Preference unless you provide a display-sleep option. Starting while another session is active replaces it.

The `display` commands affect only the current session. They refuse to run when no session is active, so they cannot accidentally change the global display-sleep Preference. The CLI reports Amphetamine's lid-close state but never changes closed-display mode.

Human-readable status looks like:

```text
session:     active
remaining:   2h 30m
display:     sleep allowed
lid-close:   keep awake
trigger:     no
```

JSON status has a stable shape:

```json
{
  "active": true,
  "remaining_seconds": 9000,
  "display_sleep_allowed": true,
  "lid_close_keep_awake": true,
  "trigger": false
}
```

`remaining_seconds` preserves Amphetamine's sentinel values: `0` for indefinite, `-1` for a Trigger, `-2` for an until-time or app-based session, and `-3` for no session.

## Exit codes

| # | Code | Meaning |
|---:|---|---|
| 1 | `0` | Success, including stopping when already inactive |
| 2 | `1` | Amphetamine is missing or AppleScript/Automation failed |
| 3 | `2` | Invalid arguments, or a display change was requested without an active session |

## Development

```sh
make test
make lint
```

The test suite uses fake `osascript` and `defaults` commands, so it does not need Amphetamine or macOS.
