#!/usr/bin/env bash
# Claude running but the Telegram plugin gone: the agent looks alive and hears nothing. Run from the image's crontab.
# It only observes, tells the owner and restarts; it never types into the session. Two sightings in a row are needed.
D=/data/cron/deaf
pgrep -x script > /dev/null || { rm -f $D; exit 0; }  # Claude is not running (starting, stopping): nothing to judge
# The plugin writes its process id here when it starts polling.
kill -0 "$(cat /data/config/channels/telegram/bot.pid 2> /dev/null)" 2> /dev/null && { rm -f $D; exit 0; }
[ -e $D ] || { touch $D; exit 0; }  # first sighting: the plugin may still be starting
rm -f $D
notify.sh "⚠️ My Telegram channel was down while Claude was running. Restarting; the conversation continues." || true
pkill -x script
