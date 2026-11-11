# Scheduled jobs

Jobs survive restarts and redeploys because they are lines in a file on the volume. [Supercronic](https://github.com/aptible/supercronic) (pinned by version and checksum) is the clock; this project adds two small scripts.

## How it works

| Piece | What it is |
|---|---|
| `config.sh job "M H D M W" NAME "PROMPT"` | How a job is added: by the agent, when the owner asks in chat. Validates the schedule and the name, tells the owner. `config.sh drop NAME` removes it |
| `/data/cron/jobs`, `/data/cron/prompts/NAME` | The agent's jobs (`SCHEDULE job.sh NAME`) and their prompts, on the volume |
| `bin/system.cron` | The image's own jobs (the daily recycle at 04:00, and `watchdog.sh` every five minutes). Root-owned, replaced by every image update |
| `/data/cron/crontab` | What Supercronic runs: the image's jobs plus the agent's, rebuilt by `config.sh apply` at every start and after every change. **Only well-formed `job.sh NAME` lines are copied**: anything else written into the files never runs |
| `job.sh NAME` | Runs the prompt in a separate Claude session (`claude -p`), which only writes the message; the script sends it to the owner in private, or to a group the agent is in if the job was given one (`config.sh job … GROUP_ID`). Failures always go to the owner. It alerts the owner if it fails or exceeds `JOB_TIMEOUT` (default 900 s) |
| `/data/workspace/sent.jsonl` | One line per delivery (when, job, destination, text; last 500). A `UserPromptSubmit` hook shows the agent its last five deliveries of the last 24 hours, each cut at 400 characters, with every message it receives, so "explain the first item" works. The file is also there for the agent to read |

Why the filter: a cron line runs outside Claude Code, with no permission check, no hook and no audit record. Limiting cron to `job.sh` keeps every scheduled action inside a Claude session under the managed policy. On hosts without a hard floor the agent's shell could still rewrite these files; the filter removes the documented, easy path, and a restart restores the image's jobs.

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

## Verified on Railway (2026-11-10, after the audit fixes)

- A job added with `config.sh job` ran, delivered in private, and was dropped by the agent afterwards; another delivered to a group the agent is in.
- The `UserPromptSubmit` hook fires for messages that arrive through the Telegram channel: asked what context came with the owner's message, the agent described the note and the delivery it listed. A follow-up question about a job's message ("even if it is completely cut off?") was answered correctly with no other context.

## Not verified yet

- Whether jobs share the subscription's usage window with the bot.
- The daily recycle (`pkill -x script` at 04:00): check the service log the morning after.
- On Railway (2026-11-10): a job added with `config.sh job` ran and was dropped by the agent afterwards. A job meant for a group failed, because jobs could only reach the owner and the job's session looked for a tool to send with; fixed, to be re-tested.
- The downtime notice after a real outage, and a failing or hung job in production.
