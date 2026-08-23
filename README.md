# amphetamine-cli

Control [Amphetamine](https://apps.apple.com/us/app/amphetamine/id937984704) sessions from a terminal or coding agent.

This is an unofficial CLI and requires the Amphetamine app from the Mac App Store.

## Install

Clone the repository, then install from its root:

```sh
git clone https://github.com/kennymcavoy/amphetamine-cli.git
cd amphetamine-cli
make install
```

`make install` always installs the CLI and asks independently whether to enable its agent skill for Codex and Claude Code:

```text
Enable the Amphetamine skill for Codex? [y/n] y
Enable the Amphetamine skill for Claude Code? [y/n] y
```

The default destinations are:

- `~/.local/bin/amphetamine` — the CLI executable
- `~/.local/share/amphetamine-cli/skills/amphetamine/SKILL.md` — one canonical skill copy, created when either agent is selected
- `~/.agents/skills/amphetamine` — a Codex discovery link, created only when selected
- `~/.claude/skills/amphetamine` — a Claude Code discovery link, created only when selected

The canonical skill directory contains a small ownership marker so uninstall can distinguish this project's files from somebody else's. Nothing links back to the cloned repository, so you can remove the clone after installation. Restart an existing agent session if the newly enabled skill is not discovered immediately.

For an unattended installation, provide both choices explicitly:

```sh
make install INSTALL_CODEX_SKILL=yes INSTALL_CLAUDE_SKILL=no
```

Each value must be `yes` or `no`. If input is unavailable and either choice is missing, installation stops before making changes. A `no` skips adding that agent's discovery link; removing previously installed links is the job of `make uninstall`.

Set `PREFIX` to install the executable elsewhere:

```sh
make install PREFIX=/your/prefix
```

Advanced installations can override `SKILL_DATA_ROOT`, `CODEX_SKILLSDIR`, and `CLAUDE_SKILLSDIR`; pass those same values to later install and uninstall commands.

Make sure the selected `bin` directory is on `PATH`. On the first CLI command, macOS may ask the calling terminal or agent app for permission to control Amphetamine; allow it under System Settings → Privacy & Security → Automation.

The repository's `AGENTS.md` is development guidance and is not installed. Agent-facing CLI instructions come from the installed `SKILL.md`.

## Uninstall

From the source directory, remove the default installation with:

```sh
make uninstall
```

If you installed with a custom prefix, pass the same value when uninstalling:

```sh
make uninstall PREFIX=/your/prefix
```

`make uninstall` removes the executable, the canonical skill installed by this project, and both installer-owned Codex and Claude Code discovery links. It refuses to remove a canonical skill directory that it did not install.

Without the source directory, the equivalent safe removal for a default installation is:

```sh
skill_dir="$HOME/.local/share/amphetamine-cli/skills/amphetamine"
codex_link="$HOME/.agents/skills/amphetamine"
claude_link="$HOME/.claude/skills/amphetamine"

rm -f "$HOME/.local/bin/amphetamine"

if [ ! -L "$skill_dir" ] &&
   [ -f "$skill_dir/.installed-by-amphetamine-cli" ] &&
   [ ! -L "$skill_dir/.installed-by-amphetamine-cli" ]; then
  if [ -L "$codex_link" ] && [ "$(readlink "$codex_link")" = "$skill_dir" ]; then
    rm -f "$codex_link"
  fi
  if [ -L "$claude_link" ] && [ "$(readlink "$claude_link")" = "$skill_dir" ]; then
    rm -f "$claude_link"
  fi
  rm -f "$skill_dir/SKILL.md" "$skill_dir/.installed-by-amphetamine-cli"
  rmdir "$skill_dir" 2>/dev/null || true
  rmdir "${skill_dir%/*}" 2>/dev/null || true
  rmdir "$HOME/.local/share/amphetamine-cli" 2>/dev/null || true
fi
```

Uninstall leaves containing directories, neighboring files and skills, Amphetamine.app, Amphetamine Preferences, and macOS Automation permissions unchanged.

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
| 14 | `amphetamine version` | Show the installed CLI version |
| 15 | `amphetamine help` | Show CLI help |

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

The test suite uses fake `osascript` and `defaults` commands, so it does not need Amphetamine. CI runs it on Ubuntu and again with the macOS system Bash 3.2; ShellCheck runs on Ubuntu.
