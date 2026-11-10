#!/usr/bin/env bash
# Read-only view of this agent for fellow agents, over SSH with a forced command (docs/PEERS.md).
#   peer.sh serve             start the SSH server (start.sh does this when PEER_PUBLIC_KEYS is set)
#   peer.sh look HOST [WHAT]  look at a fellow agent; WHAT is screen (default), status or denials
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
  look)
    exec ssh -i $D/peer_key -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$D/known_hosts "agent@$2" "${3:-screen}" ;;
esac
case "${SSH_ORIGINAL_COMMAND:-}" in
  screen) exec "$B/screen.sh" 40 ;;
  denials) exec "$B/denials.sh" ;;
  status) pgrep -x script > /dev/null && echo "claude: running" || echo "claude: NOT running"
          echo "last heartbeat: $(date -r /data/cron/alive '+%F %T %Z' 2> /dev/null || echo never)" ;;
  *) echo "allowed: screen | status | denials" >&2; exit 2 ;;
esac
