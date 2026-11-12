#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"
# Acceptance tests for the daily dream: bin/dream.sh with a stub `claude`.
# BIN points at the scripts under test; CI runs this inside the built image.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
cd / || exit 1
BIN=${BIN:-/usr/local/bin}; STUBS=$(mktemp -d); P=/data/config/projects/-data-workspace
cat > "$STUBS/claude" <<'EOF2'
#!/usr/bin/env bash
# Stub Claude: record its config directory, its prompt and what it was given to read; then behave as CLAUDE_STUB says.
echo "$CLAUDE_CONFIG_DIR" > /data/claude-config-dir; printf '%s' "$*" > /data/claude-prompt; printf '%s\n' "$@" > /data/claude-args; cat > /data/claude-stdin
[ "${CLAUDE_STUB:-ok}" = ok ] || { echo boom >&2; exit 1; }
echo "- Ana prefers mornings" > /data/workspace/MEMORY.md
EOF2
chmod 755 "$STUBS"/*
fresh() {
  mkdir -p /data/workspace; find /data -mindepth 1 -delete; mkdir -p /data/workspace /data/cron "$P"
  echo '{"type":"user","message":{"content":"Call Ana on Monday"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","input":{"text":"Noted, Monday"}},{"type":"tool_result","content":"TOOL-OUTPUT"}]}}' > "$P/s1.jsonl"
}
dream() { env PATH="$STUBS:$BIN:$PATH" "$@" "$BIN/dream.sh" > /dev/null 2> /data/dream-log; RC=$?; }
rc() { test "$RC" = "$1"; }
absent() { test ! -e "$1"; }
gave() { grep -q "$1" /data/claude-stdin; }
kept_out() { ! grep -q "$1" /data/claude-stdin; }

fresh; dream
check "a dream consolidates the conversation: Claude is given what was said" gave "Call Ana on Monday"
check "...and what the agent answered on Telegram" gave "Noted, Monday"
check "...but not tool results" kept_out TOOL-OUTPUT
check "...and is told to keep the memory file" grep -q "/data/workspace/MEMORY.md" /data/claude-prompt
check "...with file tools only: no shell and no network over text that anyone in a group may have written" test "$(tail -n 2 /data/claude-args | tr "\n" " ")" = "--tools Read,Edit,Write "
check "...in its own config directory, not the bot's (a second Telegram plugin would silence the bot)" test "$(cat /data/claude-config-dir)" = /data/cron/config
check "after a dream the next conversation starts clean" test -e /data/fresh
check "...and the dream is remembered" test -e /data/cron/last-dream
check "...and the start log says so" grep -q "dream: memory consolidated" /data/dream-log

rm -f /data/fresh /data/claude-stdin; dream
check "no second dream the same day: nothing runs" absent /data/claude-stdin
check "...and the conversation continues" absent /data/fresh

touch -d '21 hours ago' /data/cron/last-dream; touch -d '22 hours ago' "$P/s1.jsonl"; dream
check "a day later with nothing new said: no dream" absent /data/claude-stdin
touch "$P/s1.jsonl"; dream
check "a day later with a conversation: it dreams again" gave "Call Ana"

fresh; dream CLAUDE_STUB=fail
check "a failed dream does not wipe the conversation: it continues" absent /data/fresh
check "...and is tried again at the next start" absent /data/cron/last-dream
check "...and the start log says why" grep -q "dream: failed.*boom" /data/dream-log
check "...without stopping the agent from starting" rc 0

fresh; rm "$P/s1.jsonl"; dream
check "a new agent with no conversation does not dream" absent /data/claude-stdin

echo "$FAILS failed"; exit $((FAILS > 0))
