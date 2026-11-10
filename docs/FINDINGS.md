# Findings

Evidence labels: **Lab** = observed on a real run; **Docs** = from official documentation; **Code** = read from the plugin source; **Open** = not verified.

## What works

| Finding | Evidence |
|---|---|
| `claude -p --channels` does **not** wake up on channel events while idle. Interactive `claude` in a pty does. | Lab |
| The official Telegram plugin, unmodified, answers messages from the interactive session in a `script` pty, with no tmux. | Lab |
| The agent recovers after `docker compose restart`, after about 11 minutes idle, and after a laptop suspension (container not restarted, no clock drift; one case). | Lab |
| `PostToolUse` hooks fire on turns that come from Telegram. | Lab |
| Permission relay buttons (Allow/Deny) work with a manual permission mode. | Lab |
| `StopFailure` alert reaches Telegram when the API key is rejected (`authentication_failed`). | Lab |
| Auto memory works once the policy does not deny the memory directory. | Lab |
| Sessions start in auto mode (classifier) by default. | Docs, Lab |
| Runs on Railway with a Claude subscription (`CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`, Max plan): answers on Telegram in auto mode. | Lab |

## What does not, or needs care

| Finding | Evidence |
|---|---|
| Auto mode can still stall on a permission prompt (for example a first Read outside the working directories). Reproduced on Railway: a Read of `/etc/hostname` stopped the turn until Allow. The `Notification` hook (`permission_prompt`) alerted the owner on Telegram alongside the plugin's Allow/Deny buttons, and the turn finished after Allow. The hook only gets a generic message; the detail is in the plugin's "See more". | Lab |
| A broad `Edit(//data/config/**)` deny also blocked the agent's own memory directory. Deny specific files instead. | Lab |
| `deny` rules block file tools, not Bash. | Docs, Lab |
| A `Read` deny rule also prevented writing the same file. Whether `Read(**/.env)` blocked reads is **not** settled: the audit log shows two reads of `/data/workspace/.env`, and the hook type that logged them was not identified. | Lab (unresolved) |
| The model is not pinned: different sessions ran different Opus versions. Set `ANTHROPIC_MODEL`. With `ANTHROPIC_MODEL=claude-opus-5-5` on Railway, all 9 responses in the transcript carry that model. | Lab |
| While the machine is suspended nothing runs. A background timer that was due during suspension fired on wake. | Lab (inferred) |
| `/start` on the bot shows pairing instructions even when the allowlist is active. | Code |
| Railway mounts the volume owned by root, so the non-root image could not write `/data`. Fixed with `RAILWAY_RUN_UID=0` plus a privilege drop in `start.sh`; Claude still runs as uid 1001. | Lab |
| A malformed OAuth token (truncated, or with line breaks from a phone copy) gives no auth error at start: Claude shows "Channels are not currently available" and manual mode, and the bot only shows "typing". `start.sh` now strips whitespace and logs length and prefix, never the value. | Lab |
| Railway does not allow user namespaces (`bwrap: Creating new namespace failed: Permission denied`). So `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` and the official sandbox (both need bubblewrap on Linux) cannot run there: a shell command can read the tokens. Mitigated only by soft layers: `deny` rules for env dumps and an `autoMode.hard_deny` rule against reading or sending credentials. | Lab |
| When claude exited, `start.sh` died with code 141 (tail got SIGPIPE under `set -e` + `pipefail`) without logging why. The container still exited, so the restart policy worked, but the documented "exit 1 and say so" was false. Fixed (`|| true`) and covered by `tests/start_test.sh`. | Lab (test) |
| The agent does not know its own policy. Asked how to connect Gmail, it told the owner to enable the claude.ai connector and that it "should appear" in the session; `disableClaudeAiConnectors: true` blocks those connectors, so the advice cannot work. Fix: a managed `CLAUDE.md` (`/etc/claude-code/CLAUDE.md`) states its limits; verified on Railway 2026-11-10 with the workspace copy, to be re-checked with the managed one. | Lab |
| Railway deprecated Config as Code and stops reading `railway.json` on 2026-12-01. Setting the Dockerfile path on the service selected the Dockerfile builder; the restart policy, Dockerfile path and watch paths now also live on the service. | Docs, Lab |
| Railway has no shell into the container; `start.sh` mirrors the readable screen to the service log when it changes. | Lab |

## Open items

- A `CLAUDE.md` for the agent's workspace that states its limits and policy.
- Pin the plugin and the base image by digest; SBOM, provenance and signing in a release workflow.
- Hard floor for the shell (sandbox or filesystem permissions).
- Egress allowlist (a firewall needs `NET_ADMIN`; unverified on Railway).
- Environment scrubbing while the bot token sits in a plugin file.
- Slack (there is no official Slack channel plugin; Claude Tag is a different product).
- Two users and simultaneous messages.
- 24-hour soak test with a non-expiring key and memory growth.
- Whether adding `/tmp` to `permissions.additionalDirectories` removes the stall prompt.
- Zombie detection (Claude alive, Telegram channel dead): no verified signal yet. `start.sh` exits when `claude` exits, which covers a crash but not a hang. Before writing a watchdog, find in a real log what a dead channel looks like (plugin process gone, no `getUpdates` activity); a guessed signal could restart a healthy bot.
- Scheduled jobs: a design proposal exists in [docs/CRON.md](CRON.md); the open questions there need a lab run.
- Detecting a second poller on the same bot token (HTTP 409). A `getMe` preflight for revoked tokens exists; 409 only shows up while polling.
- Attachments: observed on Railway (2026-11-10) that the agent could not read a photo (inbox outside the workspace, read denied). Fixed with `permissions.additionalDirectories`; to be confirmed by sending a photo after the redeploy.
