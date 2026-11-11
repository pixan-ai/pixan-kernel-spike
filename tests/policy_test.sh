#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"; regexes and jq programs are single-quoted on purpose
# Acceptance tests for the managed policy as installed in the image (POLICY): the settings that keep the agent safe and
# unattended, and the hooks it runs, executed against a stub curl with an empty environment. Run as root inside the image.
set -uo pipefail
cd / || exit 1  # the tests empty /data, which can be the working directory of the container
POLICY=${POLICY:-/etc/claude-code/managed-settings.json}
CREDS=/data/config/channels/telegram/.env
STUBS=$(mktemp -d); ARGS=$STUBS/curl.args; FAILS=0
chmod 755 "$STUBS"
cat > "$STUBS/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGS"; cat > "$ARGS.stdin"
EOF
chmod 755 "$STUBS/curl"

check() {  # check "description" command...
  local d=$1; shift
  if "$@"; then echo "ok   - $d"; else echo "FAIL - $d"; FAILS=$((FAILS + 1)); fi
}
setting() { jq -e "$1" "$POLICY" > /dev/null; }
denies() { jq -e --arg r "$1" '.permissions.deny | index($r) != null' "$POLICY" > /dev/null; }
parses() { printf '%s\n' "$1" | bash -n; }
sent() { grep -qF -- "$1" "$ARGS"; }
hook() { jq -r "$1" "$POLICY"; }
run_hook() {  # run_hook JQ-PATH-TO-COMMAND STDIN-JSON: runs the hook with an empty environment, as a POSIX shell
  printf '%s' "$2" | env -i PATH="$STUBS:${BIN:-/usr/local/bin}:/usr/bin:/bin" sh -c "$(hook "$1")" > /dev/null 2>&1
}

check "the policy is valid JSON" setting .
check "the agent's instructions are managed: next to the policy, out of its reach" test -s "$(dirname "$POLICY")/CLAUDE.md"
for expr in '.channelsEnabled == true' '.disableClaudeAiConnectors == true' '.promptSuggestionEnabled == false' \
            '.permissions.denyInsteadOfPrompting == true' '.skipDangerousModePermissionPrompt == true'; do
  check "policy: $expr" setting "$expr"
done
# Photos and files from Telegram land in the plugin's inbox, outside the workspace: without this the first Read would prompt, and a prompt is denied.
inbox_readable() { jq -e --arg d "${TELEGRAM_STATE_DIR:-/data/config/channels/telegram}/inbox" '.permissions.additionalDirectories | index($d) != null' "$POLICY" > /dev/null; }
check "the agent may read the Telegram inbox (attachments)" inbox_readable
for rule in 'Read(**/.env)' 'Read(**/.env.*)' 'Edit(//etc/claude-code/**)' 'Edit(//data/config/channels/**)' \
            'Edit(//data/config/plugins/**)' 'Edit(//data/config/settings.json)' 'Bash(printenv)' 'Bash(env)'; do
  check "policy denies $rule" denies "$rule"
done
check "auto mode keeps the built-in rules and forbids leaking credentials" \
  setting '.autoMode.hard_deny | (index("$defaults") != null) and (map(test("credential"; "i")) | any)'
for event in SessionStart PostToolUse PostToolUseFailure PermissionDenied StopFailure Notification; do
  check "policy has a $event hook" setting ".hooks.$event | length > 0"
done
mapfile -t cmds < <(jq -r '.hooks[][].hooks[].command' "$POLICY")
for c in "${cmds[@]}"; do check "hook command parses: ${c:0:44}..." parses "$c"; done

# --- the hooks, executed. Credentials come from the private file, never from the environment.
mkdir -p "$(dirname "$CREDS")"
says() { session_start | grep -q "$1"; }
silent_about() { ! says "$1"; }
session_start() { env -i PATH=/usr/bin:/bin sh -c "$(hook '.hooks.SessionStart[0].hooks[0].command')" 2>&1; }
echo '{"ok":true,"result":{"id":555,"username":"Test_bot","first_name":"Test"}}' > "$(dirname "$CREDS")/me.json"
check "SessionStart tells the agent the date" says "The current date and time is"
check "...and its own Telegram bot name and id" says "You are the Telegram bot @Test_bot (shown as Test), id 555"
echo '{"ok":false,"error_code":401}' > "$(dirname "$CREDS")/me.json"
check "...and says nothing about a name it does not know" silent_about "Telegram bot"
rm -f "$(dirname "$CREDS")/me.json"
check "...and still works without that file" says "The current date"
printf 'TELEGRAM_BOT_TOKEN=123:abc\nOWNER_TELEGRAM_ID=42\n' > "$CREDS"

rm -f "$ARGS"
check "StopFailure hook runs" run_hook '.hooks.StopFailure[0].hooks[0].command' '{"error":"authentication_failed"}'
on_stdin() { grep -qF -- "$1" "$ARGS.stdin"; }
off_the_command_line() { ! sent "$1"; }
check "...and calls the bot API with the token from the credentials file" on_stdin "https://api.telegram.org/bot123:abc/sendMessage"
check "...which never appears on a command line" off_the_command_line "123:abc"
check "...addressed to the owner" sent "chat_id=42"
check "...saying what failed" sent "authentication_failed"

rm -f "$ARGS"
check "Notification hook runs" run_hook '.hooks.Notification[0].hooks[0].command' '{"message":"Claude needs your permission to use Bash"}'
check "...and relays the permission prompt to the owner" sent "Claude needs your permission to use Bash"
check "...through the bot API" on_stdin "https://api.telegram.org/bot123:abc/sendMessage"

: > /data/audit.jsonl
check "PostToolUse hook runs" run_hook '.hooks.PostToolUse[0].hooks[0].command' '{"hook_event_name":"PostToolUse","tool_name":"Bash","permission_mode":"auto","tool_input":{"command":"SECRET-COMMAND"},"tool_response":"LONG-OUTPUT"}'
check "...and appends one short line: when, which event, which tool, which mode" test "$(tail -1 /data/audit.jsonl | jq -c '[.event, .tool, .mode, (.at | length > 10)]')" = '["PostToolUse","Bash","auto",true]'
check "...without the tool's input or output (the transcript already has them)" bash -c '! grep -qE "SECRET-COMMAND|LONG-OUTPUT" /data/audit.jsonl'
check "the three audit hooks write the same record" test "$(jq -r '[.hooks.PostToolUse, .hooks.PostToolUseFailure, .hooks.PermissionDenied] | map(.[0].hooks[0].command) | unique | length' "$POLICY")" = 1

matcher=$(hook '.hooks.StopFailure[0].matcher')
matches() { grep -Eqx -- "$matcher" <<<"$1"; }
unmatched() { ! matches "$1"; }
check "StopFailure alerts on authentication_failed" matches authentication_failed
check "StopFailure alerts on billing_error" matches billing_error
check "StopFailure stays quiet on a rate limit" unmatched rate_limit
check "Notification alerts only on permission prompts" test "$(hook '.hooks.Notification[0].matcher')" = permission_prompt

rm -f "$CREDS" /data/audit.jsonl "$ARGS" "$STUBS/curl"
rmdir "$STUBS" 2> /dev/null
echo "$FAILS failed"; exit $((FAILS > 0))
