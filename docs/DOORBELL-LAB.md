# Lab: sleep when idle, wake on a Telegram webhook ("doorbell")

Status: **experiment on a branch, not in the product.** Question: can an idle agent cost close to nothing on a host that suspends idle containers, without changing the official Telegram plugin, and how long does the first answer take?

## Idea

An agent listens by long polling, so its container always looks busy. With `IDLE_SLEEP_MINUTES` set:

1. After that many minutes without activity in the session, `start.sh` stops Claude, sets a Telegram **webhook** pointing at this service, and waits on a tiny HTTP listener. Nothing sends a packet any more, so the host may suspend the container.
2. A message arrives: Telegram calls the webhook, the host wakes the container, the listener answers **503** and exits. Telegram keeps a message whose delivery failed.
3. `start.sh` removes the webhook and starts Claude with `--continue`; the official plugin polls and receives the pending message.

## What to measure

- The doorbell log line: seconds between the message being sent and the listener being reached (host wake time).
- Seconds until the answer appears in Telegram (Claude start, session resume, model).
- Memory billed while asleep.
- Whether any message is lost or duplicated.

## Known gaps

- Scheduled jobs do not run while the container is suspended.
- Only `message` updates ring the doorbell.
- Needs a public domain for the service (`RAILWAY_PUBLIC_DOMAIN`) and a `PORT`.
