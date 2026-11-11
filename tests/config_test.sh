#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"
# Acceptance tests for bin/config.sh: the settings an agent may change itself, with a stub `curl` as Telegram.
set -uo pipefail
cd / || exit 1
BIN=${BIN:-/usr/local/bin}; STUBS=$(mktemp -d); FAILS=0
A=/data/config/channels/telegram/access.json
check() {  # check "description" command...
  local d=$1; shift
  if "$@"; then echo "ok   - $d"; else echo "FAIL - $d"; FAILS=$((FAILS + 1)); fi
}
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> /data/curl-args; cat > /dev/null\n' > "$STUBS/curl"; chmod 755 "$STUBS" "$STUBS/curl"
config() { env PATH="$STUBS:$PATH" "$BIN/config.sh" "$@" > /dev/null 2>&1; }
access() { jq -c "$1" $A; }
told() { grep -q "chat_id=42" /data/curl-args && grep -q "$1" /data/curl-args; }
refused() { ! config "$@" && test "$(cat /data/settings)" = "$before"; }

mkdir -p /data/config/channels/telegram; find /data -mindepth 1 -delete; mkdir -p /data/config/channels/telegram
printf 'TELEGRAM_BOT_TOKEN=123:SECRET\nOWNER_TELEGRAM_ID=42\n' > /data/config/channels/telegram/.env

config group -1001
check "group ID: the bot takes part in that group, without a mention" test "$(access '.groups["-1001"].requireMention')" = false
check "...listening only to the owner there" test "$(access '.groups["-1001"].allowFrom')" = '["42"]'
check "...and the owner is told, in private" told "Setting changed: group -1001"
config sender 777
check "sender ID: that user or bot is heard in the groups" test "$(access '.groups["-1001"].allowFrom')" = '["42","777"]'
check "...but not in private" test "$(access '.allowFrom - ["-1001"]')" = '["42"]'
config group -1001
check "repeating a setting does not duplicate it" test "$(grep -c 'group -1001' /data/settings)" = 1
config peer Junior=agent2.railway.internal
check "peer NAME=HOST is remembered" grep -qx "peer Junior=agent2.railway.internal" /data/settings

before=$(cat /data/settings)
check "an id that is not a number is refused" refused group '-1001; cat /etc/passwd'
check "the owner cannot be changed from here" refused owner 666
check "nor any other key" refused TELEGRAM_BOT_TOKEN abc

: > /data/curl-args; config apply
check "apply rebuilds the access list without telling anyone" test ! -s /data/curl-args -a "$(access '.groups | keys')" = '["-1001"]'
config drop 777; config drop -1001; config drop Junior
check "drop removes a sender, a group and a peer" test "$(access '[.groups, .allowFrom]')$(cat /data/settings)" = '[{},["42"]]'

rm -rf "$STUBS"
echo "$FAILS failed"; exit $((FAILS > 0))
