# Peer view: one agent looks at another

Opt-in. Lets a fellow agent (or its owner, through it) see what this agent is doing, and add or drop its Telegram groups ([SETTINGS.md](SETTINGS.md)). Nothing else. It is the mechanism used in the earlier pixan stacks (SSH with a forced command), rebuilt with standard tools and no extra code beyond `bin/peer.sh`.

## What a peer can do

| Request | Returns |
|---|---|
| `screen` (default) | The last readable lines of this agent's Claude Code screen |
| `status` | Whether Claude is running and the last heartbeat |
| `denials` | The loaded policy checks and the latest tool errors |
| `transcript` | The last 40 messages of the latest conversation: what the owner wrote and what the agent answered (each cut at 600 characters). No tool results |
| `group ID`, `drop ID` | Changes this agent's groups through its own `config.sh`; this agent's owner is told |
| anything else | Refused |

No shell, no terminal, no port forwarding, no file transfer: the SSH server runs one fixed command per connection (`ForceCommand`), as the unprivileged `agent` user, on port 2222. The command does not receive this agent's environment, so it cannot return its tokens.

## Set-up for two agents, A looks at B

1. On any machine: `ssh-keygen -t ed25519 -N '' -f peer_key` creates `peer_key` (private) and `peer_key.pub` (public).
2. On **B** (the one being looked at), set `PEER_PUBLIC_KEYS` to the content of `peer_key.pub` (one key per line for several peers).
3. On **A** (the one looking), set `PEER_SSH_KEY` to the content of `peer_key`.
4. Redeploy both. On A: `peer.sh look B-HOST`, where `B-HOST` is B's private address (on Railway, `<service>.railway.internal`).

For both to see each other, set both variables on both.

## Names instead of addresses

Set `PEERS` on the agent that looks, as `name=host` pairs separated by spaces, for example `Junior=agent2.railway.internal`. Then `peer.sh look junior` works (names are case-insensitive), and the agent can find a fellow agent when the owner names it.

## Read before enabling

- **The screen is the owner's conversation, and `transcript` returns more of it.** Whoever holds a listed key can read what B is discussing with its owner.
- `PEER_SSH_KEY` is a secret in A's environment. On hosts without a hard floor (Railway), A's own shell can read it. A leaked key gives read access to peers' screens, nothing more.
- Do not publish port 2222 to the internet; use the host's private network.
- Without `PEER_PUBLIC_KEYS` no SSH server starts.

## Verified

- In CI, inside the image, with a real server and client: a listed key sees the screen; other commands, chained commands and shell requests are refused; an unlisted key sees nothing.
- On Railway (2026-11-10): one agent read the other's screen and status over the private network (`agent2.railway.internal`).
- Not verified yet on Railway: `transcript` against a real session file, and names from `PEERS`.
