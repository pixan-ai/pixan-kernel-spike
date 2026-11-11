# Backup and restore

Opt-in. Every night at 03:30 the agent's memory, conversations, workspace, settings and scheduled jobs are packed, **encrypted inside the container** and sent to storage the owner controls. The storage provider only ever holds a file that the owner's private key can open.

Standard tools, no code of ours beyond `bin/backup.sh`: [rclone](https://rclone.org) for the transfer (it speaks Google Drive, Cloudflare R2 and many others with the same command) and [age](https://age-encryption.org) for the encryption.

## Set-up (once, in the host's variables)

1. Make a key pair on your own computer: `age-keygen -o agent-backup.key`. It prints a public key (`age1…`). **Keep the file safe and off the host**: without it no backup can be read, by anyone.
2. Set:

| Variable | Value |
|---|---|
| `BACKUP_AGE_RECIPIENT` | The public key, `age1…` (not secret) |
| `BACKUP_REMOTE` | Where to store them, as an rclone remote and folder, e.g. `gdrive:agent-backups` |
| `RCLONE_CONF` | The rclone configuration for that remote (secret). `start.sh` writes it to a private file |
| `BACKUP_KEEP_DAYS` | Optional. Days to keep (default 14) |

### Google Drive (default)

On your computer run `rclone config`, create a remote named `gdrive` of type `drive` (scope `drive.file`, so rclone only sees the files it creates), and paste the resulting section of `rclone.conf` into `RCLONE_CONF`. A service account with a shared folder works as well and does not expire.

### Cloudflare R2 (alternative)

Create a bucket and an API token limited to it, then:

```
[r2]
type = s3
provider = Cloudflare
access_key_id = …
secret_access_key = …
endpoint = https://<account-id>.r2.cloudflarestorage.com
```

with `BACKUP_REMOTE=r2:<bucket>/agent-backups`.

## What is in a backup

Everything under `/data` except what the image or the variables rebuild at every start (the plugin, the Telegram credentials file, the screen log) and the keys in `/data/ssh`.

## Restore

On a **new, empty volume**: set the same `BACKUP_REMOTE` and `RCLONE_CONF`, add `BACKUP_AGE_KEY` with the private key (the `AGE-SECRET-KEY-…` line), and deploy. `start.sh` restores the newest backup before starting. A volume that already has data is never overwritten. **Remove `BACKUP_AGE_KEY` afterwards**: while it is set, a shell in the container can read it.

## If a backup fails

The owner gets a Telegram message. A backup that has never been restored is a hope, not a backup: try a restore once into a scratch service.

## Verified

- In CI (`tests/backup_test.sh`), with the real rclone and age against a local folder: encrypted at rest, restore of memory, settings and jobs, exclusions, a wrong key restores nothing, retention, failure notice.
- Not verified yet: Google Drive and R2 themselves, and a restore on Railway.
