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

## Results on Railway (2026-11-11, one agent, `IDLE_SLEEP_MINUTES=3`, Serverless on)

| State when the message arrived | What woke it | Measured |
|---|---|---|
| Claude stopped, container still running | The doorbell | Doorbell reached 0.9 s after the message was sent; Claude starting 0.5 s later |
| Container suspended by the host (26 min idle) | The host restarted the container; `start.sh` removed the webhook | Claude starting 1.3 s after the container start; the owner measured 2 to 3 s to the answer |

- No message was lost in either case, and the conversation continued.
- Memory with Claude stopped and the container running: 0.12 GB (0.33 GB average awake).
- The doorbell rang twice 0.1 s apart for one message (Telegram retried after the 503). The message was delivered once, because delivery is by polling, not by the webhook body.
- Not known yet: what the host bills while the container is suspended.

## To resolve before this can be a product feature

1. **Exactly one delivery per message, also when things are slow.** The owner's requirement: one message from the customer must never become two requests to Claude, including when the doorbell-to-Claude handoff is slow or intermittent (Telegram retries, the doorbell ringing more than once, a wake that overlaps another wake). Needs a test that forces slowness and retries.
2. **Two messages in a row.** What happens when the customer sends a message and immediately a second one: both must arrive, once each, in order, whether the second lands while the container is starting, while the webhook is being removed, or just as the agent is going back to sleep.
3. Scheduled jobs do not run while the container is suspended.
4. Only `message` updates ring the doorbell (no photos-only updates, edits, callbacks); groups not tested.
5. Anyone who knows the URL can ring the doorbell (it only wakes the agent). Use Telegram's webhook secret token.
6. A suspended agent and the peer view: does private-network traffic wake it?
7. The race at the edge of sleep: a message that arrives between "Claude stopped" and "webhook set".
8. No automated tests on this branch.

