# Secrets: inventory and rotation

Secrets are passed as environment variables at run time and are never baked into the image or committed.

## Inventory

| Secret | What it grants | Where it lives | How to rotate |
|---|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Use of the owner's Claude subscription | Host environment variable | Run `claude setup-token` as the account owner, replace the variable, redeploy. Revoke the old one in the Claude account (see Anthropic's documentation) |
| `ANTHROPIC_API_KEY` | Pay-per-use API access; wins over the token if both are set | Host environment variable | Console: create a new key, delete the old one, replace the variable, redeploy |
| `TELEGRAM_BOT_TOKEN` | Full control of the bot | Host environment variable and `/data/config/channels/telegram/.env` (mode 600, rewritten at every start) | BotFather `/revoke`, set the new value, redeploy |
| `OWNER_TELEGRAM_ID` | Not secret. Who may talk to the bot | Host environment variable; `access.json` on the volume | Change the variable and redeploy: `start.sh` rebuilds `access.json` at every start |

## Rotate when

- a value was pasted into a chat, a log or a screenshot;
- someone with access left;
- the host or a vendor reports an incident;
- usage you cannot explain;
- after a suspected prompt-injection incident in which the agent had a shell.

## Order

1. Revoke at the issuer.
2. Set the new value on the host.
3. Redeploy or restart.
4. Verify without printing secrets: the start log says `oauth token: N chars, starts with sk-ant-oat01-: yes`, and the bot answers.
5. Look at the issuer's usage page for the window of exposure.

Never run `printenv` to check a value. A token copied from a phone can arrive truncated or with line breaks: `start.sh` removes whitespace and the log line above tells you the length.
