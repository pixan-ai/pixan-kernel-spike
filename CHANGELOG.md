# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/) once the first release is tagged.

## [Unreleased]

### Changed

- Fix: the Telegram plugin ran from the image's build path (its registry files hold absolute paths), outside the policy's protection, and a newer image could not replace the copy on the volume. Every start now copies the plugin to the volume and points its registry there.
- Fix: the agent could not see photos or files sent on Telegram. They land in the plugin's inbox, outside the workspace, and the first read was denied. The inbox is now an additional working directory (still not writable by the agent).
- The agent's instructions moved to the managed location (`/etc/claude-code/CLAUDE.md`): root-owned, updated with every image, not editable by the agent. The copy seeded earlier in `/data/workspace` is no longer written.
- The Dockerfile has two targets: `base` (no Anthropic software, the only publishable one) and `agent` (default; adds Claude Code and the plugin). The release workflow pushes `base` only and CI verifies it contains no Claude Code.
- Docs: the security level is stated per host (**Railway: soft floor only**) in README and SECURITY.md, with the namespace check for hosts that can do better.
- The base image is pinned by digest; a test fails on an unpinned `FROM`.
- Start-up asks Telegram (`getMe`) once and fails fast on HTTP 401 (revoked or mistyped bot token) instead of leaving the bot mute. A network error does not stop the start.

### Added

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
