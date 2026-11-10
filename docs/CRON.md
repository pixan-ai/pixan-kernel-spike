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

## Verified on Railway (2026-11-10)

- A job the bot scheduled itself ran three minutes later with the subscription token, headless, next to the interactive session, and its message reached the owner.
- The bot then answered "what did you just send me?" correctly from `sent.md`, and removed the one-off line from the crontab.
- Times follow `TZ` (Supercronic logs in -06:00; the message said 9:01 CST).
- After a redeploy the bot continued the conversation (it listed the attachments sent the night before).

## Not verified yet

- Whether jobs share the subscription's usage window with the bot.
- The daily recycle (`pkill -x script` at 04:00): check the service log the morning after.
- The downtime notice after a real outage, and a failing or hung job in production.
