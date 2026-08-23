---
name: amphetamine
description: Control Amphetamine keep-awake, display-sleep, and lid-close sessions from a coding agent. Use when an agent needs to inspect, start, change, or stop a Mac keep-awake session.
---

# Amphetamine

Use the installed `amphetamine` binary exclusively. Its status output exposes the active session, remaining time, display-sleep behavior, and lid-close keep-awake state without changing Amphetamine's global closed-display setting.

## Commands

| # | Intent | Command |
|---:|---|---|
| 1 | Inspect status | `amphetamine status` |
| 2 | Inspect structured status | `amphetamine status --json` |
| 3 | Start from Amphetamine Preferences | `amphetamine start` |
| 4 | Start indefinitely | `amphetamine start --indefinite` |
| 5 | Start for a duration | `amphetamine start 2h`, `amphetamine start 45m`, or `amphetamine start 2h30m` |
| 6 | Allow display sleep this session | `amphetamine start 2h --display-sleep` or `amphetamine display sleep` |
| 7 | Prevent display sleep this session | `amphetamine start 2h --no-display-sleep` or `amphetamine display no-sleep` |
| 8 | Stop | `amphetamine stop` |

Add `--json` to `start`, `stop`, or `display` when the result will be consumed programmatically. It replaces human stdout with the status schema returned by `amphetamine status --json`.

`amphetamine display sleep` and `amphetamine display no-sleep` are session-only and exit `2` when no session is active. Use them instead of changing Amphetamine Preferences.

Route all Amphetamine automation through this binary; do not hand-write `osascript` commands. In particular, preserve the user's closed-display-mode configuration and treat `lid_close_keep_awake` as read-only status.
