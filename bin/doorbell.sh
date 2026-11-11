#!/usr/bin/env bash
# Asleep (docs/SLEEP.md): Claude is stopped and nothing here talks to the network, so a host that suspends idle
# containers stops billing memory. Telegram is told to call this service when a message arrives; this script returns
# when one is waiting. The message itself is never read here: the official plugin collects it by polling, once.
set -uo pipefail
TG=/data/config/channels/telegram; S=/data/ssh/doorbell-secret; B=$(dirname "$(readlink -f "$0")")
# shellcheck source=/dev/null
. $TG/.env
api() { printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$TELEGRAM_BOT_TOKEN" "$1" | curl -sS -m 15 -K - "${@:2}"; }
waiting() { [ "$(api getWebhookInfo | jq -r '.result.pending_update_count // 0')" -gt 0 ]; }
url=${DOORBELL_URL:-https://${RAILWAY_PUBLIC_DOMAIN:?set DOORBELL_URL: sleeping needs a public address for Telegram to call}}
[ -s $S ] || (umask 077; head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' > $S)
# A suspended container runs no nightly backup: make one now if the last is older than 20 hours.
[ -n "$(find /data/cron/last-backup -mmin -1200 2> /dev/null)" ] || "$B/backup.sh" || true
api setWebhook --data-urlencode "url=$url/doorbell" -d "secret_token=$(cat $S)" -o /dev/null
echo "$(date '+%F %T') asleep: waiting for the doorbell" >&2
# Scheduled jobs need the container: with jobs, one packet every four minutes keeps the host from suspending it (Claude still sleeps).
K=; [ ! -s /data/cron/jobs ] || { (while sleep 240; do curl -s -m 5 -o /dev/null https://api.telegram.org || true; done) & K=$!; }
until waiting; do DOORBELL_SECRET=$(cat $S) bun "$B/doorbell.js" || sleep 5; done
[ -z "$K" ] || kill "$K" 2> /dev/null
api deleteWebhook -o /dev/null
echo "$(date '+%F %T') awake: a message is waiting" >&2
