#!/usr/bin/env bash
# Runs interactive Claude Code (the mode that wakes up on channel events) inside a minimal pty (`script`), without tmux.
# If claude dies, the container exits and the restart policy brings it back. There is no watchdog process.
set -euo pipefail
# Railway mounts volumes owned by root (it runs this as root via RAILWAY_RUN_UID=0): fix ownership, then drop to agent.
if [ "$(id -u)" = 0 ]; then
  mkdir -p /data/workspace && chown 1001:1001 /data /data/workspace
  exec setpriv --reuid=1001 --regid=1001 --init-groups env HOME=/home/agent "$0" "$@"
fi
# A token copied from a phone often carries line breaks; tokens never contain whitespace, so strip it.
# Then log a sanity check without printing any part of it.
T="${CLAUDE_CODE_OAUTH_TOKEN:-}"; T="${T//[[:space:]]/}"; [ -z "$T" ] || export CLAUDE_CODE_OAUTH_TOKEN="$T"; [ -z "$T" ] || echo "oauth token: ${#T} chars, starts with sk-ant-oat01-: $([[ "$T" == sk-ant-oat01-* ]] && echo yes || echo NO), whitespace: $([[ "$T" =~ [[:space:]] ]] && echo YES || echo no)" >&2
CFG=/data/config; TG=$CFG/channels/telegram; WS=/data/workspace
mkdir -p "$WS" "$TG"
cp -rn /opt/seed/config/. "$CFG"/
# Only the owner can talk to the bot (first start only; afterwards the owner edits it on the volume).
[ -f "$TG/access.json" ] || printf '{"dmPolicy":"allowlist","allowFrom":["%s"],"groups":{},"pending":{}}\n' "$OWNER_TELEGRAM_ID" > "$TG/access.json"
# The plugin and the alert hook read the bot credentials from this file, so the environment can be scrubbed.
(umask 077; printf 'TELEGRAM_BOT_TOKEN=%s\nOWNER_TELEGRAM_ID=%s\n' "$TELEGRAM_BOT_TOKEN" "$OWNER_TELEGRAM_ID" > "$TG/.env")
# Can bubblewrap (needed by CLAUDE_CODE_SUBPROCESS_ENV_SCRUB on Linux) isolate a process on this host?
b1=$(bwrap --ro-bind / / --dev /dev --unshare-pid --proc /proc true 2>&1) && b1=ok
b2=$(bwrap --ro-bind / / --dev /dev --unshare-pid --bind /proc /proc true 2>&1) && b2=ok
echo "bwrap probe: fresh /proc: ${b1:0:120}; existing /proc: ${b2:0:120}" >&2
# Nobody is at the screen: pre-accept onboarding, the API key (if one is used) and trust for the workspace folder.
# Auth: ANTHROPIC_API_KEY (Console, billed per use) or CLAUDE_CODE_OAUTH_TOKEN (subscription, from `claude setup-token`).
[ -s "$CFG/.claude.json" ] || echo '{}' > "$CFG/.claude.json"
KEY="${ANTHROPIC_API_KEY:-}"
jq --arg k "${KEY: -20}" --arg ws "$WS" \
  '.hasCompletedOnboarding=true | (if $k=="" then . else .customApiKeyResponses.approved=(((.customApiKeyResponses.approved//[])-[$k])+[$k]) end) | .projects[$ws].hasTrustDialogAccepted=true | .projects[$ws].hasCompletedProjectOnboarding=true' \
  "$CFG/.claude.json" > "$CFG/.claude.json.tmp" && mv "$CFG/.claude.json.tmp" "$CFG/.claude.json"
cd "$WS"
# Railway has no shell into the container: mirror the readable screen to the service log whenever it changes.
(prev=; while sleep 30; do cur=$(screen.sh 25 2>/dev/null || true); [ "$cur" = "$prev" ] || { printf '%s\n----\n' "$cur" >&2; prev=$cur; }; done) &
# script = the pty; tail keeps stdin open; stty avoids a 0x0 terminal. The screen is kept in /data/tui.log (see screen.sh).
tail -f /dev/null | script -qfc "stty cols 120 rows 40; exec claude --channels plugin:telegram@claude-plugins-official ${CLAUDE_FLAGS:-}" /data/tui.log > /dev/null
echo "claude exited" >&2; exit 1
