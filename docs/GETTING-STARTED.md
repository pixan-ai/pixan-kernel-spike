# Getting started: from nothing to an agent that answers

For someone who has never run this. About 20 minutes. You need a Telegram account and a Claude subscription (or an Anthropic API key).

After the installation everything else is done **by talking to the agent**: adding groups, scheduling jobs, pointing it at fellow agents. You come back to the host only to change a credential.

## 1. Create the bot (Telegram, 3 minutes)

1. Talk to [@BotFather](https://t.me/BotFather), send `/newbot`, choose a name and a username. Keep the **token** it gives you.
2. Each agent needs **its own bot**. Never reuse a token that another program is using.
3. Find your numeric Telegram id: talk to [@userinfobot](https://t.me/userinfobot). Keep the **id**.

## 2. Get the Claude credential (your computer, 3 minutes)

- **Subscription (recommended):** install Claude Code, run `claude` once and log in, then run `claude setup-token` in the terminal (not inside Claude). Keep the token that starts with `sk-ant-oat01-`.
- **API key instead:** create one in the [Anthropic console](https://console.anthropic.com/). Billed per use.

Copy the value with a copy button, not by selecting text: a truncated token gives a bot that shows "typing…" and never answers.

## 3. Deploy

### Railway (the quick way)

1. New project → deploy from this repository.
2. Service **Settings**: Dockerfile Path `Dockerfile`, Restart Policy **Always**.
3. Add a **volume** mounted at `/data`.
4. **Variables**:

| Variable | Value |
|---|---|
| `TELEGRAM_BOT_TOKEN` | from step 1 |
| `OWNER_TELEGRAM_ID` | from step 1 |
| `CLAUDE_CODE_OAUTH_TOKEN` | from step 2 (or `ANTHROPIC_API_KEY`, not both) |
| `RAILWAY_RUN_UID` | `0` |
| `TZ` | your time zone, e.g. `America/Mexico_City` |

5. Press **Deploy** (variables stay pending until you do).

Details and notes: [DEPLOY-RAILWAY.md](DEPLOY-RAILWAY.md). Cost: an agent that is always on uses about 0.3 to 0.7 GB of memory, billed by the minute. 

**Optional: sleep when idle.** Off by default: the agent is always on. To pay only while it works, add the variable `IDLE_SLEEP_MINUTES` (for example `10`) and give the service a public address; the agent then stops after that many quiet minutes and wakes on the next message, a few seconds later. Remove the variable to go back to always on. Steps and limits: [SLEEP.md](SLEEP.md).

### Your own server or computer (Docker)

```bash
git clone https://github.com/pixan-ai/pixan-kernel-spike && cd pixan-kernel-spike
cp .env.example .env    # fill in the same values as above
docker compose up -d --build
```

A fixed-price server suits several agents better than per-minute billing, and a host that allows user namespaces can add the hard isolation that Railway cannot ([THREAT-MODEL.md](THREAT-MODEL.md)).

## 4. Check that it works

1. The start log shows `oauth token: N chars, starts with sk-ant-oat01-: yes`. N is about 108; a much smaller number means a truncated token.
2. Send the bot "Hola". It answers within a few seconds.
3. Ask "¿Cómo te llamas y cuál es tu id?": it knows its own bot name.

`/start` shows pairing instructions from the plugin. Ignore them: only the owner is allowed, and no pairing is needed.

## 5. What to tell the agent next

| You say | What happens | More |
|---|---|---|
| "Mándame cada día a las 8 un resumen de …" | It schedules a job; you get a notice | [CRON.md](CRON.md) |
| "Únete al grupo -100…" | It reads and answers everyone in that group, people and bots, no mention needed | [GROUPS.md](GROUPS.md) |
| "Tu compañero X está en …" / "¿Qué está haciendo X?" | It remembers a fellow agent and can look at its screen | [PEERS.md](PEERS.md) |
| "Recuerda que …" / "¿Qué recuerdas de …?" | It keeps it in its memory. Every night it consolidates the day and starts a clean conversation | [MEMORY.md](MEMORY.md) |
| "Cada día a las 9 publica en el grupo -100… lo más relevante de ayer" | The daily council: every agent of a team reports in one group, and they read each other | [MEMORY.md](MEMORY.md#the-daily-council) |
| "Haz super-usuario a 123456789" | That person can also give it instructions in its groups | [GROUPS.md](GROUPS.md) |
| "Mándame el archivo …" | It attaches files from its workspace, or ones it received. It cannot attach keys, credentials or its configuration | [THREAT-MODEL.md](THREAT-MODEL.md) |
| "Anota en tu CLAUDE.md que …" | Its own lasting instructions (name, role, tone) | |

Every change it makes to its own settings is confirmed to you in private ([SETTINGS.md](SETTINGS.md)).

## 6. What to expect day to day

- **Every night at 4:00** the agent restarts, consolidates the day into its memory and begins a new conversation. It is away for a minute or two. The next day it knows what it kept, not the literal wording of yesterday.
- **Every change to its settings** (a group, a super-user, a job, a fellow agent) reaches you as a private notice, whoever asked for it.
- **If you turned on the optional sleep** ([SLEEP.md](SLEEP.md)), the first message after a quiet period takes a few seconds longer.
- **In groups** it answers when addressed or when a message is for everyone, and stays silent otherwise. Only you and the super-users give it instructions there.

## 7. Before you rely on it

- **Backups:** off until you set them up. [BACKUP.md](BACKUP.md).
- **What it can and cannot protect:** [SECURITY.md](../SECURITY.md) and [THREAT-MODEL.md](THREAT-MODEL.md). On Railway the protection is policy and judgment, not a sandbox.
- **Rotating a credential:** [SECRETS.md](SECRETS.md).

## If something is wrong

| Symptom | Likely cause |
|---|---|
| "typing…" and no answer | Claude credential truncated or expired (see the start log) |
| No reaction at all | Wrong bot token, or variables not deployed. The log says `Telegram rejected TELEGRAM_BOT_TOKEN` for a bad token |
| Silent in a group | The bot was added before privacy mode was disabled, or the group id changed when it became a supergroup ([GROUPS.md](GROUPS.md)) |
| It does not remember something from yesterday | The nightly memory left it out. Ask "¿qué recuerdas de …?", and say "recuerda que …" for what must stay ([MEMORY.md](MEMORY.md)) |
| A job's answer came to you instead of the group | The agent is no longer in that group; tell it to join again |
| It refuses to send a file | The file is outside its workspace; ask it to copy what you need there, if it is not a credential |
| It never sleeps although sleep is on | The log says `not sleeping: Telegram did not accept the webhook`: the public address is missing or wrong ([SLEEP.md](SLEEP.md)) |
| "My Telegram channel was down … Restarting" | The watchdog saw the plugin gone and restarted Claude; one message is normal, a stream of them is a bug to report |
