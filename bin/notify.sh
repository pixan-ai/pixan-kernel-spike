#!/usr/bin/env bash
# Sends one Telegram message: to the owner, or to the chat given as a second argument. Usage: notify.sh TEXT [CHAT_ID]
# Credentials come from the plugin's private file; the URL goes through stdin so the token never shows in a process list.
set -euo pipefail
# shellcheck source=/dev/null
. /data/config/channels/telegram/.env
printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN" \
  | curl -fsS -m 20 -K - -d chat_id="${2:-$OWNER_TELEGRAM_ID}" --data-urlencode text="${1:0:4000}" > /dev/null
