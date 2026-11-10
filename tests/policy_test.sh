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
printf '%s\n' "\$@" > "$ARGS"
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
  printf '%s' "$2" | env -i PATH="$STUBS:/usr/bin:/bin" sh -c "$(hook "$1")" > /dev/null 2>&1
}

check "the policy is valid JSON" setting .
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
printf 'TELEGRAM_BOT_TOKEN=123:abc\nOWNER_TELEGRAM_ID=42\n' > "$CREDS"

rm -f "$ARGS"
check "StopFailure hook runs" run_hook '.hooks.StopFailure[0].hooks[0].command' '{"error":"authentication_failed"}'
check "...and calls the bot API with the token from the credentials file" sent "https://api.telegram.org/bot123:abc/sendMessage"
check "...addressed to the owner" sent "chat_id=42"
check "...saying what failed" sent "authentication_failed"

rm -f "$ARGS"
check "Notification hook runs" run_hook '.hooks.Notification[0].hooks[0].command' '{"message":"Claude needs your permission to use Bash"}'
check "...and relays the permission prompt to the owner" sent "Claude needs your permission to use Bash"
check "...through the bot API" sent "https://api.telegram.org/bot123:abc/sendMessage"

: > /data/audit.jsonl
check "PostToolUse hook runs" run_hook '.hooks.PostToolUse[0].hooks[0].command' '{"tool":"Bash"}'
check "...and appends the event to the audit log" test "$(tail -1 /data/audit.jsonl)" = '{"tool":"Bash"}'

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
