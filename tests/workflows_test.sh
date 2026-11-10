#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"; regexes are single-quoted on purpose
# Supply-chain hygiene of the CI itself: what OpenSSF Scorecard and a reviewer look for in .github/workflows.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
FAILS=0

check() {  # check "description" command...
  local d=$1; shift
  if "$@"; then echo "ok   - $d"; else echo "FAIL - $d"; FAILS=$((FAILS + 1)); fi
}
absent() { ! grep -qE "$1" .github/workflows/*.yml; }

# Every `uses:` is a local action or a full 40-character commit SHA (a tag can be moved; a SHA cannot).
unpinned=$(grep -hnE '^[[:space:]]*(-[[:space:]]*)?uses:' .github/workflows/*.yml \
  | grep -vE 'uses:[[:space:]]*(\./|[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}([[:space:]]|$))' || true)
check "every action is pinned to a full commit SHA" test -z "$unpinned"
while IFS= read -r line; do [ -z "$line" ] || echo "     $line"; done <<<"$unpinned"

for f in .github/workflows/*.yml; do
  check "$f declares top-level permissions" grep -qE '^permissions:' "$f"
done
check "no workflow is triggered by pull_request_target" absent 'pull_request_target'
check "no workflow reads untrusted event data" absent 'github\.(head_ref|event\.(issue|pull_request|comment|review|pages)\b)'
count() { grep -h -- "$1" .github/workflows/*.yml | grep -c ''; }
check "every checkout drops its credentials" test "$(count 'uses: actions/checkout@')" = "$(count 'persist-credentials: false')"

# Only the `base` target (no Anthropic software) may leave the build machine.
pushes=$(grep -c 'push: true' .github/workflows/release.yml); based=$(grep -B1 'push: true' .github/workflows/release.yml | grep -c 'target: base')
check "every image push in the release workflow builds the base target" test "$pushes" -gt 0 -a "$pushes" = "$based"
check "the Dockerfile's default (last) target is the agent, built from base" test "$(grep -E '^FROM ' Dockerfile | tail -1 | grep -c 'FROM base AS agent$')" = 1
check "Claude Code is installed only after the base target" test -z "$(sed '/^FROM base AS agent$/,$d' Dockerfile | grep -iE 'claude\.ai/install|claude plugin')"

echo "$FAILS failed"; exit $((FAILS > 0))
