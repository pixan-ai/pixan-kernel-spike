#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"
# Acceptance tests for scheduled jobs: bin/job.sh and bin/notify.sh with a stub `claude` and a stub `curl`.
# BIN points at the scripts under test; CI runs this inside the built image.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
cd / || exit 1
BIN=${BIN:-/usr/local/bin}; STUBS=$(mktemp -d)
cat > "$STUBS/claude" <<'EOF'
#!/usr/bin/env bash
# Stub Claude: record where it keeps its config, then behave as CLAUDE_STUB says.
echo "$CLAUDE_CONFIG_DIR" > /data/claude-config-dir; printf '%s' "${@: -1}" > /data/claude-prompt
case "${CLAUDE_STUB:-ok}" in ok) echo "five AI headlines";; echo) echo "${@: -1}"; echo "noise on stderr" >&2;; fail) echo "boom" >&2; exit 1;; hang) sleep 30;; esac
EOF
cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
# Stub Telegram: record the arguments and the config read from stdin.
printf '%s\n' "$*" >> /data/curl-args; cat >> /data/curl-stdin
EOF
chmod 755 "$STUBS"/*
fresh() {
  mkdir -p /data/workspace /data/config/channels/telegram; find /data -mindepth 1 -delete
  mkdir -p /data/workspace /data/config/channels/telegram /data/cron/prompts
  printf 'TELEGRAM_BOT_TOKEN=123:SECRET\nOWNER_TELEGRAM_ID=42\n' > /data/config/channels/telegram/.env
}
job() { env PATH="$STUBS:$BIN:$PATH" "$@" "$BIN/job.sh" news "Summarise the news" > /dev/null 2>&1; RC=$?; }
sent_to_owner() { grep -q "chat_id=42" /data/curl-args && grep -q "$1" /data/curl-args; }
token_only_on_stdin() { grep -q "bot123:SECRET/sendMessage" /data/curl-stdin && ! grep -q SECRET /data/curl-args; }

fresh; job
check "a job's answer is sent to the owner" sent_to_owner "five AI headlines"
check "...with the bot token on stdin, never on the command line" token_only_on_stdin
check "...and recorded for the bot: when, which job, what it said" test "$(jq -c '[.name, .text, (.at > 1700000000)]' /data/workspace/sent.jsonl)" = '["news","five AI headlines",true]'
check "a job runs in its own config directory, never the bot's" test "$(cat /data/claude-config-dir)" = /data/cron/config

fresh; mkdir -p /data/cron/prompts; echo "PROMPT-FROM-FILE" > /data/cron/prompts/news
env PATH="$STUBS:$BIN:$PATH" CLAUDE_STUB=echo "$BIN/job.sh" news > /dev/null 2>&1
check "a job without a prompt on its line takes it from its file" grep -q "PROMPT-FROM-FILE" /data/workspace/sent.jsonl
check "what a job writes on stderr never reaches the owner" bash -c '! grep -q "noise on stderr" /data/curl-args /data/workspace/sent.jsonl'

fresh; mkdir -p /data/cron/prompts; printf '%s' "-1001" > /data/cron/prompts/news.to; job
only_owner() { grep -q "chat_id=42" /data/curl-args && ! grep -q "chat_id=-1001" /data/curl-args; }
check "a job for a group this agent is no longer in (dropped, or never was) delivers to the owner instead" only_owner
: > /data/curl-args; echo "group -1001" > /data/settings; job
check "a job with a group as its destination delivers there" grep -q "chat_id=-1001" /data/curl-args
check "the job's session is told to write the message, not to send it" grep -q "do not look for a tool to send it" /data/claude-prompt
: > /data/curl-args; job CLAUDE_STUB=fail
check "...but its failure goes to the owner, never to the group" bash -c 'grep -q "chat_id=42" /data/curl-args && ! grep -q "chat_id=-1001" /data/curl-args'
check "...with the error, which never travels with a normal answer" grep -q "boom" /data/curl-args

fresh; job CLAUDE_STUB=fail
check "a failing job alerts the owner" sent_to_owner 'Scheduled job "news" failed'
check "...exits non-zero" test "$RC" != 0
check "...and records nothing as sent" test ! -e /data/workspace/sent.jsonl

fresh; job CLAUDE_STUB=hang JOB_TIMEOUT=1
check "a hung job is killed at its timeout and the owner is alerted" sent_to_owner 'Scheduled job "news" failed'

# --- watchdog: Claude up, Telegram plugin gone
printf '#!/usr/bin/env bash\n[ "${CLAUDE_UP:-1}" = 1 ]\n' > "$STUBS/pgrep"; printf '#!/usr/bin/env bash\necho "$*" >> /data/pkill-args\n' > "$STUBS/pkill"; chmod 755 "$STUBS/pgrep" "$STUBS/pkill"
dog() { env PATH="$STUBS:$BIN:$PATH" "$@" "$BIN/watchdog.sh" > /dev/null 2>&1; }
quiet() { test ! -e /data/pkill-args -a ! -s /data/curl-args; }
fresh; : > /data/curl-args; echo $$ > /data/config/channels/telegram/bot.pid; dog; dog
check "watchdog: plugin alive -> nothing happens" quiet
echo 999999 > /data/config/channels/telegram/bot.pid; dog
check "watchdog: plugin gone, first sighting -> wait (it may be starting)" quiet
echo $$ > /data/config/channels/telegram/bot.pid; dog; echo 999999 > /data/config/channels/telegram/bot.pid; dog
check "watchdog: a recovery in between resets the count" quiet
dog
check "watchdog: gone twice in a row -> the owner is told" sent_to_owner "Telegram channel was down"
check "...and Claude is restarted" grep -qx -- "-x script" /data/pkill-args
fresh; : > /data/curl-args; dog CLAUDE_UP=0; dog CLAUDE_UP=0; dog CLAUDE_UP=0
check "watchdog: Claude not running (starting, asleep) -> it judges nothing" quiet
fresh; : > /data/curl-args; echo $$ > /data/config/channels/telegram/bot.pid
echo $(($(date +%s) - 120)) > /data/cron/pending; dog
check "unanswered: a message two minutes old is not reported" quiet
echo $(($(date +%s) - 900)) > /data/cron/pending; dog
check "unanswered: a message left 15 minutes without an end of turn -> the owner is told" sent_to_owner "have not finished with it"
: > /data/curl-args; dog; dog
check "...once, not every five minutes" test ! -s /data/curl-args
check "the daily recycle's command (pkill) exists" test -x /usr/bin/pkill
if command -v supercronic > /dev/null; then
  check "the image's crontab is valid for supercronic" supercronic -quiet -test "$BIN/system.cron"
fi
rm -rf "$STUBS"
echo "$FAILS failed"; exit $((FAILS > 0))
