# Contributing

## Principles

1. **Official components only.** Prefer a documented Claude Code setting, hook or plugin over new code.
2. **Smallest code that is safe.** A change that adds code says what it removes, or why nothing smaller works.
3. **Evidence over claims.** A security or behavior claim in the docs needs a label from [docs/FINDINGS.md](docs/FINDINGS.md): Lab, Docs, Code or Open.
4. **Surgical changes.** Touch only what the change requires.

## Before you open a pull request

```bash
shellcheck bin/*.sh
jq empty policy/managed-settings.json
hadolint Dockerfile
docker build -t pixan-kernel-spike .
```

CI runs the same checks. Never commit `.env` or any real credential.

## Commit messages

Imperative, one subject line, explain why in the body when it is not obvious.
