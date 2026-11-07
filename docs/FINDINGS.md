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

## What does not, or needs care

| Finding | Evidence |
|---|---|
| Auto mode can still stall on a permission prompt (for example a first Read outside the working directories). Nobody sees it unless they open the screen log. | Lab |
| A broad `Edit(//data/config/**)` deny also blocked the agent's own memory directory. Deny specific files instead. | Lab |
| `deny` rules block file tools, not Bash. | Docs, Lab |
| A `Read` deny rule also prevented writing the same file. Whether `Read(**/.env)` blocked reads is **not** settled: the audit log shows two reads of `/data/workspace/.env`, and the hook type that logged them was not identified. | Lab (unresolved) |
| The model is not pinned: different sessions ran different Opus versions. Set `ANTHROPIC_MODEL`. | Lab |
| While the machine is suspended nothing runs. A background timer that was due during suspension fired on wake. | Lab (inferred) |
| `/start` on the bot shows pairing instructions even when the allowlist is active. | Code |

## Open items

- Hard floor for the shell (sandbox or filesystem permissions).
- Egress allowlist (a firewall needs `NET_ADMIN`; unverified on Railway).
- Environment scrubbing while the bot token sits in a plugin file.
- Slack (there is no official Slack channel plugin; Claude Tag is a different product).
- Two users and simultaneous messages.
- 24-hour soak test with a non-expiring key and memory growth.
- Whether adding `/tmp` to `permissions.additionalDirectories` removes the stall prompt.
- Preflight check for a reused bot token (`getMe` and HTTP 409).
