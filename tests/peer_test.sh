#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"
# Acceptance tests for the peer view (bin/peer.sh): a real SSH server and a real client, both as the agent user.
# What a fellow agent can do is read the screen; everything else must be refused. CI runs this inside the built image.
set -uo pipefail
cd / || exit 1
BIN=${BIN:-/usr/local/bin}; K=$(mktemp -d); FAILS=0
check() {  # check "description" command...
  local d=$1; shift
  if "$@"; then echo "ok   - $d"; else echo "FAIL - $d"; FAILS=$((FAILS + 1)); fi
}
agent() { setpriv --reuid=1001 --regid=1001 --init-groups env HOME=/home/agent "$@"; }
look() { agent "$BIN/peer.sh" look localhost "$@" 2>&1; }
sees() { look "$1" | grep -q "$2"; }
no_shell() { ! agent ssh -i /data/ssh/peer_key -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -tt agent@localhost < /dev/null 2>&1 | grep -q '[$#] $'; }
blind() { ! sees screen SCREEN-MARKER; }
refused() { ! look "$@" | grep -q "root:"; }  # /etc/passwd never comes back

mkdir -p /data/ssh /run/sshd; find /data -mindepth 1 -delete; mkdir -p /data/ssh; chmod 755 /data; chmod 700 /data/ssh
ssh-keygen -q -t ed25519 -N '' -f "$K/friend"; ssh-keygen -q -t ed25519 -N '' -f "$K/stranger"
echo "the agent is working on: SCREEN-MARKER" > /data/tui.log
mkdir -p /data/config/projects/-data-workspace
cat > /data/config/projects/-data-workspace/s.jsonl <<'EOF'
{"type":"user","message":{"role":"user","content":"OWNER-SAID-THIS"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"reply","input":{"chat_id":"42","text":"AGENT-REPLIED-THIS"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"TOOL-OUTPUT"}]}}
{"type":"system","content":"TOOL-OUTPUT"}
EOF
chown -R 1001:1001 /data
agent env PEER_PUBLIC_KEYS="$(cat "$K/friend.pub")" "$BIN/peer.sh" serve
for _ in 1 2 3 4 5 6 7 8 9 10; do (exec 3<>/dev/tcp/127.0.0.1/2222) 2> /dev/null && break; sleep 0.5; done

install -o 1001 -g 1001 -m 600 "$K/friend" /data/ssh/peer_key
check "a fellow agent with a listed key sees the screen" sees screen SCREEN-MARKER
check "...and the status" sees status "claude: "
check "...but cannot run anything else" refused "cat /etc/passwd"
check "...not even by chaining after an allowed word" refused "screen; cat /etc/passwd"
check "...and gets no shell" no_shell
check "the server's files are private to the agent" test "$(stat -c %a /data/ssh/host_key)" = 600
by_name() { agent env PEERS="Other=nowhere.invalid Junior=localhost" "$BIN/peer.sh" look junior status 2>&1 | grep -q "claude: "; }
check "a peer can be addressed by its name in PEERS, whatever the case" by_name
check "transcript shows what the owner wrote" sees transcript "OWNER-SAID-THIS"
check "...and what the agent answered on Telegram" sees transcript "AGENT-REPLIED-THIS"
check "...but not tool results or anything else in the session file" bash -c '! grep -q TOOL-OUTPUT "$0"' <(look transcript)
install -o 1001 -g 1001 -m 600 "$K/stranger" /data/ssh/peer_key
check "a key that is not listed sees nothing" blind

pkill -u 1001 -x sshd 2> /dev/null; rm -rf "$K"
echo "$FAILS failed"; exit $((FAILS > 0))
