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
| Auto mode can still stall on a permission prompt (for example a first Read outside the working directories). A `Notification` hook (`permission_prompt`) now alerts the owner on Telegram; the alert itself is not yet observed firing. | Lab (alert: Open) |
| A broad `Edit(//data/config/**)` deny also blocked the agent's own memory directory. Deny specific files instead. | Lab |
| `deny` rules block file tools, not Bash. | Docs, Lab |
| A `Read` deny rule also prevented writing the same file. Whether `Read(**/.env)` blocked reads is **not** settled: the audit log shows two reads of `/data/workspace/.env`, and the hook type that logged them was not identified. | Lab (unresolved) |
| The model is not pinned: different sessions ran different Opus versions. Set `ANTHROPIC_MODEL`. | Lab |
| While the machine is suspended nothing runs. A background timer that was due during suspension fired on wake. | Lab (inferred) |
| `/start` on the bot shows pairing instructions even when the allowlist is active. | Code |
| Railway mounts the volume owned by root, so the non-root image could not write `/data`. Fixed with `RAILWAY_RUN_UID=0` plus a privilege drop in `start.sh`; Claude still runs as uid 1001. | Lab |
| A malformed OAuth token (truncated, or with line breaks from a phone copy) gives no auth error at start: Claude shows "Channels are not currently available" and manual mode, and the bot only shows "typing". `start.sh` now strips whitespace and logs length and prefix, never the value. | Lab |
| Railway does not allow user namespaces (`bwrap: Creating new namespace failed: Permission denied`). So `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` and the official sandbox (both need bubblewrap on Linux) cannot run there: a shell command can read the tokens. Mitigated only by soft layers: `deny` rules for env dumps and an `autoMode.hard_deny` rule against reading or sending credentials. | Lab |
| Railway has no shell into the container; `start.sh` mirrors the readable screen to the service log when it changes. | Lab |

## Open items

- Hard floor for the shell (sandbox or filesystem permissions).
- Egress allowlist (a firewall needs `NET_ADMIN`; unverified on Railway).
- Environment scrubbing while the bot token sits in a plugin file.
- Slack (there is no official Slack channel plugin; Claude Tag is a different product).
- Two users and simultaneous messages.
- 24-hour soak test with a non-expiring key and memory growth.
- Whether adding `/tmp` to `permissions.additionalDirectories` removes the stall prompt.
- Preflight check for a reused bot token (`getMe` and HTTP 409).
