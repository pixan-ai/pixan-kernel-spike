# Contributing

## Principles

1. **Official components only.** Prefer a documented Claude Code setting, hook or plugin over new code.
2. **Smallest code that is safe.** A change that adds code says what it removes, or why nothing smaller works.
3. **Evidence over claims.** A security or behavior claim in the docs needs a label from [docs/FINDINGS.md](docs/FINDINGS.md): Lab, Docs, Code or Open.
4. **Surgical changes.** Touch only what the change requires.

## Foundations

- **Tests:** [Acceptance Pipeline Specification](https://github.com/unclebob/Acceptance-Pipeline-Specification) (Uncle Bob). A test exercises behavior and must be able to fail; CI never skips a test silently.
- **Execution:** [Karpathy guidelines](https://github.com/multica-ai/andrej-karpathy-skills): think before coding, simplicity first, surgical changes, goal-driven execution.
- **Current docs, not memory:** check Claude Code, Railway and Telegram behavior against current documentation (for agents: [Context7](https://context7.com)) before relying on it.

## Before you open a pull request

```bash
shellcheck bin/*.sh tests/*.sh
jq empty policy/managed-settings.json
hadolint Dockerfile
docker build -t pixan-kernel-spike .
bash tests/docs_test.sh
for t in start tools policy cron peer config backup sleep dream install; do
  docker run --rm --user 0 --entrypoint bash -v "$PWD/tests:/tests:ro" pixan-kernel-spike "/tests/${t}_test.sh" || break
done
```

A change to `bin/` comes with a test in `tests/` that runs the script and checks what it does (exit code, files, output). Break the value the test guards and make sure it turns red.

CI runs the same checks. Never commit `.env` or any real credential.

## Commit messages

Imperative, one subject line, explain why in the body when it is not obvious.
