# Settings the agent changes itself

The host's variables are for installation: credentials, the owner, keys. Day-to-day changes are made by telling the agent in chat. It runs `config.sh`, which validates the value, stores it in `/data/settings` on the volume, applies it at once (no restart) and **sends the owner a private message every time**.

| Tell the agent to… | It runs | Effect |
|---|---|---|
| take part in a Telegram group | `config.sh group -1001234567890` | Listens in that group, no mention needed |
| also listen to a user or bot in its groups | `config.sh sender 123456789` | That id is heard in every listed group (never in private) |
| remember a fellow agent | `config.sh peer Junior=agent2.railway.internal` | `peer.sh look junior` works |
| undo any of these | `config.sh drop VALUE` | Removes the lines with that value |

`TELEGRAM_GROUP_IDS` and `TELEGRAM_GROUP_SENDERS` still work: `start.sh` adds them to the same file at every start.

## One agent setting another's groups

Any agent that can look at a fellow agent ([PEERS.md](PEERS.md)) can also add or drop **groups and senders** on it: `peer.sh look junior "group -1001234567890"`. The change is made by the other agent's own `config.sh`, so **its** owner gets the notice, marked "by a fellow agent".

Technically every agent holding a listed key can do this. Who *should* is a matter of instructions: the managed `CLAUDE.md` tells an agent to change a fellow agent's settings only when its own workspace `CLAUDE.md` names it as supervisor, or its owner asks directly. Put that line in the supervisor's `/data/workspace/CLAUDE.md`.

## What cannot be changed this way

The owner, the Claude and Telegram credentials and the peer keys. `config.sh` accepts only the three settings above; over SSH only `group`, `sender` and `drop` with a numeric id.

## Read before relying on it

- This lets the agent widen who it listens to. An agent can be talked into it by content it reads (prompt injection). The barrier is the notice: an unexpected "Setting changed" message means someone or something asked for it. Undo it and look at what the agent was reading.
- The notice is sent after the change, not before. There is no approval step.
- A leaked peer key now allows adding groups and senders on the agents that list it, not only reading their screens.

## Verified

- In CI (`tests/config_test.sh`, `tests/peer_test.sh`): each setting, the notice, refusal of anything else, and a change made by a fellow agent over a real SSH connection.
- On Railway (2026-11-10): one agent added a group to the other over the private network; the other's owner received the notice "by a fellow agent".
