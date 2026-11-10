# Scheduled jobs

Jobs survive restarts and redeploys because they are lines in a file on the volume. [Supercronic](https://github.com/aptible/supercronic) (pinned by version and checksum) is the clock; this project adds two small scripts.

## How it works

| Piece | What it is |
|---|---|
| `/data/cron/crontab` | The schedule. Standard cron syntax, times in the container's `TZ`. Seeded once from `seed/crontab`; then it is the owner's. Edits apply at once |
| `supercronic` | Runs the lines when they are due. Started by `start.sh` |
| `job.sh NAME "PROMPT"` | Runs the prompt in a separate Claude session (`claude -p`), sends the answer to the owner on Telegram, alerts the owner if it fails or exceeds `JOB_TIMEOUT` (default 900 s) |
| `notify.sh TEXT` | One Telegram message to the owner |
| `/data/workspace/sent.md` | A copy of what jobs sent (last 300 lines). The bot's instructions tell it to read this when the owner refers to something it does not remember sending |

Example line:

```
0 8 * * *  job.sh news "Summarise today's AI news in five bullets"
```

The seeded file contains one job: a daily recycle at 04:00 (`pkill -x script`). The container restarts and Claude continues the conversation.

## Why a separate session, with its own config directory

A second Claude started on the bot's config directory would start a second Telegram plugin, and the plugin kills the previous holder of the bot (`bot.pid`): the bot would go deaf while Claude stays alive. Jobs therefore use `/data/cron/config`, where no plugin is installed, and deliver through `notify.sh`.

Claude Code's own in-session scheduler is disabled (`CLAUDE_CODE_DISABLE_CRON=1`): its jobs die at the next restart.

## What it does not do

- **It does not run jobs that were due while the container was down.** Instead, a start after more than five minutes without a heartbeat tells the owner from when to when it was down.
- If `supercronic` itself dies, jobs stop until the next restart (at the latest, the daily recycle).

## Not verified yet (needs the lab)

- `claude -p` with a subscription token, headless, next to the interactive session.
- Whether jobs share the subscription's usage window with the bot.
- `--permission-mode auto` for jobs under the managed policy.
- That `TZ` moves the schedule (the image needs time zone data).
