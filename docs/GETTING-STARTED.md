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

## Everything you can configure

Three places, and nothing else. What is not listed here is fixed on purpose (the 4:00 recycle, the limits of the policy, the size of the logs).

### On the host: variables

Set once, at installation. Changing one restarts the agent.

| Variable | Default | What it does | More |
|---|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | required, or the next | Claude subscription token | step 2 |
| `ANTHROPIC_API_KEY` | | Console API key instead of the subscription; wins if both are set | step 2 |
| `TELEGRAM_BOT_TOKEN` | required | This agent's own bot | step 1 |
| `OWNER_TELEGRAM_ID` | required | The owner: the only private chat, and who gets every notice | step 1 |
| `TZ` | `UTC` | Time zone for jobs, the nightly recycle and the dates the agent sees | [CRON.md](CRON.md) |
| `ANTHROPIC_MODEL` | Claude's default | Pin the model | |
| `CLAUDE_FLAGS` | empty | Extra flags for `claude`, e.g. `--advisor claude-opus-5-5` | |
| `TELEGRAM_GROUP_IDS` | empty | Groups to join from the first start (the same as telling the agent) | [GROUPS.md](GROUPS.md) |
| `IDLE_SLEEP_MINUTES` | empty = always on | Sleep after this many quiet minutes | [SLEEP.md](SLEEP.md) |
| `DOORBELL_URL` | `https://` + `RAILWAY_PUBLIC_DOMAIN` | Public address Telegram calls to wake a sleeping agent. Needed outside Railway | [SLEEP.md](SLEEP.md) |
| `RAILWAY_PUBLIC_DOMAIN` | set by Railway | Not yours to set: Railway provides it when the service has a public domain | [SLEEP.md](SLEEP.md) |
| `PORT` | `8080` | Port the wake-up listener uses | [SLEEP.md](SLEEP.md) |
| `BACKUP_REMOTE` | empty = no backups | Where the nightly encrypted backup goes | [BACKUP.md](BACKUP.md) |
| `BACKUP_AGE_RECIPIENT` | | Public key the backups are encrypted to | [BACKUP.md](BACKUP.md) |
| `RCLONE_CONF` | | Credentials for the backup storage (secret) | [BACKUP.md](BACKUP.md) |
| `BACKUP_KEEP_DAYS` | `14` | Days of backups kept | [BACKUP.md](BACKUP.md) |
| `BACKUP_AGE_KEY` | | Only to restore onto an empty volume; remove it afterwards | [BACKUP.md](BACKUP.md) |
| `PEER_PUBLIC_KEYS` | empty = nobody | Keys of the fellow agents allowed to look at this one and set its groups and super-users | [PEERS.md](PEERS.md) |
| `PEER_SSH_KEY` | | Key this agent uses to look at others | [PEERS.md](PEERS.md) |
| `PEERS` | empty | Fellow agents by name, `Name=host` separated by spaces (the same as telling the agent) | [PEERS.md](PEERS.md) |
| `SCREEN_MIRROR` | empty = off | Seconds between copies of the agent's screen to the host log. Shows conversations to whoever reads the log | [THREAT-MODEL.md](THREAT-MODEL.md) |
| `JOB_TIMEOUT` | `900` | Seconds a scheduled job or the nightly dream may take | [CRON.md](CRON.md) |
| `MEM_LIMIT` | `4g` | Memory cap, with Docker Compose only | |

### By talking to the agent

Applied at once, kept on the volume, and confirmed to the owner in private. The owner or a super-user asks.

| Setting | Say | Undo |
|---|---|---|
| A group to take part in | "únete al grupo -100…" | "sal del grupo -100…" |
| A super-user | "haz super-usuario a 123456789" | "quita a 123456789" |
| A fellow agent, by name | "tu compañero Junior está en agent2.railway.internal" | "olvida a Junior" |
| A scheduled job, to you or to a group | "cada día a las 8 mándame …" | "quita la tarea …" |
| Something to remember | "recuerda que …" | "olvida que …" |

"¿Qué ajustes tienes?" lists them ([SETTINGS.md](SETTINGS.md)).

## Self-improvement: installing skills and tools (decided, not built yet)

As of 2026-11-12 these rules are decided; the mechanism is not in the image yet.

- Only a super-user can ask the agent to install a new skill or tool (for example "baja elevenlabs" or "learn to make a PowerPoint"). The owner is one more super-user. Anyone else who asks is refused.
- When a super-user asks, it runs at once. There is no owner approval step. The owner gets a private Telegram notice afterwards, the same as for settings ([SETTINGS.md](SETTINGS.md)).
- An install applies only to that agent. A super-user can explicitly ask to replicate it to several agents.
- Python 3 will be added to the kernel image (it is not there today; the base is oven/bun Debian, which already has Bun for JavaScript and TypeScript). Still under evaluation, not decided: `python3-venv`/`uv`, `ffmpeg`, `poppler-utils`, `pandoc`.

How it is planned to work: skills live on the volume (`/data`); Python and Node packages go in `/data/tools`, static binaries in `/data/bin`; system packages (`apt`) only arrive through a pull request to the image. Enforcement is a lock, not an instruction: a `UserPromptSubmit` hook checks the sender against the super-users and opens a per-turn permission; a `PreToolUse` hook blocks `pip`/`npm`/`uv` installs and writes to `/data/bin` and the skills folder unless that permission is open. Every install is recorded in `/data/tools.json` (what, who asked, when, which agents) and `start.sh` reinstalls from it. API keys (for example ElevenLabs) never go through chat; the admin sets them as host variables.

### Files on the volume

| File | What it is | Who writes it |
|---|---|---|
| `/data/workspace/CLAUDE.md` | This agent's own lasting instructions: name, role, tone, whether it supervises others | The agent, when you ask ("anota en tu CLAUDE.md que …") |
| `/data/workspace/MEMORY.md` | What it remembers | The agent, and the nightly dream ([MEMORY.md](MEMORY.md)) |

The rules common to every agent (`/etc/claude-code/`) come with the image and cannot be changed from inside.

## What the image contains

Every agent gets these, ready for its skills (decided 2026-11-12):

| Tool | Made by | For |
|---|---|---|
| Python 3 (`python3`) | Python Software Foundation | Most skills: PowerPoint, Excel, PDFs, charts, ElevenLabs and other APIs |
| `uv`, `uvx` | Astral | Installing Python packages and tools, fast and isolated (pinned by version and checksum) |
| `ffmpeg` | FFmpeg project | Voice notes, audio, and frames from a video, so the agent can "see" one |
| `pdftotext` and the rest of `poppler-utils` | Poppler (freedesktop.org) | Reading PDFs |
| `pandoc` | John MacFarlane and contributors | Converting between Word, Markdown, HTML and PDF |
| `unzip` | Info-ZIP | Opening zip files and skill packages |
| Time zones (`tzdata`) | IANA | Jobs and logs in the `TZ` you set; already in the Debian base |

Also there: Bun (JavaScript and TypeScript), `git`, `jq`, `curl`, `rclone`, `age`, `supercronic`; Claude Code only in the agent image, never in the published `base` ([PRODUCT-IMAGE.md](PRODUCT-IMAGE.md)). Python packages (for example `python-pptx`) are not in the image: they are installed per agent. These tools add about 750 MB to the image, most of it `ffmpeg`'s libraries and `pandoc`.

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
