#!/usr/bin/env bash
# Runs interactive Claude Code (the mode that wakes up on channel events) inside a minimal pty (`script`), without tmux.
# If claude dies, the container exits and the restart policy brings it back. There is no watchdog process.
set -euo pipefail
: "${TELEGRAM_BOT_TOKEN:?is not set}" "${OWNER_TELEGRAM_ID:?is not set}"
# Without a Claude credential, claude would sit on a login screen nobody sees: fail fast instead.
[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ] || { echo "missing CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY" >&2; exit 1; }
# Railway mounts volumes owned by root (it runs this as root via RAILWAY_RUN_UID=0): fix ownership, then drop to agent.
if [ "$(id -u)" = 0 ]; then
  mkdir -p /data/workspace && chown 1001:1001 /data /data/workspace
  exec setpriv --reuid=1001 --regid=1001 --init-groups env HOME=/home/agent "$0" "$@"
fi
# A token copied from a phone often carries line breaks; tokens never contain whitespace, so strip it.
# Then log a sanity check without printing any part of it.
T="${CLAUDE_CODE_OAUTH_TOKEN:-}"; T="${T//[[:space:]]/}"; [ -z "$T" ] || export CLAUDE_CODE_OAUTH_TOKEN="$T"; [ -z "$T" ] || echo "oauth token: ${#T} chars, starts with sk-ant-oat01-: $([[ "$T" == sk-ant-oat01-* ]] && echo yes || echo NO)" >&2
CFG=/data/config; TG=$CFG/channels/telegram; WS=/data/workspace
# Backups (docs/BACKUP.md): the storage credentials go to a private file. An empty volume with BACKUP_AGE_KEY set is restored from the newest backup.
(umask 077; mkdir -p /data/ssh; [ -z "${RCLONE_CONF:-}" ] || printf '%s\n' "$RCLONE_CONF" > /data/ssh/rclone.conf)
[ -e "$CFG/.claude.json" ] || [ -z "${BACKUP_AGE_KEY:-}" ] || backup.sh restore || echo "restore failed: starting with an empty volume" >&2
mkdir -p "$WS" "$TG/inbox"
cp -rn /opt/seed/config/. "$CFG"/
# The plugin must run from the volume copy (the one the policy protects), and a new image must replace it:
# its registry files carry the absolute build path, so copy it fresh at every start and point them at the volume.
rm -rf "$CFG/plugins" && cp -r /opt/seed/config/plugins "$CFG/" && sed -i "s#/opt/seed/config#$CFG#g" "$CFG"/plugins/*.json
# Who may talk to the bot: the owner in private, plus everyone in the groups listed in /data/settings. That file is seeded
# from the variables and then kept by the agent itself (config.sh), so the owner never has to come back to the host.
# shellcheck disable=SC2086  # word splitting on purpose: one line per id
{ cat /data/settings 2> /dev/null || true; printf 'group %s\n' ${TELEGRAM_GROUP_IDS:-}; } | grep ' .' | sort -u > /data/settings.tmp || true
mv /data/settings.tmp /data/settings
# The plugin and the alert hook read the bot credentials from this file (ready for an env scrub on hosts that allow it).
(umask 077; printf 'TELEGRAM_BOT_TOKEN=%s\nOWNER_TELEGRAM_ID=%s\n' "$TELEGRAM_BOT_TOKEN" "$OWNER_TELEGRAM_ID" > "$TG/.env")
config.sh apply
# A revoked or mistyped bot token would leave the bot mute with no error anywhere: ask Telegram once (the answer also tells the agent its own bot name, see the SessionStart hook). Only a clear 401 stops the start; a network hiccup does not. The URL goes through stdin so the token is not in a process list.
code=$(printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$TELEGRAM_BOT_TOKEN" | curl -sS -K - -o "$TG/me.json" -w '%{http_code}' -m 10 2>/dev/null || true)
[ "$code" != 401 ] || { echo "Telegram rejected TELEGRAM_BOT_TOKEN (HTTP 401): create a new one with BotFather" >&2; exit 1; }
unset TELEGRAM_BOT_TOKEN RCLONE_CONF BACKUP_AGE_KEY  # from here on only private files hold them (the plugin, the hooks and the scripts read those)
# Nobody is at the screen: pre-accept onboarding, the API key (if one is used) and trust for the workspace folder.
# Auth: ANTHROPIC_API_KEY (Console, billed per use) or CLAUDE_CODE_OAUTH_TOKEN (subscription, from `claude setup-token`).
[ -s "$CFG/.claude.json" ] || echo '{}' > "$CFG/.claude.json"
KEY="${ANTHROPIC_API_KEY:-}"
jq --arg k "${KEY: -20}" --arg ws "$WS" \
  '.hasCompletedOnboarding=true | (if $k=="" then . else .customApiKeyResponses.approved=(((.customApiKeyResponses.approved//[])-[$k])+[$k]) end) | .projects[$ws].hasTrustDialogAccepted=true | .projects[$ws].hasCompletedProjectOnboarding=true' \
  "$CFG/.claude.json" > "$CFG/.claude.json.tmp" && mv "$CFG/.claude.json.tmp" "$CFG/.claude.json"
cd "$WS"
# Opt-in via SCREEN_MIRROR, the seconds between copies: copy the readable screen to the service log when it changes. Off by default: the screen holds the owner's conversation.
[ -z "${SCREEN_MIRROR:-}" ] || (prev=; while sleep "$SCREEN_MIRROR"; do cur=$(screen.sh 25 2>/dev/null || true); [ "$cur" = "$prev" ] || { printf '%s\n----\n' "$cur" >&2; prev=$cur; }; done) &
# script = the pty; tail keeps stdin open; stty avoids a 0x0 terminal. The screen is kept in /data/tui.log (see screen.sh).
# Opt-in peer view (docs/PEERS.md): fellow agents whose public keys are listed may read this agent's screen; PEER_SSH_KEY lets this one look at others.
(umask 077; mkdir -p /data/ssh; [ -z "${PEER_SSH_KEY:-}" ] || printf '%s\n' "$PEER_SSH_KEY" > /data/ssh/peer_key)
[ -z "${PEER_PUBLIC_KEYS:-}" ] || peer.sh serve
# The audit log keeps its last 10000 events and the record of job deliveries its last 500 (the screen log is overwritten at every start).
[ ! -f /data/audit.jsonl ] || { tail -n 10000 /data/audit.jsonl > /data/audit.tmp && mv /data/audit.tmp /data/audit.jsonl; }
[ ! -f "$WS/sent.jsonl" ] || { tail -n 500 "$WS/sent.jsonl" > "$WS/sent.tmp" && mv "$WS/sent.tmp" "$WS/sent.jsonl"; }
# Scheduled jobs: config.sh apply (above) built /data/cron/crontab from the image's jobs and the agent's. If the last heartbeat is old, say so: jobs due meanwhile did not run.
[ ! -e /data/cron/alive ] || [ -e /data/idle ] || (( $(date +%s) - $(stat -c %Y /data/cron/alive) < 300 )) || notify.sh "Back online. I was down from $(date -r /data/cron/alive '+%F %H:%M') to $(date '+%H:%M'); jobs scheduled in between did not run." || true
(while touch /data/cron/alive; do sleep 30; done) &
supercronic -quiet -inotify /data/cron/crontab &
# Opt-in sleep (IDLE_SLEEP_MINUTES, docs/SLEEP.md): after that long without activity Claude is stopped and doorbell.sh waits for
# Telegram to announce a message; then Claude starts again and continues the conversation. /data/idle marks "asleep".
while :; do
  T0=$SECONDS
  [ ! -e /data/idle ] || [ -z "${IDLE_SLEEP_MINUTES:-}" ] || doorbell.sh || sleep 30
  rm -f /data/idle
  [ -z "${IDLE_SLEEP_MINUTES:-}" ] || (while sleep 30; do (( SECONDS - T0 < IDLE_SLEEP_MINUTES * 60 )) && continue
      [ -n "$(find "$CFG/projects" -name '*.jsonl' -newermt "-${IDLE_SLEEP_MINUTES} minutes" 2> /dev/null | head -1)" ] || { touch /data/idle; pkill -x script; break; }; done) &
  # A restart continues the last conversation. If claude then dies within a minute, the next start opens a fresh one instead of looping on a session it cannot load.
  C=; ls "$CFG"/projects/*/*.jsonl > /dev/null 2>&1 && [ ! -e /data/fresh ] && C=--continue; rm -f /data/fresh
  tail -f /dev/null | script -qfc "stty cols 120 rows 40; exec claude $C --channels plugin:telegram@claude-plugins-official ${CLAUDE_FLAGS:-}" /data/tui.log > /dev/null || true  # tail dies of SIGPIPE when claude exits; still report it below
  [ -e /data/idle ] || break
done
[ -z "$C" ] || (( SECONDS - T0 > 60 )) || touch /data/fresh
(( SECONDS - T0 > 60 )) || sleep 60  # crash-loop brake: do not hammer the APIs with restarts
echo "claude exited" >&2; exit 1
