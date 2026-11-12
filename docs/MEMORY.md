# Memory: the daily dream

A conversation that never ends gets more expensive with every message, because the whole of it is read again each time. So once a day the agent **dreams**: it writes down what matters, and the next conversation starts clean.

## What happens

1. Every night at 4:00 the agent is recycled (`bin/system.cron`).
2. Before Claude starts again, `bin/dream.sh` gives a separate, short-lived Claude everything that was said since the last dream: the messages received and the agent's replies, without tool results.
3. That Claude rewrites `/data/workspace/MEMORY.md` (who is who, decisions, commitments and open tasks, lessons; at most 150 lines) and writes the day's account to `/data/workspace/memory/YYYY-MM-DD.md`.
4. The agent starts a **new conversation**. A hook shows it `MEMORY.md` at the start of every session, so it knows what it kept.

An agent that sleeps when idle ([SLEEP.md](SLEEP.md)) dreams when it goes to sleep or wakes, if its last dream was more than 20 hours ago. Nothing said since the last dream means no dream.

## What the agent keeps and loses

- Kept: what the dream wrote in `MEMORY.md`, and everything in `/data/workspace`. The agent can read the daily files in `memory/` when asked about a past day.
- Lost: the literal wording of yesterday's conversation. If something must not be forgotten, tell the agent "remember that …": it writes it to `MEMORY.md` at once.
- The agent may edit `MEMORY.md` itself at any time. The dream merges, it does not start from zero.

## Read before relying on it

- The dream is a summary made by a model: it can leave out something you cared about. Check `MEMORY.md` now and then, or ask the agent "what do you remember about …".
- If the dream fails (no quota, timeout), nothing is lost: the conversation simply continues and the dream is tried again at the next start. The error is in `/data/cron/dream.err`.
- **A memory that outgrows what is shown.** Seen after months with earlier agents: the index passed the size that is loaded, the end was cut in silence and the agent lost entries without knowing. Here the dream rewrites the index every night to at most 150 lines, and if the file is ever over 20000 characters the agent is told at the start of the session that it is missing the end and must shorten it.
- The dream uses the owner's Claude plan: one short run a day.
- The agent is unavailable for a minute or two while it dreams.
- `MEMORY.md` is in the backup ([BACKUP.md](BACKUP.md)) with the rest of the workspace.

## The daily council

With several agents working for the same client, a daily council keeps them, and you, in step. It needs no code: a Telegram group and one scheduled job per agent.

1. Create a Telegram group, add every agent and the people who should read it ([GROUPS.md](GROUPS.md)).
2. Tell each agent, in private: "join the group -100…".
3. Tell each agent: "every day at 9:00 post in the group -100… the most relevant from yesterday: what you did, what is pending, what you need from the others. Five lines at most." It schedules a job ([CRON.md](CRON.md)) that reads its memory and posts.

Each agent reads what the others post, since in a group it hears everyone, and its next dream keeps what matters. Stagger the times by a few minutes (9:00, 9:05, …) so that each one has read the previous ones.

## Verified

- In CI (`tests/dream_test.sh`): what the dream is given, that it dreams once a day and only when something was said, that a failed dream leaves the conversation intact; the memory reaching the new session (`tests/policy_test.sh`); the dream running before Claude starts (`tests/start_test.sh`).
- With a real Claude, outside a container (2026-11-12): a two-message conversation became a correct `MEMORY.md` and a daily file, using only the file tools.
- Not verified yet on a real host: the dream under the managed policy, the quality of what it keeps, and a council in a real group.
