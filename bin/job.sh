#!/usr/bin/env bash
# Runs one scheduled prompt and delivers the answer to the owner. Usage: job.sh NAME (the prompt is in /data/cron/prompts/NAME; see config.sh job)
set -uo pipefail
name=$1; shift; [ $# -gt 0 ] || set -- "$(cat "/data/cron/prompts/$name")"
# Its own config directory: a second Claude on the bot's directory would start a second Telegram plugin, which kills the first.
export CLAUDE_CONFIG_DIR=/data/cron/config
cd /data/workspace || exit 1
if out=$(timeout "${JOB_TIMEOUT:-900}" claude -p --permission-mode auto "$*" 2>&1) && [ -n "$out" ]; then
  # The bot's own session never saw this message: keep a copy where its instructions tell it to look (last 300 lines).
  printf '\n## %s · %s\n%s\n' "$(date '+%F %H:%M')" "$name" "$out" >> sent.md && tail -n 300 sent.md > sent.md.tmp && mv sent.md.tmp sent.md
  notify.sh "$out"
else
  notify.sh "⚠️ Scheduled job \"$name\" failed or timed out. ${out: -300}"; exit 1
fi
