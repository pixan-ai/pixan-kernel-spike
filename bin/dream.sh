#!/usr/bin/env bash
# The daily dream (docs/MEMORY.md): once a day, what was said since the last one is consolidated into /data/workspace/MEMORY.md
# and the next conversation starts clean, so the session does not grow for ever. start.sh calls this before every start of Claude.
set -uo pipefail
L=/data/cron/last-dream; W=/data/workspace
[ -z "$(find $L -mmin -1200 2> /dev/null)" ] || exit 0   # dreamt less than 20 hours ago
n=(); [ ! -e $L ] || n=(-newer "$L")
f=$(find /data/config/projects -maxdepth 2 -name '*.jsonl' "${n[@]}" -printf '%T@ %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2-)
[ -n "$f" ] || exit 0                                    # nothing was said since
# Its own config directory, like job.sh: a second Claude on the bot's directory would start a second Telegram plugin.
export CLAUDE_CONFIG_DIR=/data/cron/config
cd $W && mkdir -p memory || exit 0
# Only what was said: the owner's and other people's messages, and the agent's replies. No tool results.
jq -r 'select(.type == "user" or .type == "assistant") | .type as $t
  | (.message.content | if type == "string" then . else map(if .type == "text" then .text elif .type == "tool_use" then (.input.text // empty) else empty end) | join("\n") end)
  | select(length > 0) | "[\($t)] \(.[0:2000])"' "$f" | tail -c 300000 |
  timeout "${JOB_TIMEOUT:-900}" claude -p --permission-mode auto "You are consolidating this agent's memory at the end of its day. Standard input is its conversation since the last time. Tomorrow it starts a new conversation and will know only what is in $W/MEMORY.md, so:
1. Rewrite $W/MEMORY.md: merge today into what is there. Keep what a colleague taking over tomorrow needs: who is who and how they like things, decisions, commitments and open tasks with their dates, lessons learned. Drop what is done or obsolete. At most 150 lines. Never credentials.
2. Write $W/memory/$(date +%F).md: a short account of today (what was asked, what was done, what is pending).
Answer with one line." > /dev/null 2> /data/cron/dream.err ||
  { echo "dream: failed, the conversation continues: $(tail -c 300 /data/cron/dream.err)" >&2; exit 0; }  # a failed dream changes nothing
touch $L /data/fresh; echo "dream: memory consolidated, starting a clean conversation" >&2
