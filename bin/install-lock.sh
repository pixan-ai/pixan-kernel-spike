#!/usr/bin/env bash
# The install lock (docs/GETTING-STARTED.md, docs/THREAT-MODEL.md): only a message from the owner or a super-user may make the
# agent install packages, tools or skills. Called by the managed policy's hooks with the hook's JSON on stdin, and by start.sh.
#   install-lock.sh turn    UserPromptSubmit: open the lock for this turn if the message is a super-user's, else close it
#   install-lock.sh check   PreToolUse: an install while the lock is closed is refused (exit 2); the install record is never written by hand
#   install-lock.sh record  PostToolUse: an install that ran is added to /data/tools.json and the owner is told
#   install-lock.sh replay  start.sh: make the Python environment, then reinstall the recorded packages (failures are logged)
set -uo pipefail
OK=/data/cron/install-ok; LOG=/data/tools.json; B=$(dirname "$(readlink -f "$0")")
# Package managers, and anything that touches where installs live. A pattern, not a sandbox (docs/THREAT-MODEL.md).
INSTALL='(^|[^[:alnum:]_.-])((uv( pip| tool)?|pip[0-9.x]*|python3? -m pip|npm|pnpm|yarn|bun) +(install|i|add)( |$)|(uvx|bunx|npx|bun x)( |$)|claude +(plugin|mcp) )|/data/(bin|tools)(/| |$)|\.claude/skills|/data/config/skills'
# Only these are replayed at start: a package manager and package names, nothing a shell would interpret.
REPLAY='^(uv pip install|uv tool install|bun add -g) [][A-Za-z0-9._=<>~!@/:+, -]+$'
in=$( [ "${1:-}" = replay ] || cat )
field() { jq -r "$1 // \"\"" <<<"$in"; }
# The main session only: scheduled jobs and the dream run with their own config directory and never get the lock.
main_session() { [ "${CLAUDE_CONFIG_DIR-}" = /data/config ]; }
open() { main_session && [ -n "$(field .session_id)" ] && [ "$(jq -r .session "$OK" 2> /dev/null)" = "$(field .session_id)" ]; }
install() { grep -qE -- "$INSTALL" <<<"$(field .tool_input.command)" || case "$(realpath -m -- "$(field '.tool_input.file_path // .tool_input.notebook_path')")" in
  /data/bin/*|/data/tools/*|/data/config/skills/*|*/.claude/skills/*) true ;; *) false ;; esac; }
case "${1:-}" in
  turn)
    main_session || exit 0; rm -f "$OK"
    # A Telegram message reaches Claude as <channel source="…telegram…" chat_id="…" user="…" user_id="…" …> on a line of its own,
    # then the text. The values cannot hold a quote, and the text comes after that line, so a tag typed in a message is never the
    # first line; and a turn with a second <channel (a typed one, or two messages at once) gets no lock at all.
    p=$(field .prompt); first=${p%%$'\n'*}
    [[ $first =~ ^\<channel\ source=\"[^\"]*telegram[^\"]*\"(\ [A-Za-z_][A-Za-z0-9_]*=\"[^\"]*\")*\>$ ]] || exit 0
    [ "$(grep -oi '<channel' <<<"$p" | wc -l)" = 1 ] || exit 0
    [[ $first =~ \ user_id=\"([0-9]+)\" ]] || exit 0; id=${BASH_REMATCH[1]}
    [[ $first =~ \ user=\"([^\"]*)\" ]] && who=${BASH_REMATCH[1]} || who=$id
    grep -qxF "OWNER_TELEGRAM_ID=$id" /data/config/channels/telegram/.env 2> /dev/null || grep -qxF "admin $id" /data/settings 2> /dev/null || exit 0
    jq -n --arg s "$(field .session_id)" --arg id "$id" --arg u "$who" '{session: $s, id: $id, user: $u}' > "$OK" ;;
  check)
    case "$(field .tool_input.command) $(field '.tool_input.file_path // .tool_input.notebook_path')" in
      *install-ok*|*tools.json*) echo "The install record is kept by the policy: read /data/tools.json with the Read tool; it is never written by hand." >&2; exit 2 ;;
    esac
    ! install || open || { echo "Only the owner or a super-user can ask for an install (packages, tools, skills, /data/bin, /data/tools). Say so, and do not try another way." >&2; exit 2; } ;;
  record)
    install && open || exit 0
    jq -cn --slurpfile o "$OK" --arg t "$(field .tool_name)" --arg c "$(field '.tool_input.command // .tool_input.file_path // .tool_input.notebook_path')" \
      '{at: (now | todate), by: $o[0].user, by_id: $o[0].id, tool: $t, command: $c}' >> "$LOG"
    "$B/notify.sh" "🧰 Installed at the request of $(jq -r .user "$OK"): $(field '.tool_input.command // .tool_input.file_path' | head -c 300)" || true ;;
  replay)
    ! command -v uv > /dev/null || [ -x /data/tools/venv/bin/python ] || uv venv -q --python /usr/bin/python3 /data/tools/venv || echo "install-lock: no Python environment (not fatal)" >&2
    [ -s "$LOG" ] || exit 0
    jq -r '.command // empty' "$LOG" | grep -E -- "$REPLAY" | awk '!seen[$0]++' | while IFS= read -r c; do
      read -ra w <<<"$c"; "${w[@]}" < /dev/null > /dev/null 2>&1 && echo "install-lock: reinstalled: $c" >&2 || echo "install-lock: could not reinstall (not fatal): $c" >&2
    done ;;
  *) sed -n '2,8p' "$0" >&2; exit 2 ;;
esac
