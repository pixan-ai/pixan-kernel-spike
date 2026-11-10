# Security policy

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: the **Security** tab, then **Report a vulnerability**. Please do not open a public issue with details. Include steps to reproduce, the impact you observed and the version (commit or tag).

If that option is not available to you, open a public issue that says only "I have a security report, please contact me", with no technical details, and a maintainer will arrange a private channel.

## What to expect

- We acknowledge a report within 7 days and send a first assessment within 14 days.
- We fix confirmed vulnerabilities on `main` and, once tagged releases exist, in the latest release.
- We disclose in coordination with you, normally when a fix is released or after 90 days, whichever comes first, and credit you if you wish.
- Good-faith research on your own deployment is welcome. Please do not test deployments you do not own, and do not access, change or copy other people's data.

## Supported versions

Only the latest commit on `main` and, once there is one, the latest tagged release receive fixes.

## Scope

In scope: the Dockerfile, `bin/*`, `policy/managed-settings.json`, the CI workflows and the documentation claims about them.
Out of scope: vulnerabilities in Claude Code or the official Telegram plugin (report those to Anthropic).

## Security level by host

- **Railway (the reference deployment): soft floor only.** Policy rules and the auto-mode classifier are the only barriers; the platform blocks the user namespaces that the environment scrub and the sandbox need, so a shell command run by the agent can read the container's environment. Do not give such a deployment credentials you cannot afford to rotate. Verified in the lab; see [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md).
- **A VM, server or local Docker that allows user namespaces:** a hard floor is possible (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, Claude Code's sandbox, an egress firewall). Not tested in this project yet; follow Anthropic's current documentation and treat it as unverified until you have tried it.

## Handling secrets

- Secrets are passed as environment variables at run time and are never baked into the image. See [docs/SECRETS.md](docs/SECRETS.md) for the inventory and how to rotate them.
- `.env` is git-ignored. Only `.env.example` with placeholders is committed.
- Rotate any credential that was pasted into a chat, a log or a screenshot.

## Known limitations

See the [threat model](docs/THREAT-MODEL.md), "Security model" in the [README](README.md) and [docs/FINDINGS.md](docs/FINDINGS.md). In particular, `deny` rules do not reliably cover the shell, and there is no egress control yet.
