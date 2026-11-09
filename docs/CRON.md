# Persistent scheduled jobs: design proposal

Status: proposal, nothing implemented. Requirement from the owner: scheduled jobs must be extremely persistent.

## What "persistent" has to survive

1. A container restart or redeploy (the volume survives; the process does not).
2. A crash of Claude Code (`start.sh` exits, the host restarts the container).
3. A job that was due while the container was down.
4. A job that hangs.

## Proposal

- **Job definitions live on the volume**: `/data/cron/crontab` (standard 5-field syntax) plus `/data/cron/state/<job>.last` (last successful start, written by the runner). Editing the file is the only interface.
- **One small scheduler process** started by `start.sh` next to Claude (about 15 lines of shell, or the single static binary [Supercronic](https://github.com/aptible/supercronic) if the owner accepts a pinned, checksummed download). It runs each job as the `agent` user with a timeout.
- **Catch-up on start**: for each job, if the last scheduled time is newer than `<job>.last`, run it once. This is what makes a restart not lose a job.
- **A job is a prompt**, not a script: the runner calls `claude -p "<prompt>"` with the same credential and policy. Everything stays inside the managed policy; no second code path.
- **Failures are visible**: a failed or timed-out job sends one Telegram message to the owner (same mechanism as the existing alert hook), never silent.
- **No overlap**: a lock per job; a hung run is killed at the timeout and reported.

## Open questions (need the owner or a lab run)

- Does `claude -p` with the subscription token work headless inside the container next to a running interactive session? (Not verified.)
- Does a headless run share the 5-hour subscription window with the interactive bot? Likely yes; a burst of jobs could starve the bot.
- Supercronic (one more downloaded binary, a supply-chain item) or the shell runner (no dependency, less tested)?
- Time zone: jobs follow `TZ`.

## Acceptance tests to write first

1. A job due while the container was down runs once after the start.
2. A job that already ran for its slot does not run twice.
3. A hung job is killed at its timeout and the owner is alerted.
4. The scheduler dying makes the entrypoint exit, so the host restarts the container.
