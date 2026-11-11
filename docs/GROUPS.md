# Telegram groups

By default the bot only listens to its owner in private. To use it in a group, two independent things must both be right.

## 1. Telegram side (the owner, in the app and BotFather)

- Add the bot to the group as a member.
- **Privacy mode.** By default a bot in a group only receives commands, mentions and replies to its own messages; plain messages never reach it. To let it read everything: BotFather `/setprivacy` → Disable, then **remove the bot from the group and add it again** (the change does not apply to groups it is already in). Making the bot an admin of the group has the same effect.
- **Bots reading other bots.** Needs Telegram's Bot-to-Bot mode enabled in BotFather for the bots involved, and each bot's id listed in the other's `TELEGRAM_GROUP_SENDERS`.

## 2. Deployment side (variables)

| Variable | Meaning |
|---|---|
| `TELEGRAM_GROUP_IDS` | Group chat ids the bot may take part in, separated by spaces, e.g. `-1001234567890` |
| `TELEGRAM_GROUP_SENDERS` | Extra user or bot ids it listens to in those groups, besides the owner. Empty = the owner only |

`start.sh` rebuilds the plugin's `access.json` from these variables at every start. In a listed group the bot receives every message from the allowed senders, **without needing a mention**: it decides from the content whether it is being addressed (its instructions tell it to stay silent otherwise).

A bot's id is the number before the colon in its token; `getMe` also returns it.

## Traps

- **The chat id changes when a group becomes a supergroup** (it takes the form `-100…`). The id in the web client's address bar can be the old one. Confirm with `getChat` (title and type) before blaming anything else.
- Being a member is not being authorised, and the reverse: the plugin silently drops messages from a group that is not listed.

## Read before enabling

- Only the listed senders are heard. Other members of the group can read the bot's answers, so do not use a group with people who should not see them.
- With several bots hearing each other, each one's messages enter the others' sessions: more usage, and a risk of bots answering each other in a loop. The instructions tell each agent to answer only when addressed and never to reply to a fellow bot's reply by default.
- Text from other senders is untrusted input, like any content the agent reads.

## Verified

- In CI: the generated `access.json` for no groups, and for listed groups and senders.
- Not verified yet on Railway: a real group with two bots.
