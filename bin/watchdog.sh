#!/usr/bin/env bash
# Two checks, run every five minutes from the image's crontab: a message left without an end of turn, and
# Claude running but the Telegram plugin gone (the agent looks alive and hears nothing).
# It only observes, tells the owner and restarts; it never types into the session. Two sightings in a row are needed.
D=/data/cron/deaf
# A message came in (UserPromptSubmit hook) and the turn has not ended (Stop hook) after ten minutes: say so, once.
P=/data/cron/pending
if [ -e $P ] && [ ! -e $P.told ] && (( $(date +%s) - $(cat $P) > 600 )); then
  touch $P.told; notify.sh "⏳ I received a message more than 10 minutes ago and have not finished with it. I may be on a long task, or stuck." || true
fi
pgrep -x script > /dev/null || { rm -f $D; exit 0; }  # Claude is not running (starting, stopping): nothing to judge
# The plugin writes its process id here when it starts polling.
kill -0 "$(cat /data/config/channels/telegram/bot.pid 2> /dev/null)" 2> /dev/null && { rm -f $D; exit 0; }
[ -e $D ] || { touch $D; exit 0; }  # first sighting: the plugin may still be starting
rm -f $D
notify.sh "⚠️ My Telegram channel was down while Claude was running. Restarting; the conversation continues." || true
pkill -x script
