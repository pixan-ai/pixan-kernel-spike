#!/usr/bin/env bash
# Settings an agent may change itself when its owner asks in chat (docs/SETTINGS.md). Applied at once, and the owner is told every time.
#   config.sh group ID       take part in this Telegram group
#   config.sh sender ID      also listen to this user or bot in the groups
#   config.sh peer NAME=HOST remember a fellow agent's private address
#   config.sh drop VALUE     remove the lines with this value
#   config.sh show | apply   print the settings | rebuild the plugin's access list without changing anything (start.sh)
# Nothing else can be set here: owner, tokens and keys only come from the host's variables.
set -euo pipefail
F=/data/settings; TG=/data/config/channels/telegram; touch $F
case "${1:-} ${2:-}" in
  "show ") exec cat $F ;;
  "apply ") ;;
  "group "*|"sender "*) [[ $2 =~ ^-?[0-9]+$ ]] || { echo "an id is a number" >&2; exit 2; }; grep -qxF "$1 $2" $F || echo "$1 $2" >> $F ;;
  "peer "*) [[ $2 =~ ^[A-Za-z0-9_]+=[A-Za-z0-9.-]+$ ]] || { echo "use NAME=HOST" >&2; exit 2; }; grep -qxF "peer $2" $F || echo "peer $2" >> $F ;;
  "drop "?*) grep -vE " ($(printf '%s' "$2" | sed 's/[^A-Za-z0-9_-]/./g'))(=.*)?$" $F > $F.tmp || true; mv $F.tmp $F ;;
  *) sed -n '2,8p' "$0" >&2; exit 2 ;;
esac
# shellcheck source=/dev/null
. $TG/.env
jq -n --arg o "$OWNER_TELEGRAM_ID" --rawfile f $F '($f | split("\n") | map(split(" "))) as $l
  | ($l | map(select(.[0] == "group") | .[1])) as $gs | ([$o] + ($l | map(select(.[0] == "sender") | .[1]))) as $who
  | {dmPolicy: "allowlist", allowFrom: ([$o] + $gs), groups: ($gs | map({key: ., value: {requireMention: false, allowFrom: $who}}) | from_entries), pending: {}}' > $TG/access.json
[ "$1" = apply ] || echo "ok: $1 $2. Groups: $(jq -c '.groups | keys' $TG/access.json), heard there: $(jq -c '[.groups[].allowFrom[]] | unique' $TG/access.json)"
[ "$1" = apply ] || "$(dirname "$(readlink -f "$0")")/notify.sh" "⚙️ Setting changed${SSH_CONNECTION:+ by a fellow agent}: $1 $2. To undo it, ask me to drop $2." || echo "could not notify the owner" >&2
