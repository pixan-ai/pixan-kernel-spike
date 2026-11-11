# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/) once the first release is tagged.

## [Unreleased]

### Changed

- **Groups are open.** In a group the agent was told to join it now reads and can answer every member, people and bots, instead of only the owner and listed ids. `TELEGRAM_GROUP_SENDERS` and `config.sh sender` are removed. The agent is told its owner's id at every session start and that only the owner gives instructions; in groups that is an instruction, not a lock (see `docs/GROUPS.md`). Super-users (`config.sh admin ID`) may also give instructions in the groups; the owner or any super-user names them, on this agent or on a fellow agent.
- CI fails when the publishable base image has a fixable CRITICAL vulnerability (Trivy). The agent image, which adds Claude Code and the plugin, stays report-only.
- The agent is shown its recent job deliveries with every message (a `UserPromptSubmit` hook over `sent.jsonl`), instead of being asked to read a file it could skip. `sent.md` is replaced by `sent.jsonl`, written one line at a time.
- Jobs can deliver to a group the agent is in (`config.sh job … GROUP_ID`); the job's session is told it only writes the message; a job's stderr no longer reaches Telegram except in its failure notice to the owner (seen on Railway: a job for a group ended as an error message in private).
- `tini` is PID 1 (SIGTERM reaches the entrypoint); the bot token is removed from the environment before Claude and the scheduler start; a missing `TELEGRAM_BOT_TOKEN` or `OWNER_TELEGRAM_ID` fails at once; `mem_limit` in compose; the start log no longer prints a `whitespace:` field that could only say "no"; tests share `tests/lib.sh`.
- **Security:** scheduled jobs can only be `job.sh NAME` (a prompt run inside Claude under the policy). The agent adds them with `config.sh job`, which tells the owner; any other line in the cron files never runs. The daily recycle moved to the image (`bin/system.cron`), so the agent cannot remove it and updates reach existing volumes.
- `access.json` is replaced atomically.
- Policy: bypass-permissions mode is disabled (`disableBypassPermissionsMode`), and the setting that pre-accepted its warning (`skipDangerousModePermissionPrompt`) is gone.
- Removed `railway.json` (Railway stops reading it on 2026-12-01); the service settings in docs/DEPLOY-RAILWAY.md are the configuration.
- Alert hooks use `notify.sh`: the bot token no longer appears on a command line.
- The audit log records one short line per event instead of the whole event, and keeps its last 10000 lines (it grew without limit and duplicated the transcript).
- Group instructions: a message from the owner to the group in general is answered (seen on Railway: both agents stayed silent on a plain "Hola").
- `config.sh` answers with a confirmation and the resulting groups and senders, so an agent that changes a fellow agent's settings can verify it (seen on Railway: the change worked but returned nothing).
- `access.json` is rebuilt from the variables at every start (it was written only once): changing the owner or the groups is a variable change and a redeploy.
- A restart continues the last conversation (`--continue`). If Claude dies within a minute while continuing, the next start opens a fresh session. A 60-second brake slows crash loops.
- Fix: the Telegram plugin ran from the image's build path (its registry files hold absolute paths), outside the policy's protection, and a newer image could not replace the copy on the volume. Every start now copies the plugin to the volume and points its registry there.
- Fix: the agent could not see photos or files sent on Telegram. They land in the plugin's inbox, outside the workspace, and the first read was denied. The inbox is now an additional working directory (still not writable by the agent).
- The agent's instructions moved to the managed location (`/etc/claude-code/CLAUDE.md`): root-owned, updated with every image, not editable by the agent. The copy seeded earlier in `/data/workspace` is no longer written.
- The Dockerfile has two targets: `base` (no Anthropic software, the only publishable one) and `agent` (default; adds Claude Code and the plugin). The release workflow pushes `base` only and CI verifies it contains no Claude Code.
- Docs: the security level is stated per host (**Railway: soft floor only**) in README and SECURITY.md, with the namespace check for hosts that can do better.
- The base image is pinned by digest; a test fails on an unpinned `FROM`.
- Start-up asks Telegram (`getMe`) once and fails fast on HTTP 401 (revoked or mistyped bot token) instead of leaving the bot mute. A network error does not stop the start.

