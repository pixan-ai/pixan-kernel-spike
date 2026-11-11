#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"; regexes and jq programs are single-quoted on purpose
# Acceptance tests for the two diagnostic tools, bin/screen.sh and bin/denials.sh. They read fixed paths under /data
# and the installed managed policy, so run as root inside the built image (or in a private mount namespace).
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname "$(readlink -f "$0")")/lib.sh"
cd / || exit 1  # the tests empty /data, which can be the working directory of the container
SCREEN=${SCREEN:-/usr/local/bin/screen.sh}
DENIALS=${DENIALS:-/usr/local/bin/denials.sh}
P=/data/config/projects/-data-workspace

has() { grep -qF -- "$2" <<<"$1"; }
lacks() { ! grep -qF -- "$2" <<<"$1"; }
reset() { mkdir -p /data; find /data -mindepth 1 -delete; }
err() { printf '{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"%s"}]}}\n' "$1"; }

check "the managed policy is installed" test -r /etc/claude-code/managed-settings.json

# --- screen.sh: the readable view of the raw terminal log
reset
printf '\033[1;1HHello \033[31mred\033[0m\r\n\033[2;1HWorld\033]0;title\007\033[3;1H   \033[4;1Hlast' > /data/tui.log
check "screen: cursor moves split lines; colors, titles, CRs and blank lines are dropped" \
  test "$("$SCREEN")" = $'Hello red\nWorld\nlast'

seq 1 40 | sed 's/^/line /' > /data/tui.log
check "screen: shows the last 30 lines by default" test "$("$SCREEN" | wc -l)" = 30
check "screen: the first of them is line 11" test "$("$SCREEN" | head -1)" = "line 11"
check "screen: an argument sets how many lines" \
  test "$("$SCREEN" 3)" = $'line 38\nline 39\nline 40'

printf '%0200d\n' 0 | tr 0 x > /data/tui.log
check "screen: lines are cut at 160 columns" test "$("$SCREEN" | awk '{ print length }')" = 160

reset
check "screen: no log -> prints nothing" test -z "$("$SCREEN" 2>/dev/null)"

# --- denials.sh: policy health and the tool errors of the latest session
export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false
reset
out=$("$DENIALS" 2>/dev/null)
check "denials: no transcript -> says so" has "$out" "no session transcript"

mkdir -p "$P"
err "OLD-ERROR" > "$P/old.jsonl"; touch -d '2 hours ago' "$P/old.jsonl"
{
  err "first-error"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","is_error":false,"content":"fine-result"}]}}\n'
  printf '{"type":"assistant","message":{"content":"not-a-tool-result"}}\n'
  err "second-error"
} > "$P/new.jsonl"
out=$("$DENIALS" 2>/dev/null)
check "denials: prints the errors of the newest transcript" has "$out" "second-error"
check "denials: ...in order, all of them" has "$out" "first-error"
check "denials: ignores older transcripts" lacks "$out" "OLD-ERROR"
check "denials: ignores results that are not errors" lacks "$out" "fine-result"
check "denials: counts the block-audit hooks of the policy (2 or more)" test "$(sed -n 2p <<<"$out")" -ge 2
check "denials: reports the prompt-suggestion variable" test "$(sed -n 4p <<<"$out")" = false

for i in $(seq 1 12); do err "err-$i"; done > "$P/new.jsonl"
out=$("$DENIALS" 2>/dev/null)
check "denials: by default shows the last 8 errors" test "$(grep -c '^err-' <<<"$out")" = 8
check "denials: ...starting at err-5" test "$(grep '^err-' <<<"$out" | head -1)" = err-5
out=$("$DENIALS" 3 2>/dev/null)
check "denials: an argument limits the errors to the last N" test "$(grep -c '^err-' <<<"$out")" = 3
check "denials: ...the most recent ones" has "$out" "err-12"
check "denials: ...and not the earlier ones" lacks "$out" "err-9"

err "$(printf '%0500d' 0 | tr 0 y)" > "$P/new.jsonl"
out=$("$DENIALS" 2>/dev/null)
check "denials: error text is cut at 400 characters" test "$(tail -1 <<<"$out" | awk '{ print length }')" = 400

reset
echo "$FAILS failed"; exit $((FAILS > 0))
