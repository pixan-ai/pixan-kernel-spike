# Two targets. `base`: everything this project owns, with no Anthropic software; the only one that may be published.
# `agent` (the default): base + Claude Code + the official Telegram channel plugin; built by whoever runs it, never published.
# No tmux, no supervisor: `script` provides the pty, and the container restart policy is the watchdog.
FROM oven/bun:1-debian@sha256:93d5032fe06d163427822dc1598f420363759bb18155c9cc90eb1be05a64a19e AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Unpinned apt packages on purpose: pinned Debian versions vanish from the mirror; Dependabot bumps the base image.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates git jq \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1001 agent && mkdir -p /data /opt/seed && chown agent:agent /data /opt/seed

# Managed policy: owned by root, not editable by the agent, highest precedence in Claude Code.
COPY policy/ /etc/claude-code/
COPY --chmod=755 bin/ /usr/local/bin/

USER 1001
ENV DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=/data/config TELEGRAM_STATE_DIR=/data/config/channels/telegram CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false
WORKDIR /data/workspace
ENTRYPOINT ["/usr/local/bin/start.sh"]

FROM base AS agent
ARG CLAUDE_CODE_VERSION=2.1.319
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}" \
 && /home/agent/.local/bin/claude --version
ENV PATH="/home/agent/.local/bin:${PATH}"

# The official plugin is baked into /opt/seed/config; start.sh copies it to the volume if missing.
RUN export CLAUDE_CONFIG_DIR=/opt/seed/config && mkdir -p "$CLAUDE_CONFIG_DIR" \
 && claude plugin marketplace add anthropics/claude-plugins-official \
 && claude plugin install telegram@claude-plugins-official \
 && for d in /opt/seed/config/plugins/cache/claude-plugins-official/telegram/*/; do bun install --cwd "$d"; done
