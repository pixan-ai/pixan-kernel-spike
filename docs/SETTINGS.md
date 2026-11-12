# Settings the agent changes itself

The host's variables are for installation: credentials, the owner, keys. Day-to-day changes are made by telling the agent in chat. It runs `config.sh`, which validates the value, stores it in `/data/settings` on the volume, applies it at once (no restart) and **sends the owner a private message every time**.

| Tell the agent to… | It runs | Effect |
|---|---|---|
| take part in a Telegram group | `config.sh group -1001234567890` | Reads and answers everyone in that group, no mention needed |
| let someone else give it instructions | `config.sh admin 123456789` | That Telegram id is a super-user in the agent's groups. The owner or any existing super-user names them |
| remember a fellow agent | `config.sh peer Junior=agent2.railway.internal` | `peer.sh look junior` works |
| run a prompt on a schedule | `config.sh job "0 8 * * *" news "Summarise…"` | See [CRON.md](CRON.md) |
| undo any of these | `config.sh drop VALUE` | Removes the lines with that value |

Super-users also decide what the agent installs (packages, tools, skills): see [GETTING-STARTED.md](GETTING-STARTED.md#self-improvement-installing-skills-and-tools).

`TELEGRAM_GROUP_IDS` still works: `start.sh` adds it to the same file at every start.

## One agent setting another's groups

Any agent that can look at a fellow agent ([PEERS.md](PEERS.md)) can also add or drop **groups and super-users** on it: `peer.sh look junior "group -1001234567890"`. The change is made by the other agent's own `config.sh`, so **its** owner gets the notice, marked "by a fellow agent".

Technically every agent holding a listed key can do this. Who *should* is a matter of instructions: the managed `CLAUDE.md` tells an agent to change a fellow agent's settings only when its own workspace `CLAUDE.md` names it as supervisor, or its owner asks directly. Put that line in the supervisor's `/data/workspace/CLAUDE.md`.

## What cannot be changed this way

The owner, the Claude and Telegram credentials and the peer keys. `config.sh` accepts only the settings above; over SSH only `group`, `admin` and `drop` with a numeric id.

## Read before relying on it

- This lets the agent widen who it listens to: adding a group means hearing every member of it ([GROUPS.md](GROUPS.md)). An agent can be talked into it by content it reads (prompt injection). The barrier is the notice: an unexpected "Setting changed" message means someone or something asked for it. Undo it and look at what the agent was reading.
- The notice is sent after the change, not before. There is no approval step.
- A leaked peer key allows adding groups and super-users on the agents that list it, not only reading their screens.

## Verified

- In CI (`tests/config_test.sh`, `tests/peer_test.sh`): each setting, the notice, refusal of anything else, and a change made by a fellow agent over a real SSH connection.
- On Railway (2026-11-10): one agent added a group to the other over the private network; the other's owner received the notice "by a fellow agent".
