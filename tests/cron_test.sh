#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"
# Acceptance tests for scheduled jobs: bin/job.sh and bin/notify.sh with a stub `claude` and a stub `curl`.
# BIN points at the scripts under test; CI runs this inside the built image.
set -uo pipefail
cd / || exit 1
BIN=${BIN:-/usr/local/bin}; STUBS=$(mktemp -d); FAILS=0
check() {  # check "description" command...
  local d=$1; shift
  if "$@"; then echo "ok   - $d"; else echo "FAIL - $d"; FAILS=$((FAILS + 1)); fi
}
cat > "$STUBS/claude" <<'EOF'
#!/usr/bin/env bash
# Stub Claude: record where it keeps its config, then behave as CLAUDE_STUB says.
echo "$CLAUDE_CONFIG_DIR" > /data/claude-config-dir
case "${CLAUDE_STUB:-ok}" in ok) echo "five AI headlines";; fail) echo "boom" >&2; exit 1;; hang) sleep 30;; esac
EOF
cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
# Stub Telegram: record the arguments and the config read from stdin.
printf '%s\n' "$*" >> /data/curl-args; cat >> /data/curl-stdin
EOF
chmod 755 "$STUBS"/*
fresh() {
  mkdir -p /data/workspace /data/config/channels/telegram; find /data -mindepth 1 -delete
  mkdir -p /data/workspace /data/config/channels/telegram
  printf 'TELEGRAM_BOT_TOKEN=123:SECRET\nOWNER_TELEGRAM_ID=42\n' > /data/config/channels/telegram/.env
}
job() { env PATH="$STUBS:$BIN:$PATH" "$@" "$BIN/job.sh" news "Summarise the news" > /dev/null 2>&1; RC=$?; }
sent_to_owner() { grep -q "chat_id=42" /data/curl-args && grep -q "$1" /data/curl-args; }
token_only_on_stdin() { grep -q "bot123:SECRET/sendMessage" /data/curl-stdin && ! grep -q SECRET /data/curl-args; }

fresh; job
check "a job's answer is sent to the owner" sent_to_owner "five AI headlines"
check "...with the bot token on stdin, never on the command line" token_only_on_stdin
check "...and kept where the bot can find it later (sent.md)" grep -q "five AI headlines" /data/workspace/sent.md
check "...under the job's name" grep -q "news" /data/workspace/sent.md
check "a job runs in its own config directory, never the bot's" test "$(cat /data/claude-config-dir)" = /data/cron/config

fresh; job CLAUDE_STUB=fail
check "a failing job alerts the owner" sent_to_owner 'Scheduled job "news" failed'
check "...exits non-zero" test "$RC" != 0
check "...and records nothing as sent" test ! -e /data/workspace/sent.md

fresh; job CLAUDE_STUB=hang JOB_TIMEOUT=1
check "a hung job is killed at its timeout and the owner is alerted" sent_to_owner 'Scheduled job "news" failed'

check "the daily recycle's command (pkill) exists" command -v pkill
if command -v supercronic > /dev/null; then
  check "the seeded crontab is valid for supercronic" supercronic -quiet -test "${CRONTAB:-/opt/seed/crontab}"
fi
rm -rf "$STUBS"
echo "$FAILS failed"; exit $((FAILS > 0))
