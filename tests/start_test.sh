#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"; regexes and jq programs are single-quoted on purpose
# Acceptance tests for bin/start.sh: run the real entrypoint as root (as Railway does with RAILWAY_RUN_UID=0)
# against an empty /data, with a stub `script` that records what claude would have been started with.
# CI runs this inside the built image; START points at the entrypoint under test.
set -uo pipefail
cd / || exit 1  # the tests empty /data, which can be the working directory of the container
START=${START:-/usr/local/bin/start.sh}
STUBS=$(mktemp -d); OUT=$(mktemp); ERR=$(mktemp); FAILS=0
chmod 755 "$STUBS"; chmod 644 "$OUT" "$ERR"
cat > "$STUBS/script" <<'EOF'
#!/usr/bin/env bash
# Stub pty: record who would run claude, with which credentials and command, then "exit" like claude dying.
{ echo "uid=$(id -u)"; echo "oauth=${CLAUDE_CODE_OAUTH_TOKEN:-}"; echo "cmd=$2"; } > /data/probe
echo "owner said: SCREEN-MARKER" > /data/tui.log; sleep 3  # long enough for a 1 s mirror to fire
EOF
chmod 755 "$STUBS/script"
cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
# Stub Telegram: answer getMe with the HTTP status in TG_STATUS (default 200); 000 = no network.
cat > /dev/null; printf '%s' "${TG_STATUS:-200}"; [ "${TG_STATUS:-200}" != 000 ] || exit 7
EOF
chmod 755 "$STUBS/curl"

base_env=(PATH="$STUBS:$PATH" TELEGRAM_BOT_TOKEN=123:abc OWNER_TELEGRAM_ID=42)
run() {  # run the entrypoint on a fresh, root-owned /data with the given extra env vars
  pkill -u 1001 2>/dev/null; mkdir -p /data /opt/seed/config /opt/seed/workspace; [ -f /opt/seed/workspace/CLAUDE.md ] || echo seed > /opt/seed/workspace/CLAUDE.md; find /data -mindepth 1 -delete; chown 0:0 /data
  env -i "${base_env[@]}" "$@" timeout 20 "$START" >"$OUT" 2>"$ERR"; RC=$?
  pkill -u 1001 2>/dev/null; return 0
}
check() {  # check "description" command...
  local d=$1; shift
  if "$@"; then echo "ok   - $d"; else echo "FAIL - $d"; FAILS=$((FAILS + 1)); fi
}
probe() { grep -qx "$1" /data/probe 2>/dev/null; }
token_not_logged() { ! grep -q "abcdef" "$ERR"; }
channel_started() { grep -q "^cmd=.*exec claude --channels plugin:telegram@claude-plugins-official" /data/probe; }
creds_file_ok() { grep -qx "TELEGRAM_BOT_TOKEN=123:abc" "$1" && grep -qx "OWNER_TELEGRAM_ID=42" "$1"; }
rejected_by_telegram() { test "$RC" = 1 && grep -q "Telegram rejected TELEGRAM_BOT_TOKEN" "$ERR"; }
failed_fast_on_bot_token() { test "$RC" = 1 && grep -q "TELEGRAM_BOT_TOKEN" "$ERR" && test ! -e /data/probe; }

run CLAUDE_CODE_OAUTH_TOKEN=$'sk-ant-oat01-abc\n def\r\n'
check "claude dies -> entrypoint exits 1 (restart policy is the watchdog)" test "$RC" = 1
check "...and says so in the log" grep -q "claude exited" "$ERR"
check "claude runs as uid 1001, never root" probe "uid=1001"
check "/data is handed to uid 1001" test "$(stat -c %u /data)" = 1001
check "line breaks in the OAuth token are stripped" probe "oauth=sk-ant-oat01-abcdef"
check "token sanity line, without the token" grep -q "oauth token: 19 chars, starts with sk-ant-oat01-: yes, whitespace: no" "$ERR"
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
check "the agent gets its instructions (CLAUDE.md) in the workspace" test -s /data/workspace/CLAUDE.md
echo "owner edit" > /data/workspace/CLAUDE.md
env -i "${base_env[@]}" CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-x timeout 20 "$START" >"$OUT" 2>"$ERR"; pkill -u 1001 2>/dev/null
check "...and a restart keeps the owner's edits" test "$(cat /data/workspace/CLAUDE.md)" = "owner edit"

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

rm -rf "$STUBS" "$OUT" "$ERR"
echo "$FAILS failed"; exit $((FAILS > 0))
