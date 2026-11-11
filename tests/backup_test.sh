#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"
# Acceptance tests for bin/backup.sh with the real rclone and age, against a local folder standing in for the storage provider.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
cd / || exit 1
BIN=${BIN:-/usr/local/bin}; W=$(mktemp -d); R=$W/remote; STUBS=$W/stubs; mkdir -p "$R" "$STUBS"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> /data/curl-args; cat > /dev/null\n' > "$STUBS/curl"; chmod 755 "$STUBS/curl"
age-keygen -o "$W/key" 2> /dev/null; PUB=$(age-keygen -y "$W/key"); KEY=$(grep AGE-SECRET-KEY "$W/key")
age-keygen -o "$W/other" 2> /dev/null; OTHER=$(grep AGE-SECRET-KEY "$W/other")
backup() { env PATH="$STUBS:$BIN:$PATH" BACKUP_REMOTE="$R" BACKUP_AGE_RECIPIENT="$PUB" "$@" "$BIN/backup.sh" > /dev/null 2>&1; }
restore() { env PATH="$STUBS:$BIN:$PATH" BACKUP_REMOTE="$R" BACKUP_AGE_KEY="$1" "$BIN/backup.sh" restore > /dev/null 2>&1; }
wipe() { mkdir -p /data; find /data -mindepth 1 -delete; }
one_file() { test "$(find "$R" -name '*.tar.gz.age' | wc -l)" = "$1"; }
unreadable() { ! grep -rq "MEMORY-OF-THE-AGENT" "$R"; }
absent() { test ! -e "$1"; }

wipe; mkdir -p /data/workspace /data/config/plugins /data/config/channels/telegram /data/ssh /data/cron/prompts
echo "MEMORY-OF-THE-AGENT" > /data/workspace/notes.md; echo '{}' > /data/config/.claude.json; echo "0 8 * * * job.sh news" > /data/cron/jobs
echo plugin > /data/config/plugins/big; echo screen > /data/tui.log; echo secret > /data/ssh/peer_key
printf 'TELEGRAM_BOT_TOKEN=123:SECRET\nOWNER_TELEGRAM_ID=42\n' > /data/config/channels/telegram/.env

env PATH="$STUBS:$BIN:$PATH" "$BIN/backup.sh"
check "not configured -> does nothing, quietly" one_file 0
backup
check "a backup is one file at the storage provider" one_file 1
check "...that nobody can read without the owner's key" unreadable

wipe; mkdir -p /data/config/channels/telegram; printf 'TELEGRAM_BOT_TOKEN=123:SECRET\nOWNER_TELEGRAM_ID=42\n' > /data/config/channels/telegram/.env
wrong_key_fails() { ! restore "$OTHER" && absent /data/workspace/notes.md; }
check "the wrong key restores nothing" wrong_key_fails
restore "$KEY"
check "restore brings back the agent's memory" grep -q "MEMORY-OF-THE-AGENT" /data/workspace/notes.md
check "...its settings and its scheduled jobs" test -s /data/config/.claude.json -a -s /data/cron/jobs
check "...but not what the image rebuilds (plugin, screen log)" absent /data/config/plugins/big
check "...nor the keys" absent /data/ssh/peer_key

touch -d "30 days ago" "$R/2020-01-01-0000.tar.gz.age"; backup
check "backups older than the retention are removed" absent "$R/2020-01-01-0000.tar.gz.age"
: > /data/curl-args; backup BACKUP_REMOTE=/proc/no-such-place
check "a failed backup tells the owner" grep -q "backup failed" /data/curl-args

rm -rf "$W"
echo "$FAILS failed"; exit $((FAILS > 0))
