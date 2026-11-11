# pixan-kernel-spike

Run **Claude Code 24x7 on Telegram** in one container, using only official components: the Claude Code harness, the official Telegram channel plugin and a managed policy file. About 60 lines of glue, no custom agent code.

> **Status: lab / alpha.** Everything marked "proven" below was observed on a real laptop (Windows, WSL2, Docker Desktop). It is not a production-ready or audited product. See [docs/FINDINGS.md](docs/FINDINGS.md) for the evidence and what is still unverified.

## Why this exists

Claude Code can receive messages from Telegram through [Channels](https://code.claude.com/docs/en/channels), but only inside a **live interactive session**. The usual answers are tmux plus a supervisor, or a custom agent built on the SDK. This repo shows a smaller path:

```
Telegram ──► official plugin (MCP channel) ──► claude (interactive, in a `script` pty) ──► reply tool ──► Telegram
                                                   ▲
                       managed policy (root-owned, highest precedence) + hooks (audit, alerts)
```

- The `script` command provides the pty. No tmux, no supervisor process.
- The container restart policy is the watchdog: if `claude` exits, the container exits and restarts.
- Behavior is controlled with `.md` files (`CLAUDE.md`) and one managed settings file.

New here? Follow [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md): from nothing to an agent that answers, step by step.

## Quick start (Docker)

1. Create a bot with [@BotFather](https://t.me/BotFather) and get your numeric Telegram user id.
2. Get a credential: run `claude setup-token` on your machine to use your Claude subscription, or create an [Anthropic API key](https://console.anthropic.com/) (Channels need claude.ai or Console API-key auth).
3. Configure and run:

```bash
cp .env.example .env   # then fill in one credential and the two Telegram values
```

```bash
docker compose up -d --build
```

4. Message your bot. The first build takes several minutes.

Use a **new bot token**. Two processes polling the same bot conflict (HTTP 409).

## Deploy on Railway

See [docs/DEPLOY-RAILWAY.md](docs/DEPLOY-RAILWAY.md). The Dockerfile deploys as is; you add one volume at `/data` and three variables.

## Configuration

| Variable | Required | Purpose |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | one of the two | Claude subscription (Pro/Max) token from `claude setup-token`; uses the subscription's limits |
| `ANTHROPIC_API_KEY` | one of the two | Console API key, billed per use. Takes precedence if both are set |
| `TELEGRAM_BOT_TOKEN` | yes | Bot token, read by the official plugin |
| `OWNER_TELEGRAM_ID` | yes | Only this user can talk to the bot (allowlist) |
| `TELEGRAM_GROUP_IDS` | no | Telegram groups the bot may take part in (see [docs/GROUPS.md](docs/GROUPS.md)). Unset = private chat with the owner only |
| `TELEGRAM_GROUP_SENDERS` | no | Extra user or bot ids the bot listens to in those groups, besides the owner |
| `RCLONE_CONF` | no | Storage credentials for the nightly encrypted backup (see [docs/BACKUP.md](docs/BACKUP.md), which lists the other backup variables) |
| `BACKUP_AGE_KEY` | no | Only to restore: the private key, on a new empty volume. Remove it afterwards |
| `PEER_PUBLIC_KEYS` | no | Public SSH keys of fellow agents allowed to read this agent's screen (see [docs/PEERS.md](docs/PEERS.md)). Unset = no SSH server |
| `PEER_SSH_KEY` | no | Private SSH key this agent uses to look at fellow agents |
| `SCREEN_MIRROR` | no | Seconds between copies of the readable screen to the service log (e.g. `30`). Unset = off. The screen contains your conversation: enable only to debug |
| `CLAUDE_FLAGS` | no | Extra `claude` flags. Empty = default interactive mode (auto mode) |
| `ANTHROPIC_MODEL` | no | Pin the model. Unpinned, the model can differ between sessions |
| `TZ` | no | Container time zone |

The policy lives in [`policy/managed-settings.json`](policy/managed-settings.json). Edit it, rebuild, and it is loaded as a root-owned managed setting that the agent cannot change.

## Security model

Defense in depth, each layer using an official mechanism:

1. **Sender allowlist**: the plugin only accepts the configured Telegram user.
2. **Managed policy**: root-owned file; `deny` rules for credentials and for writes to the config, plugin and policy paths.
3. **Permission classifier (auto mode)**: reviews every action that is not explicitly allowed.
4. **Never waits for a person**: `permissions.denyInsteadOfPrompting` denies any call that would need an approval prompt; the agent is told and carries on. Nothing is ever allowed by it.
5. **Hooks**: every tool call, failure and denial adds one short line to `/data/audit.jsonl` (when, event, tool, mode, error; the last 10000 are kept, the full detail is in the session transcript); credential failures alert the owner on Telegram.
6. **Container**: non-root user (uid 1001), one volume, no secrets baked into the image.

Known limits (read before trusting it):

- `deny` rules are enforced for Claude's file tools. For the shell it depends on how a command is written: Claude Code recognises some commands (`cat`, redirections) but not a script or `grep -r` that opens a file itself. Treat the shell as unconstrained. A hard floor needs OS-level controls (file permissions, sandbox).
- **Security level on Railway: soft floor only.** There is no hard isolation for the shell: it blocks the user namespaces that the env scrub and the sandbox need, so a shell command can read the tokens. Only the `deny` rules and the auto mode `hard_deny` rule stand in the way (soft layers). A host that allows namespaces is needed for a hard floor: see [Hardening by host](docs/THREAT-MODEL.md#hardening-by-host).
- There is **no egress control** by default. An allowed shell can reach any host. A network allowlist is not included yet.
- The alert hook is reactive: it fires when a turn fails, not on a timer.

The full picture is in the [threat model](docs/THREAT-MODEL.md). Report vulnerabilities as described in [SECURITY.md](SECURITY.md). For what a customer would download versus what runs here, see [lab image and product image](docs/PRODUCT-IMAGE.md).

## Repository layout

```
Dockerfile                    image: Claude Code + official Telegram plugin, non-root
compose.yml                   local run, one volume at /data
bin/start.sh                  entrypoint: seed config, allowlist, pre-accept, run claude in a pty
bin/screen.sh                 readable view of the Claude screen log
bin/job.sh                    runs one scheduled prompt and delivers the answer (see docs/CRON.md)
bin/config.sh                 settings the agent changes itself when the owner asks (see docs/SETTINGS.md)
bin/peer.sh                   what fellow agents may do over SSH: look, and set groups (see docs/PEERS.md)
bin/backup.sh                 nightly encrypted backup, and restore onto an empty volume (see docs/BACKUP.md)
bin/watchdog.sh               tells the owner and restarts when Claude runs but the Telegram plugin is gone
bin/notify.sh                 one Telegram message to the owner
bin/denials.sh                loaded policy + tool errors from the latest session
policy/managed-settings.json  the managed policy and hooks
bin/system.cron               the image's own scheduled jobs (daily recycle)
policy/CLAUDE.md              what the agent is told about its limits (managed: root-owned, updated with the image)
tests/                        acceptance tests (run inside the built image) and docs-vs-code checks
docs/                         architecture, findings, deployment, threat model, secrets, repository settings, releasing
.github/                      CI, issue and PR templates, Dependabot
```

## Contributing

Questions and bug reports: open an issue. To contribute, see [CONTRIBUTING.md](CONTRIBUTING.md). The project goal is the smallest amount of code that is safe; a change that adds code must say what it removes or why nothing smaller works.

## License

[Apache-2.0](LICENSE)
