# Architecture

## Components

| Piece | Role | Source |
|---|---|---|
| Claude Code (pinned by `CLAUDE_CODE_VERSION`) | The agent harness | Anthropic, official installer |
| `telegram@claude-plugins-official` | Channel: pushes messages into the session, exposes `reply`, `react`, `edit_message`, `download_attachment` | Anthropic, Apache-2.0 |
| `script` | Provides the pty that interactive Claude needs | util-linux |
| `bin/start.sh` | Seeds config, writes the allowlist, pre-accepts onboarding, starts claude | this repo |
| `policy/managed-settings.json` | Permissions, hooks, channel enablement | this repo |

## Why interactive mode in a pty

Channel events are delivered to a live interactive session. In `-p` mode an idle process does not start a turn when an event arrives. The smallest thing that gives Claude a terminal without a person is a pty, and `script` is already in the base image. `tail -f /dev/null` keeps stdin open.

## State

One volume at `/data`:

- `/data/config`: Claude config, plugin, transcripts, auto memory, Telegram `access.json`
- `/data/workspace`: the agent working directory (put `CLAUDE.md` here to steer behavior)
- `/data/audit.jsonl`: hook audit log
- `/data/tui.log`: raw screen log (read it with `bin/screen.sh`)

## Failure handling

- `claude` exits: the container exits with status 1 and restarts.
- Credential error: the `StopFailure` hook sends a Telegram alert to the owner.
- A message unanswered after ten minutes, or the Telegram plugin gone while Claude runs: `watchdog.sh` tells the owner (and restarts Claude for the plugin). Anything else: check `bin/screen.sh`.

## Permission profiles

Three official profiles, no code: strict (`dontAsk`), human in the loop (manual mode and Telegram buttons), automatic (classifier, the default here). Select with `CLAUDE_FLAGS` and the policy.
