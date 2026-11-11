# Sleep when idle, wake on a message

Opt-in. An agent listens to Telegram by asking it for messages without pause, so to its host it always looks busy and is billed around the clock, mostly for memory. With `IDLE_SLEEP_MINUTES` set, an agent nobody is talking to stops costing.

## How it works

1. After `IDLE_SLEEP_MINUTES` without activity in the conversation, `start.sh` stops Claude.
2. `doorbell.sh` tells Telegram to call this service when a message arrives (a webhook, protected by a secret only Telegram and the agent know) and waits. Nothing talks to the network any more, so a host that suspends idle containers (Railway Serverless) suspends this one.
3. A message arrives. Telegram calls; the host wakes the container if it was suspended. The call is answered **503**, which makes Telegram keep the message.
4. The webhook is removed and Claude starts with `--continue`. The **official plugin** receives the message the way it always does, by polling.

The doorbell never reads or forwards a message. That is why a message cannot be delivered twice, however often Telegram retries the call, and why messages sent in a row arrive once each, in order.

## Set-up

| Variable | Value |
|---|---|
| `IDLE_SLEEP_MINUTES` | Minutes without activity before sleeping, e.g. `10`. Unset = never sleep |
| `DOORBELL_URL` | The public `https://…` address of this service. On Railway it is taken from the service's public domain |
| `PORT` | Port the doorbell listens on (default 8080); the public address must route to it |

On Railway: generate a public domain for the service with target port 8080, and turn **Serverless** on in the service settings.

## Measured on Railway (2026-11-11)

| State when the message arrived | Time |
|---|---|
| Claude stopped, container running | Doorbell reached 0.9 s after sending; Claude starting 0.5 s later |
| Container suspended by the host for 4 hours | The owner measured 2 to 3 s to the answer |

- Memory: 0.40 GB average for an agent that is always on; 0.12 GB with Claude stopped; **0 while suspended** (three hours of metrics at zero).
- Several messages sent in a row to a suspended agent arrived once each, in order.

## What changes when an agent sleeps

- **Scheduled jobs.** A suspended container runs nothing. If the agent has jobs, the doorbell sends one packet every four minutes so the host keeps the container (Claude still sleeps: about a third of the memory). An agent without jobs is suspended completely.
- **Nightly backup.** It would not run in a suspended container, so a backup is made when going to sleep if the last one is older than 20 hours.
- **The first answer** after a sleep takes a few seconds longer.
- **The peer view** of a suspended agent: untested. Private-network traffic should wake the container, and the first attempt may fail.
- The public address only wakes the container; without the secret the doorbell answers 403 and Claude is not started. After a wake with no message waiting, the agent goes straight back to waiting.

## Not verified yet

- The host's invoice itself (the metrics show zero while suspended).
- Groups, and updates other than plain messages, as the ring.
- The keep-awake for agents with jobs, and the backup before sleeping, on a real host.
- Hosts other than Railway.
