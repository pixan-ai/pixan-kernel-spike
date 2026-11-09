# Threat model

Status: lab / alpha. Not audited. Evidence labels as in [FINDINGS.md](FINDINGS.md): **Lab** (observed), **Docs**, **Code**, **Open** (not verified).

## What is protected

- The Claude credential (`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`) and the Telegram bot token.
- The owner's conversations, the agent's memory and transcripts (`/data`).
- Whatever the agent can reach from its container: the volume and the network.

## Trust

- **Trusted:** the owner (one Telegram user id), the Claude Code binary and the official Telegram plugin (official sources, Claude Code version pinned), and the host that runs the container.
- **Untrusted:** everyone else who messages the bot, and **any content the agent reads**: web pages, files, messages, tool output. Content can carry instructions (prompt injection). The model's own judgment is a layer, not a guarantee.

## Threats and what stands in the way

| Threat | What stands in the way | Evidence | Residual risk |
|---|---|---|---|
| A stranger messages the bot | Allowlist with the owner id, written by `start.sh` | Code, tested | `/start` still shows pairing instructions although pairing is off (Code) |
| Injected content makes the agent leak a credential | Auto-mode classifier with a `hard_deny` rule on credentials; `deny` rules for `.env`, `printenv`, `env`, `/proc`; credentials for the plugin and the alert hook come from a 600 file | Lab: the agent refused `printenv` and "show me your token", by its own judgment; the rules were not exercised | **High where the host blocks user namespaces (Railway):** a shell command can read the environment and files. No egress control |
| An unattended agent stalls or does something unsafe | `denyInsteadOfPrompting` (a call that would prompt is denied, the agent carries on); classifier; non-root user; audit log | Docs; Lab for the stall and its alert; Open for `denyInsteadOfPrompting` on Railway | The audit log is written after the fact |
| The credential dies and nobody notices | `StopFailure` hook alerts the owner on Telegram | Lab (expired key) | Reactive: fires when a turn fails, not on a timer |
| Tampered image, CLI or plugin | Claude Code version pinned; installer and marketplace are the official ones; CI builds the image and runs tests in it | Docs | **The plugin and the base image tag are not pinned** (digest pin, SBOM, provenance and signing are planned: Open) |
| Two processes poll one bot token (HTTP 409) | A dedicated token per deployment, documented | Lab | No preflight check yet (Open) |
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
| A VM or server that allows namespaces | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, the official sandbox, an egress firewall (Open: not tested here) |

See [SECRETS.md](SECRETS.md) for rotation and [REPO-SETTINGS.md](REPO-SETTINGS.md) for the repository's own protections.
