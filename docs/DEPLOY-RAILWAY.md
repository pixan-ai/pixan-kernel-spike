# Deploy on Railway

Status: the Dockerfile builds and runs under Docker Desktop. The Railway steps below are the intended path and have not been verified end to end.

1. Create a project and a service from this repository (Dockerfile build; [`railway.json`](../railway.json) sets the builder and the restart policy).
2. Add a **volume** mounted at `/data` (one volume per service).
3. Set variables in the Railway dashboard (never in the repository):
   - `ANTHROPIC_API_KEY`
   - `TELEGRAM_BOT_TOKEN`
   - `OWNER_TELEGRAM_ID`
   - optional: `TZ`, `ANTHROPIC_MODEL`
4. Deploy and message the bot.

Notes:

- Railway bills per minute for CPU and memory. Long polling keeps a Serverless service awake, so leave Serverless off.
- Use a dedicated bot token. Do not reuse one that another process polls.
- Rotate the API key if it is ever pasted into a chat, log or screenshot.
