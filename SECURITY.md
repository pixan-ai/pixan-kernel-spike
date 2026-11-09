# Security policy

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting (Security tab, "Report a vulnerability") for this repository. Include steps to reproduce and the impact you observed.

## Scope

In scope: the Dockerfile, `bin/*`, `policy/managed-settings.json` and the documentation claims about them.
Out of scope: vulnerabilities in Claude Code or the official Telegram plugin (report those to Anthropic).

## Handling secrets

- Secrets (`ANTHROPIC_API_KEY`, `TELEGRAM_BOT_TOKEN`) are passed as environment variables at run time and are never baked into the image.
- `.env` is git-ignored. Only `.env.example` with placeholders is committed.
- Rotate any credential that was pasted into a chat, a log or a screenshot.

## Known limitations

See "Security model" in the [README](README.md) and [docs/FINDINGS.md](docs/FINDINGS.md). In particular, deny rules do not cover the shell, and there is no egress control yet.
