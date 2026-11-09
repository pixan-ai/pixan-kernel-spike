# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/) once the first release is tagged.

## [Unreleased]

### Changed

- Docs: the security level is stated per host (**Railway: soft floor only**) in README and SECURITY.md, with the namespace check for hosts that can do better.

### Added

- Claude Code on Telegram in one container: the official harness in a `script` pty, the official Telegram channel plugin, a root-owned managed policy.
- Credential: a Claude subscription token (`CLAUDE_CODE_OAUTH_TOKEN`) or an API key (`ANTHROPIC_API_KEY`).
- Railway support: volume ownership handled by the entrypoint (`RAILWAY_RUN_UID=0`), screen mirrored to the service log.
- Policy: `denyInsteadOfPrompting` so an unattended agent never waits for a person; deny rules and an auto-mode rule against leaking credentials; hooks that audit and alert the owner on Telegram.
- Acceptance tests for the entrypoint, the diagnostic tools, the policy and the documentation, run in CI inside the built image.
- Documentation: findings, architecture, Railway deployment, threat model, secrets, repository settings.

### Fixed

- The entrypoint now exits with status 1 and says so when Claude exits (it used to exit with 141).
- The entrypoint fails fast, naming the missing variable, when no Claude credential is set.
- A token copied from a phone with line breaks is cleaned before use.
