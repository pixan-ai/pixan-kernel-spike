#!/usr/bin/env bash
# What fellow agents can do with this agent, over SSH with a forced command (docs/PEERS.md): look, and set its groups.
#   peer.sh serve             start the SSH server (start.sh does this when PEER_PUBLIC_KEYS is set)
#   peer.sh look HOST [WHAT]  look at a fellow agent; WHAT is screen (default), status, denials, transcript,
#                             or "group ID" / "drop ID" to change that agent's groups
#   peer.sh                   what the SSH server runs for every connection: answer one request, nothing else
set -euo pipefail
D=/data/ssh; B=$(dirname "$(readlink -f "$0")")
case "${1:-}" in
  serve)
    [ -f $D/host_key ] || ssh-keygen -q -t ed25519 -N '' -f $D/host_key
    printf '%s\n' "$PEER_PUBLIC_KEYS" > $D/authorized_keys
    exec "$(command -v sshd)" -f /dev/null -o Port=2222 -o HostKey=$D/host_key -o AuthorizedKeysFile=$D/authorized_keys -o PidFile=none \
      -o ForceCommand="$B/peer.sh" -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no \
      -o PermitTTY=no -o AllowTcpForwarding=no -o AllowAgentForwarding=no -o X11Forwarding=no -o PermitUserRC=no ;;
  look)  # $2 is a host, or a name from PEERS or from config.sh peer (case-insensitive)
    h=$2; for p in ${PEERS:-} $(sed -n 's/^peer //p' /data/settings 2> /dev/null); do n=${p%%=*}; [ "${n,,}" != "${2,,}" ] || h=${p#*=}; done
    exec ssh -i $D/peer_key -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$D/known_hosts "agent@$h" "${3:-screen}" ;;
esac
case "${SSH_ORIGINAL_COMMAND:-}" in
  screen) exec "$B/screen.sh" 40 ;;
  denials) exec "$B/denials.sh" ;;
  transcript)  # the last 40 messages of the latest conversation: what the owner wrote and what the agent answered
    f=$(find /data/config/projects -maxdepth 2 -name '*.jsonl' -printf '%T@ %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    jq -r 'select(.type == "user" or .type == "assistant") | .type as $t
      | (.message.content | if type == "string" then . else map(if .type == "text" then .text elif .type == "tool_use" then (.input.text // empty) else empty end) | join("\n") end)
      | select(length > 0) | "[\($t)] \(.[0:600])"' "$f" | tail -n 40 ;;
  status) pgrep -x script > /dev/null && echo "claude: running" || echo "claude: NOT running"
          echo "last heartbeat: $(date -r /data/cron/alive '+%F %T %Z' 2> /dev/null || echo never)" ;;
  *)  # the one thing a fellow agent may change here: its groups, through config.sh (which tells this agent's owner)
    [[ ${SSH_ORIGINAL_COMMAND:-} =~ ^(group|drop)\ -?[0-9]+$ ]] || { echo "allowed: screen | status | denials | transcript | group ID | drop ID" >&2; exit 2; }
    read -r a b <<< "$SSH_ORIGINAL_COMMAND"; exec "$B/config.sh" "$a" "$b" ;;
esac
