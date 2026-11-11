# Deploy on Railway

Status: verified end to end on Railway (November 2026) with a Claude Max subscription token.

1. Create a project and a service from this repository. In the service's **Settings**: set **Dockerfile Path** to `Dockerfile` (this selects the Dockerfile builder) and **Restart Policy** to **Always**. Optional **Watch Paths**: `Dockerfile`, `bin/**`, `policy/**`, `seed/**`, so documentation and CI changes do not restart the agent.
2. Add a **volume** mounted at `/data` (one volume per service).
3. Set variables in the Railway dashboard (never in the repository):
   - `CLAUDE_CODE_OAUTH_TOKEN` (subscription, from `claude setup-token`) **or** `ANTHROPIC_API_KEY` (Console, per use). Not both: the API key wins.
   - `TELEGRAM_BOT_TOKEN`
   - `OWNER_TELEGRAM_ID`
   - optional: `TZ`, `ANTHROPIC_MODEL`
   - `RAILWAY_RUN_UID=0`: Railway volumes are owned by root. The entrypoint only fixes `/data` ownership as root, then drops to the `agent` user (uid 1001).
4. Deploy and message the bot.

Notes:

- This repository carries no `railway.json`: Railway deprecated Config as Code (it stops reading `railway.json` and `railway.toml` on 2026-12-01, and new services cannot use it). The service settings above are the configuration. `.railway/railway.ts` (Infrastructure as Code) is the official alternative for teams that manage several services.

- Railway bills per minute for CPU and memory. Long polling keeps a Serverless service awake, so leave Serverless off.
- Use a dedicated bot token. Do not reuse one that another process polls.
- Rotate the API key if it is ever pasted into a chat, log or screenshot.
