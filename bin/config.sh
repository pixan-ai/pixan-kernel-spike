#!/usr/bin/env bash
# Settings an agent may change itself when its owner asks in chat (docs/SETTINGS.md). Applied at once, and the owner is told every time.
#   config.sh group ID       take part in this Telegram group
#   config.sh sender ID      also listen to this user or bot in the groups
#   config.sh peer NAME=HOST remember a fellow agent's private address
#   config.sh job "M H D M W" NAME "PROMPT"   run that prompt on that schedule (job.sh delivers the answer)
#   config.sh drop VALUE     remove the lines with this value (a group, a sender, a peer or a job name)
#   config.sh show | apply   print the settings | rebuild the plugin's access list without changing anything (start.sh)
# Nothing else can be set here: owner, tokens and keys only come from the host's variables.
set -euo pipefail
F=/data/settings; TG=/data/config/channels/telegram; J=/data/cron/jobs; B=$(dirname "$(readlink -f "$0")")
mkdir -p /data/cron/prompts; touch $F $J
case "${1:-} ${2:-}" in
  "show ") exec cat $F $J ;;
  "job "*) [[ $2 =~ ^([0-9*/,-]+\ ){4}[0-9*/,-]+$ && ${3:-} =~ ^[A-Za-z0-9_-]+$ && -n ${4:-} ]] || { echo 'use: job "M H D M W" NAME "PROMPT"' >&2; exit 2; }
    printf '%s\n' "$4" > "/data/cron/prompts/$3"; grep -vE " job\.sh $3$" $J > $J.tmp || true; echo "$2 job.sh $3" >> $J.tmp; mv $J.tmp $J; set -- job "$3 ($2)" ;;
  "apply ") ;;
  "group "*|"sender "*) [[ $2 =~ ^-?[0-9]+$ ]] || { echo "an id is a number" >&2; exit 2; }; grep -qxF "$1 $2" $F || echo "$1 $2" >> $F ;;
  "peer "*) [[ $2 =~ ^[A-Za-z0-9_]+=[A-Za-z0-9.-]+$ ]] || { echo "use NAME=HOST" >&2; exit 2; }; grep -qxF "peer $2" $F || echo "peer $2" >> $F ;;
  "drop "?*) grep -vE " ($(printf '%s' "$2" | sed 's/[^A-Za-z0-9_-]/./g'))(=.*)?$" $F > $F.tmp || true; mv $F.tmp $F
    grep -vE " job\.sh ($(printf '%s' "$2" | sed 's/[^A-Za-z0-9_-]/./g'))$" $J > $J.tmp || true; mv $J.tmp $J ;;
  *) sed -n '2,8p' "$0" >&2; exit 2 ;;
esac
# What supercronic runs: the image's jobs, then the agent's, and of those only well-formed job.sh lines. Anything else in the file never runs.
{ cat "$B/system.cron"; grep -E '^([0-9*/,-]+ ){5}job\.sh [A-Za-z0-9_-]+$' $J || true; } > /data/cron/crontab.tmp && mv /data/cron/crontab.tmp /data/cron/crontab
# shellcheck source=/dev/null
. $TG/.env
jq -n --arg o "$OWNER_TELEGRAM_ID" --rawfile f $F '($f | split("\n") | map(split(" "))) as $l
  | ($l | map(select(.[0] == "group") | .[1])) as $gs | ([$o] + ($l | map(select(.[0] == "sender") | .[1]))) as $who
  | {dmPolicy: "allowlist", allowFrom: ([$o] + $gs), groups: ($gs | map({key: ., value: {requireMention: false, allowFrom: $who}}) | from_entries), pending: {}}' > $TG/access.json.tmp && mv $TG/access.json.tmp $TG/access.json
[ "$1" = apply ] || echo "ok: $1 $2. Groups: $(jq -c '.groups | keys' $TG/access.json), heard there: $(jq -c '[.groups[].allowFrom[]] | unique' $TG/access.json)"
[ "$1" = apply ] || "$B/notify.sh" "⚙️ Setting changed${SSH_CONNECTION:+ by a fellow agent}: $1 $2. To undo it, ask me to drop $2." || echo "could not notify the owner" >&2
