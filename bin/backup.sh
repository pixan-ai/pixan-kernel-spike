#!/usr/bin/env bash
# Encrypted backup of the agent's memory, conversations, workspace and settings (docs/BACKUP.md).
#   backup.sh           make one backup now (the image's crontab does this every night)
#   backup.sh restore   bring the newest backup back into /data (start.sh does this on an empty volume when BACKUP_AGE_KEY is set)
# Does nothing unless BACKUP_REMOTE (an rclone remote, e.g. gdrive:agent-backups) and BACKUP_AGE_RECIPIENT (an age public key) are set.
# The data is encrypted here, before it leaves: the storage provider only ever holds what the owner's private key can open.
set -euo pipefail
[ -n "${BACKUP_REMOTE:-}" ] || exit 0
export RCLONE_CONFIG=/data/ssh/rclone.conf
if [ "${1:-}" = restore ]; then
  f=$(rclone lsf "$BACKUP_REMOTE" --include '*.tar.gz.age' | sort | tail -1); [ -n "$f" ] || { echo "no backup found in $BACKUP_REMOTE" >&2; exit 1; }
  rclone cat "$BACKUP_REMOTE/$f" | age -d -i <(printf '%s\n' "$BACKUP_AGE_KEY") | tar -C /data -xz
  echo "restored $f" >&2; exit 0
fi
# Left out: what the image or the variables rebuild at every start, and the keys.
# tar's exit status 1 only means a file changed while it was read (a live conversation): that is fine.
{ tar -C /data -cz --exclude=./config/plugins --exclude=./config/channels/telegram/.env --exclude=./ssh --exclude=./tui.log --exclude='./cron/*.err' . || [ $? = 1 ]; } \
  | age -r "$BACKUP_AGE_RECIPIENT" | rclone rcat "$BACKUP_REMOTE/$(date +%F-%H%M).tar.gz.age" \
  || { notify.sh "⚠️ Tonight's backup failed. Check BACKUP_REMOTE and the storage credentials." || true; exit 1; }
rclone delete "$BACKUP_REMOTE" --include '*.tar.gz.age' --min-age "${BACKUP_KEEP_DAYS:-14}d" || true
