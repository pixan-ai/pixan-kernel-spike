#!/usr/bin/env bash
# Shows the latest readable screen of Claude Code. Usage: screen.sh [lines]
# Every cursor move becomes a newline; the remaining terminal escape codes are then stripped.
sed -E 's/\x1b\[[0-9;]*[HABCDEFGJKf]/\n/g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b[()][A-Z0-9]//g' /data/tui.log | tr -d '\r' | grep -v '^[[:space:]]*$' | tail -"${1:-30}" | cut -c1-160
