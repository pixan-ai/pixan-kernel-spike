#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"; regexes and jq programs are single-quoted on purpose
# Acceptance tests for bin/start.sh: run the real entrypoint as root (as Railway does with RAILWAY_RUN_UID=0)
# against an empty /data, with a stub `script` that records what claude would have been started with.
# CI runs this inside the built image; START points at the entrypoint under test.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
cd / || exit 1  # the tests empty /data, which can be the working directory of the container
START=${START:-/usr/local/bin/start.sh}
STUBS=$(mktemp -d); OUT=$(mktemp); ERR=$(mktemp)
chmod 755 "$STUBS"; chmod 644 "$OUT" "$ERR"
cat > "$STUBS/script" <<'EOF'
#!/usr/bin/env bash
# Stub pty: record who would run claude, with which credentials and command, then "exit" like claude dying.
{ echo "uid=$(id -u)"; echo "oauth=${CLAUDE_CODE_OAUTH_TOKEN:-}"; echo "bottoken=${TELEGRAM_BOT_TOKEN:-}"; echo "backupsecrets=${RCLONE_CONF:-}${BACKUP_AGE_KEY:-}"; echo "cmd=$2"; } > /data/probe
echo "owner said: SCREEN-MARKER" > /data/tui.log; sleep 3  # long enough for a 1 s mirror to fire
EOF
chmod 755 "$STUBS/script"
cat > "$STUBS/sleep" <<'EOF'
#!/usr/bin/env bash
# Stub the 60 s crash-loop brake (record it, return at once); every other sleep is real.
[ "$1" != 60 ] || { echo braked > /data/braked; exit 0; }
exec /bin/sleep "$@"
EOF
chmod 755 "$STUBS/sleep"
cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
# Stub Telegram: answer getMe with the HTTP status in TG_STATUS (default 200); 000 = no network.
printf '%s\n' "$*" >> /data/curl-calls 2>/dev/null
grep -q 'bot123:abc/' || { printf 000; exit 7; }  # the real request carries the token on stdin; without it there is no answer
while [ $# -gt 1 ]; do [ "$1" != -o ] || [ "${TG_STATUS:-200}" != 200 ] || echo '{"ok":true,"result":{"id":555,"username":"Test_bot","first_name":"Test"}}' > "$2"; shift; done
printf '%s' "${TG_STATUS:-200}"; [ "${TG_STATUS:-200}" != 000 ] || exit 7
EOF
printf '#!/usr/bin/env bash\necho "$*" > /data/supercronic-args\n' > "$STUBS/supercronic"; chmod 755 "$STUBS/supercronic"
printf '#!/usr/bin/env bash\necho "$*" > /data/peer-args\n' > "$STUBS/peer.sh"; chmod 755 "$STUBS/peer.sh"
printf '#!/usr/bin/env bash\necho "$*" >> /data/backup-args\n' > "$STUBS/backup.sh"; chmod 755 "$STUBS/backup.sh"
printf '#!/usr/bin/env bash\necho rang >> /data/doorbell-runs\n' > "$STUBS/doorbell.sh"; chmod 755 "$STUBS/doorbell.sh"
chmod 755 "$STUBS/curl"

base_env=(PATH="$STUBS:$PATH" TELEGRAM_BOT_TOKEN=123:abc OWNER_TELEGRAM_ID=42)
run() {  # run the entrypoint on a fresh, root-owned /data with the given extra env vars
  pkill -u 1001 2>/dev/null; mkdir -p /data /opt/seed/config; [ -e /opt/seed/config/plugins/installed_plugins.json ] || { mkdir -p /opt/seed/config/plugins; echo '{"installPath":"/opt/seed/config/plugins/cache/x"}' > /opt/seed/config/plugins/installed_plugins.json; }; find /data -mindepth 1 -delete; chown 0:0 /data
  env -i "${base_env[@]}" "$@" timeout 20 "$START" >"$OUT" 2>"$ERR"; RC=$?
  pkill -u 1001 2>/dev/null; return 0
}
probe() { grep -qx "$1" /data/probe 2>/dev/null; }
token_not_logged() { ! grep -q "abcdef" "$ERR"; }
channel_started() { grep -q "^cmd=.*exec claude .*--channels plugin:telegram@claude-plugins-official" /data/probe; }
creds_file_ok() { grep -qx "TELEGRAM_BOT_TOKEN=123:abc" "$1" && grep -qx "OWNER_TELEGRAM_ID=42" "$1"; }
rejected_by_telegram() { test "$RC" = 1 && grep -q "Telegram rejected TELEGRAM_BOT_TOKEN" "$ERR"; }
failed_fast_on_bot_token() { test "$RC" = 1 && grep -q "TELEGRAM_BOT_TOKEN" "$ERR" && test ! -e /data/probe; }

run CLAUDE_CODE_OAUTH_TOKEN=$'sk-ant-oat01-abc\n def\r\n'
check "claude dies -> entrypoint exits 1 (restart policy is the watchdog)" test "$RC" = 1
check "...and says so in the log" grep -q "claude exited" "$ERR"
check "claude runs as uid 1001, never root" probe "uid=1001"
check "/data is handed to uid 1001" test "$(stat -c %u /data)" = 1001
check "line breaks in the OAuth token are stripped" probe "oauth=sk-ant-oat01-abcdef"
check "token sanity line, without the token" grep -q "oauth token: 19 chars, starts with sk-ant-oat01-: yes$" "$ERR"
check "the token value never reaches the log" token_not_logged
check "claude starts with the official Telegram channel" channel_started
check "plugin credentials file is private (600)" test "$(stat -c %a /data/config/channels/telegram/.env)" = 600
check "plugin credentials file holds token and owner" creds_file_ok /data/config/channels/telegram/.env
check "only the owner is allowlisted" test "$(jq -c '[.dmPolicy, .allowFrom]' /data/config/channels/telegram/access.json)" = '["allowlist",["42"]]'
check "no API key -> nothing pre-approved" test "$(jq -c '.customApiKeyResponses // "none"' /data/config/.claude.json)" = '"none"'
check "workspace trusted and onboarding done" test "$(jq -c '[.hasCompletedOnboarding, .projects["/data/workspace"].hasTrustDialogAccepted]' /data/config/.claude.json)" = '[true,true]'

run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x
check "screen mirror is off by default: the conversation stays out of the log" bash -c '! grep -q SCREEN-MARKER "$0"' "$ERR"
run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x SCREEN_MIRROR=1
check "SCREEN_MIRROR=1 copies the screen to the log" grep -q SCREEN-MARKER "$ERR"
plugin_runs_from_volume() { grep -q /data/config/plugins /data/config/plugins/installed_plugins.json && ! grep -rqs /opt/seed /data/config/plugins/*.json; }
check "the plugin is registered at its volume copy, not at the image's build path" plugin_runs_from_volume
touch /data/config/plugins/left-by-an-older-image
env -i "${base_env[@]}" CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x timeout 20 "$START" >"$OUT" 2>"$ERR"; pkill -u 1001 2>/dev/null
check "...and every start replaces it with the image's version" test ! -e /data/config/plugins/left-by-an-older-image

again() { env -i "${base_env[@]}" CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x timeout 20 "$START" >"$OUT" 2>"$ERR"; pkill -u 1001 2>/dev/null; return 0; }
continues() { grep -q "^cmd=.*exec claude --continue " /data/probe; }
starts_fresh() { ! grep -q -- "--continue" /data/probe; }
run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x
check "first start: nothing to continue" starts_fresh
check "claude dying within a minute -> crash-loop brake" test -e /data/braked
mkdir -p /data/config/projects/-data-workspace && touch /data/config/projects/-data-workspace/s.jsonl; again
check "restart with a past session -> continues the conversation" continues
again
check "...but after dying at once while continuing, the next start is fresh" starts_fresh
again
check "...only once: then it continues again" continues

run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x
check "scheduled jobs: the image's jobs (daily recycle) are in what supercronic runs" grep -q "pkill -x script" /data/cron/crontab
check "...and supercronic runs that file" grep -q "/data/cron/crontab" /data/supercronic-args
echo "* * * * * touch /data/escaped" > /data/cron/crontab; echo "0 8 * * * job.sh news" > /data/cron/jobs; again
check "...a restart rebuilds it: a hand-written line is gone, the image's jobs are back" bash -c '! grep -q escaped /data/cron/crontab && grep -q "pkill -x script" /data/cron/crontab'
check "...and the agent's own jobs are kept" grep -qx "0 8 \* \* \* job.sh news" /data/cron/crontab
check "a quick restart is not reported as downtime" bash -c '! grep -q "Back online" /data/curl-calls'
touch -d "2 hours ago" /data/cron/alive; again
check "a start after real downtime tells the owner jobs may have been missed" grep -q "Back online" /data/curl-calls

check "peer view is off by default: no SSH server" test ! -e /data/peer-args
run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x PEER_PUBLIC_KEYS="ssh-ed25519 AAAA friend" PEER_SSH_KEY="PRIVATE-KEY-BODY"
check "PEER_PUBLIC_KEYS starts the peer view" grep -qx serve /data/peer-args
check "PEER_SSH_KEY is stored for looking at others, private (600)" test "$(stat -c %a /data/ssh/peer_key)$(cat /data/ssh/peer_key)" = "600PRIVATE-KEY-BODY"

check "no groups unless listed" test "$(jq -c .groups /data/config/channels/telegram/access.json)" = '{}'
run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x TELEGRAM_GROUP_IDS="-1001 -1002"
group() { jq -c "$1" /data/config/channels/telegram/access.json; }
check "listed groups are open to the bot, without a mention" test "$(group '[.groups | keys[], (.[] | .requireMention)]')" = '["-1001","-1002",false,false]'
check "...and it hears everyone in them, people and bots" test "$(group '.groups["-1001"].allowFrom')" = '[]'
check "...and private messages stay owner-only" test "$(group '.allowFrom - ["-1001","-1002"]')" = '["42"]'

check "the bot's own Telegram identity is kept for the session hook" test "$(jq -r .result.username /data/config/channels/telegram/me.json)" = Test_bot

seq 1 10050 > /data/audit.jsonl; seq 1 520 > /data/workspace/sent.jsonl; chown 1001 /data/audit.jsonl /data/workspace/sent.jsonl; again
check "the audit log is trimmed to its last 10000 lines at start" test "$(wc -l < /data/audit.jsonl) $(head -1 /data/audit.jsonl)" = "10000 51"
check "...and the record of job deliveries to its last 500" test "$(wc -l < /data/workspace/sent.jsonl) $(head -1 /data/workspace/sent.jsonl)" = "500 21"

token_gone() { grep -qx "bottoken=" /data/probe; }
check "the bot token is no longer in the environment when Claude starts" token_gone

check "no restore unless the owner provides the key" test ! -e /data/backup-args
run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x RCLONE_CONF="[gdrive]" BACKUP_AGE_KEY=AGE-SECRET-KEY-1X
check "an empty volume with BACKUP_AGE_KEY is restored before anything else" grep -qx restore /data/backup-args
check "the storage credentials are kept in a private file (600)" test "$(stat -c %a /data/ssh/rclone.conf)$(cat /data/ssh/rclone.conf)" = "600[gdrive]"
check "...and neither they nor the restore key stay in the environment of Claude" grep -qx "backupsecrets=" /data/probe
rm -f /data/backup-args; again
check "a volume that already has data is never restored over" test ! -e /data/backup-args

touch /data/idle; again
check "sleep is off by default: a leftover marker changes nothing" test ! -e /data/doorbell-runs
touch /data/idle; env -i "${base_env[@]}" CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x IDLE_SLEEP_MINUTES=30 timeout 20 "$START" >"$OUT" 2>"$ERR"; pkill -u 1001 2>/dev/null
check "IDLE_SLEEP_MINUTES: an agent that was asleep waits at the doorbell before Claude starts" test -s /data/doorbell-runs
check "...then starts Claude and is no longer marked asleep" bash -c 'grep -q "exec claude" /data/probe && test ! -e /data/idle'
check "...and waking up is not reported as downtime" bash -c '! grep -q "Back online" /data/curl-calls'

run ANTHROPIC_API_KEY=dummy-api-key-0123456789ABCDEFGHIJ
check "API key switch: its last 20 chars are pre-approved" test "$(jq -c '.customApiKeyResponses.approved' /data/config/.claude.json)" = '["0123456789ABCDEFGHIJ"]'

run
check "no Claude credential -> fails fast" test "$RC" = 1
check "...naming both options" grep -q "CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY" "$ERR"
check "...before starting claude" test ! -e /data/probe

run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x TG_STATUS=401
check "Telegram rejects the bot token (401) -> fails fast, says so" rejected_by_telegram
check "...before starting claude" test ! -e /data/probe
run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x TG_STATUS=000
check "Telegram unreachable -> still starts (a hiccup is not a verdict)" probe "uid=1001"

base_env=(PATH="$STUBS:$PATH" OWNER_TELEGRAM_ID=42)
run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x
check "no bot token -> fails fast naming it" failed_fast_on_bot_token
base_env=(PATH="$STUBS:$PATH" TELEGRAM_BOT_TOKEN=123:abc)
run CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x
failed_fast_on_owner() { test "$RC" = 1 && grep -q "OWNER_TELEGRAM_ID" "$ERR" && test ! -e /data/probe; }
check "no owner id -> fails fast naming it" failed_fast_on_owner

rm -rf "$STUBS" "$OUT" "$ERR"
echo "$FAILS failed"; exit $((FAILS > 0))
