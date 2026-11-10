# Lab image and product image

Status: **Option A chosen by the owner (2026-11-10)**: the product image has no Claude Code; the entrypoint installs the pinned official release on first start into the volume. Not built yet.

## Two images, two purposes

| | Lab image (today) | Product image (proposed) |
|---|---|---|
| Contains Claude Code | **Yes**, installed at build time | **No** |
| Who builds it | The owner, on their own host (Railway) | CI, published to a registry |
| May be published publicly | **No**: Claude Code is "All rights reserved", used under Anthropic's Commercial Terms | Yes |
| Purpose | Run the owner's own agent | What a customer downloads |

The `Dockerfile` in this repository is the lab image. Its `release.yml` publish job is locked (`PUBLISH_IMAGE`) so nothing containing Claude Code reaches a public registry by accident.

## Why the product image has no Claude Code

Anthropic's documentation says a product that preinstalls Claude Code needs Commercial Terms, an unmodified binary, and each end user's own credentials. This project is open source and sells consulting, not software, so it should not redistribute the binary at all.

## How the product image gets Claude Code

Option A (recommended): the entrypoint installs the **pinned** official release on first start into the volume (`/data`), using the customer's own network and credentials. The image stays free of the binary; the binary is unmodified and comes from Anthropic. Cost: first start needs outbound access to the official installer, and the entrypoint gains a few lines plus a checksum or version check.

Option B: the customer builds the image themselves from the same `Dockerfile` (`docker build`). No distribution, no extra code. Cost: no pull-and-run convenience, so no registry "seals" for that image.

Option C: publish a base image (OS, `bun`, `jq`, `setpriv`, policy, scripts) and let the customer's own `FROM` add Claude Code. Closest to A without runtime install, but needs the customer to build once.

## Decisions needed from the owner

1. A, B or C (or a mix: B for customers, A for convenience).
2. Whether the product image carries the managed policy (recommended: yes, it contains no secrets).
3. Whether to ask Anthropic in writing before publishing anything.

## Not decided here

This document does not change the lab deployment or any workflow.
