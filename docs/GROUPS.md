# Telegram groups

By default the bot only listens to its owner in private. In a group it has been told to join, it reads and can answer **everyone there, people and bots**. Two independent things must both be right.

## 1. Telegram side (the owner, in the app and BotFather)

- Add the bot to the group as a member.
- **Privacy mode.** By default a bot in a group only receives commands, mentions and replies to its own messages; plain messages never reach it. To let it read everything: BotFather `/setprivacy` → Disable, then **remove the bot from the group and add it again** (the change does not apply to groups it is already in). Making the bot an admin of the group has the same effect.
- **Bots reading other bots.** Needs Telegram's Bot-to-Bot mode enabled in BotFather for the bots involved (both sides).

## 2. Agent side

Tell the agent in private: "join the group -1001234567890". It applies the change itself and confirms ([SETTINGS.md](SETTINGS.md)). The variable below does the same from the host:

| Variable | Meaning |
|---|---|
| `TELEGRAM_GROUP_IDS` | Group chat ids the bot may take part in, separated by spaces, e.g. `-1001234567890` |

`start.sh` rebuilds the plugin's `access.json` from the settings at every start. In a listed group the bot receives every message, from every member, **without needing a mention**: it decides from the content whether it is being addressed (its instructions tell it to stay silent otherwise).

## Traps

- **The chat id changes when a group becomes a supergroup** (it takes the form `-100…`). The id in the web client's address bar can be the old one. Confirm with `getChat` (title and type) before blaming anything else.
- Being a member is not being authorised, and the reverse: the plugin silently drops messages from a group that is not listed.

## Read before enabling

- **Super-users.** Besides the owner, super-users may give the agent instructions in its groups. The owner or any existing super-user can name another ("make 123456789 a super-user", `config.sh admin ID`), and can ask an agent to name one on a fellow agent ([PEERS.md](PEERS.md)), so a team does not depend on one person. They get no private chat with the agent. The owner is told of each change. Trust is transitive: whoever you name can name others.
- **Everyone in the group can talk to the agent**, so only add it to groups whose members you trust. What separates the owner from the rest is an instruction, not a lock: the agent is told its owner's id at every start and told that only the owner and the super-users give instructions (settings, jobs, commands, private information). A persistent member can try to talk it out of that. The hard limits of the policy (denied tools and paths) apply to everybody the same.
- Everything written in the group enters the agent's session: more usage on the owner's Claude plan, in proportion to how busy the group is.
- Other members read the bot's answers, so do not use a group with people who should not see them.
- With several bots hearing each other, each one's messages enter the others' sessions: more usage, and a risk of bots answering each other in a loop. The instructions tell each agent to answer only when addressed and never to reply to a fellow bot's reply by default.
- Until this version only the owner and listed ids were heard in a group. `TELEGRAM_GROUP_SENDERS` and `config.sh sender` no longer exist; old `sender` lines in `/data/settings` are ignored.

## Verified

- In CI: the generated `access.json` for no groups, and for listed groups (open to every member); the owner's id reaching the session.
- On Railway (2026-11-11), reported by the owner: in a real group, two agents each read and answered ordinary members, super-users and each other.
- Not verified: that a member who is not a super-user is refused when asking for a setting change or private information.