### Added

- Opt-in sleep (`IDLE_SLEEP_MINUTES`): Claude stops after a quiet period and a Telegram webhook wakes the agent; the official plugin still receives the message by polling. On Railway with Serverless an idle agent used no memory, and answered 2 to 3 s after a message. See docs/SLEEP.md.
- Unanswered-message alert: a message whose turn has not ended after ten minutes is reported to the owner, once.
- docs/GETTING-STARTED.md: installation for a first-time user, and what to tell the agent afterwards.
- Backup and restore: a nightly backup of memory, conversations, workspace, settings and jobs, encrypted with age inside the container and sent with rclone (Google Drive by default, Cloudflare R2 as an alternative); restore onto an empty volume by setting the private key. See docs/BACKUP.md.
- Watchdog: when Claude runs but the Telegram plugin's process is gone (two checks, five minutes apart), the owner is told and Claude restarts with the conversation.
- The agent knows its own Telegram bot name and id from the first message: the start-up check keeps Telegram's answer and the SessionStart hook states it (seen on Railway: an agent in a group did not know it was being addressed).
- Settings by chat: the agent adds groups, senders and fellow agents itself (`config.sh`), applies them at once and tells the owner every time. A fellow agent can set another's groups over the peer channel. See docs/SETTINGS.md.
- Peer view: `transcript` (the recent conversation of a fellow agent) and names from `PEERS` instead of addresses.
- Telegram groups: `TELEGRAM_GROUP_IDS` and `TELEGRAM_GROUP_SENDERS`; no mention needed in a listed group. See docs/GROUPS.md.
- Peer view (opt-in): a fellow agent holding a listed key can read this agent's screen, status and denials over SSH with a forced command; nothing else. See docs/PEERS.md.
- `procps` in the image: the seeded daily recycle uses `pkill`.
- Scheduled jobs that survive restarts: a crontab on the volume run by Supercronic (pinned), `job.sh` (a prompt in its own Claude session, answer sent to the owner and kept in `sent.md`, alert on failure or timeout), a downtime notice at start, and a daily recycle at 04:00. Claude Code's in-session scheduler is disabled. See docs/CRON.md.
- The agent gets a `CLAUDE.md` in its workspace stating its limits (denied prompts, no credentials, connectors disabled, only `/data` persists). Copied once; the owner can edit the copy.
- Claude Code on Telegram in one container: the official harness in a `script` pty, the official Telegram channel plugin, a root-owned managed policy.
- Credential: a Claude subscription token (`CLAUDE_CODE_OAUTH_TOKEN`) or an API key (`ANTHROPIC_API_KEY`).
- Railway support: volume ownership handled by the entrypoint (`RAILWAY_RUN_UID=0`), screen mirror to the service log (opt-in, see Changed).
- Policy: `denyInsteadOfPrompting` so an unattended agent never waits for a person; deny rules and an auto-mode rule against leaking credentials; hooks that audit and alert the owner on Telegram.
- Acceptance tests for the entrypoint, the diagnostic tools, the policy and the documentation, run in CI inside the built image.
- Documentation: findings, architecture, Railway deployment, threat model, secrets, repository settings.
- Supply chain: every action pinned to a commit SHA (and a test that keeps it so), CodeQL for the workflows, OpenSSF Scorecard, a report-only Trivy scan, and a release workflow that publishes with an SBOM, SLSA provenance, a keyless cosign signature and a GitHub attestation. See [docs/RELEASING.md](docs/RELEASING.md).

### Fixed

- The entrypoint now exits with status 1 and says so when Claude exits (it used to exit with 141).
- The entrypoint fails fast, naming the missing variable, when no Claude credential is set.
- A token copied from a phone with line breaks is cleaned before use.

### Changed

- **Privacy:** the screen mirror to the service log is now off by default. It contains the owner's conversation, and service logs are visible to anyone with project access. Set `SCREEN_MIRROR=<seconds>` to turn it on while debugging.
