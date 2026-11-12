# Threat model

Status: lab / alpha. Not audited. Evidence labels as in [FINDINGS.md](FINDINGS.md): **Lab** (observed), **Docs**, **Code**, **Open** (not verified).

## What is protected

- The Claude credential (`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`) and the Telegram bot token.
- The owner's conversations, the agent's memory and transcripts (`/data`).
- Whatever the agent can reach from its container: the volume and the network.

## Trust

- **Trusted:** the owner (one Telegram user id) and the super-users the owner names, the Claude Code binary and the official Telegram plugin (official sources, Claude Code version pinned), and the host that runs the container.
- **Untrusted:** everyone else who messages the bot, and **any content the agent reads**: web pages, files, messages, tool output. Content can carry instructions (prompt injection). The model's own judgment is a layer, not a guarantee.

## Threats and what stands in the way

| Threat | What stands in the way | Evidence | Residual risk |
|---|---|---|---|
| A stranger messages the bot | Allowlist with the owner id, written by `start.sh` | Code, tested | `/start` still shows pairing instructions although pairing is off (Code) |
| A member of an enabled group tells the agent what to do | The agent is told its owner's id at every start and that only the owner and the super-users (named by the owner or by another super-user) give instructions; the policy's denied tools and paths apply to everyone | Instruction, plus code for the hard limits | No lock, except for installs (next row): every member's text enters the session, and a persistent member can try to talk the agent round. Only enable groups whose members are trusted ([GROUPS.md](GROUPS.md)) |
| Someone who is not a super-user talks the agent into installing a package, a tool or a skill | The install lock: a `UserPromptSubmit` hook opens it for one turn only when the Telegram message is from the owner or a super-user. It reads the sender from the plugin's own first line, whose values cannot hold a quote; a turn with a second `<channel` tag (typed, or two messages at once) gets nothing. A `PreToolUse` hook refuses install commands and writes to `/data/bin`, `/data/tools` and the skills folders while it is closed. Scheduled jobs and the dream never get it. Each install goes to `/data/tools.json` and the owner is told | Code, tested (`tests/install_test.sh`); Open: not tried on a live agent, and the exact prompt text the hook receives for a channel message was read from the Claude Code binary, not observed | A pattern, not a sandbox: a command written to avoid it (a script file, an encoded string, `python -m` with an odd spelling, another package manager) installs anyway, and the agent can open the lock file or edit `/data/tools.json` the same way, since hooks and agent are one user. A message that arrives while a super-user's turn is still running may be read inside that turn. If Claude Code changes the channel tag, the lock stays closed (fails safe). `start.sh` replays only lines of the form `uv pip install …`, `uv tool install …`, `bun add -g …`, so a forged record can at most reinstall packages |
| The agent is talked into attaching a key or a credential to a reply | A `PreToolUse` hook on the reply tool: attachments only from `/data/workspace`, `/tmp` and the Telegram inbox, after resolving `..` and links | Code, tested | The agent can still copy a file into the workspace with the shell first; that step is reviewed by auto mode, not blocked |
| Injected content makes the agent leak a credential | Auto-mode classifier with a `hard_deny` rule on credentials; `deny` rules for `.env`, `printenv`, `env`, `/proc`; credentials for the plugin and the alert hook come from a 600 file | Lab: the agent refused `printenv` and "show me your token", by its own judgment; the rules were not exercised | **High where the host blocks user namespaces (Railway):** a shell command can read the environment and files. No egress control |
| An unattended agent stalls or does something unsafe | `denyInsteadOfPrompting` (a call that would prompt is denied, the agent carries on); classifier; non-root user; audit log | Docs; Lab for the stall and its alert; Open for `denyInsteadOfPrompting` on Railway | The audit log is written after the fact |
| The credential dies and nobody notices | `StopFailure` hook alerts the owner on Telegram | Lab (expired key) | Reactive: fires when a turn fails, not on a timer |
| Tampered image, CLI or plugin | Claude Code version pinned; installer and marketplace are the official ones; CI builds the image and runs tests in it | Docs | **The plugin is not pinned** (the base image is pinned by digest; SBOM, provenance and signing are in CI but the release is locked) |
| Two processes poll one bot token (HTTP 409) | A dedicated token per deployment, documented | Lab | `start.sh` asks Telegram (`getMe`) once and stops on HTTP 401; it cannot see a second poller (HTTP 409 only appears while polling): Open |
| Container or host compromise | Non-root `agent` (uid 1001); no extra capabilities requested | Code | On Railway the entrypoint starts as root only to fix `/data` ownership, then drops to uid 1001 |
| Data at rest | Volume access is the host's | Docs | Transcripts, memory and the token file are not encrypted by this project |

## What this project does not claim

- It is **not a sandbox**: a shell command can do what the container's user can do.
- It is **single-tenant**: one owner per deployment.
- A Claude **subscription** credential is for individual use; a service for third parties should use API keys or each customer's own subscription (check Anthropic's current terms).
- It has not been audited and is not production-grade.

## Hardening by host

| Host | Available |
|---|---|
| Railway container | Soft layers only (policy rules, classifier). The platform blocks user namespaces, so the env scrub and the sandbox cannot run (Lab) |
| A VM or server that allows namespaces | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, the official sandbox, an egress firewall (Open: not tested here). Check first: `unshare -U true` must succeed inside the container, as the unprivileged user |

See [SECRETS.md](SECRETS.md) for rotation and [REPO-SETTINGS.md](REPO-SETTINGS.md) for the repository's own protections.
