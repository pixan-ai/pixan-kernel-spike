#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"
# Acceptance tests for the opt-in sleep: bin/doorbell.js with the real bun and curl, bin/doorbell.sh against a stub Telegram.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
cd / || exit 1
BIN=${BIN:-/usr/local/bin}; STUBS=$(mktemp -d); CURL=$(command -v curl); PORT=18181; export PORT

# --- the listener: only Telegram's ring wakes the agent, and one ring is one wake
ring() { "$CURL" -s -o /dev/null -w '%{http_code}' -m 5 -X POST "http://127.0.0.1:$PORT/doorbell" "$@" -d '{"message":{"text":"hi"}}'; }
DOORBELL_SECRET=s3cret bun "$BIN/doorbell.js" & L=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2> /dev/null && break; sleep 0.3; done
check "a caller without the secret is refused" test "$(ring)" = 403
check "...and with a wrong one" test "$(ring -H 'X-Telegram-Bot-Api-Secret-Token: guess')" = 403
check "...and does not wake the agent" kill -0 "$L"
check "Telegram's ring is answered 503, so Telegram keeps the message" test "$(ring -H 'X-Telegram-Bot-Api-Secret-Token: s3cret')" = 503
ring -H 'X-Telegram-Bot-Api-Secret-Token: s3cret' > /dev/null 2>&1  # a retry right behind the first ring
gone() { for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$L" 2> /dev/null || return 0; sleep 0.3; done; return 1; }
check "...and the listener ends: one wake, however many times Telegram retries" gone

# --- the sleep script against a stub Telegram: pending-count says how many messages wait
cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
# Stub Telegram Bot API. The method is the last path element of the URL given on stdin.
m=$(sed -n 's/.*\/\([A-Za-z]*\)"$/\1/p'); echo "$m $*" >> /data/api-calls
[ "$m" != getWebhookInfo ] || printf '{"ok":true,"result":{"pending_update_count":%s}}' "$(cat /data/pending-count)"
EOF
printf '#!/usr/bin/env bash\necho ring >> /data/bun-runs; echo 1 > /data/pending-count\n' > "$STUBS/bun"
printf '#!/usr/bin/env bash\necho run >> /data/backup-runs\n' > "$STUBS/backup.sh"
chmod 755 "$STUBS"/*
fresh() {
  mkdir -p /data; find /data -mindepth 1 -delete; mkdir -p /data/config/channels/telegram /data/ssh /data/cron
  printf 'TELEGRAM_BOT_TOKEN=123:SECRET\nOWNER_TELEGRAM_ID=42\n' > /data/config/channels/telegram/.env; echo "$1" > /data/pending-count
}
# backup.sh is looked up next to doorbell.sh: run a copy that sits beside the stubs
cp "$BIN/doorbell.sh" "$BIN/doorbell.js" "$STUBS/"
asleep() { env PATH="$STUBS:$PATH" "$@" "$STUBS/doorbell.sh" > /dev/null 2>&1; }
calls() { cut -d' ' -f1 /data/api-calls | tr '\n' ' '; }

fresh 0; asleep DOORBELL_URL=https://agent.example
check "going to sleep sets Telegram's webhook to this service" grep -q "^setWebhook .*url=https://agent.example/doorbell" /data/api-calls
check "...with a secret that only Telegram and this agent know" grep -q "secret_token=$(cat /data/ssh/doorbell-secret)" /data/api-calls
check "...kept in a private file" test "$(stat -c %a /data/ssh/doorbell-secret)" = 600
check "it waits for a ring, then removes the webhook so the plugin can poll" test "$(cat /data/bun-runs) $(calls | awk '{print $NF}')" = "ring deleteWebhook"
check "a backup is made before sleeping when the last one is old" test -s /data/backup-runs

fresh 1; touch /data/cron/last-backup; asleep DOORBELL_URL=https://agent.example
check "a message already waiting (it arrived while going to sleep, or the host woke the container) -> no waiting" test ! -e /data/bun-runs
check "...and the webhook is removed" grep -q "^deleteWebhook" /data/api-calls
check "no backup when a recent one exists" test ! -e /data/backup-runs

fresh 0
no_address() { ! env PATH="$STUBS:$PATH" "$STUBS/doorbell.sh" > /dev/null 2> /data/err && grep -q DOORBELL_URL /data/err && test ! -e /data/api-calls; }
check "without a public address it refuses to sleep, and says why" no_address

rm -rf "$STUBS"
echo "$FAILS failed"; exit $((FAILS > 0))
