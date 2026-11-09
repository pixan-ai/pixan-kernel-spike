#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2016  # helpers are called through check "$@"; regexes and jq programs are single-quoted on purpose
# Documentation-vs-code drift tests: what the docs say must be what the scripts do. Run from a checkout (no image needed).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
FAILS=0

check() {  # check "description" command...
  local d=$1; shift
  if "$@"; then echo "ok   - $d"; else echo "FAIL - $d"; FAILS=$((FAILS + 1)); fi
}
listed() { grep -qxF -- "$1" <<<"$2"; }
exists() { [ -e "$1" ]; }

# Configuration the entrypoint takes from the environment = variables it reads but never assigns itself.
refs=$(grep -oE '\$\{?[A-Z][A-Z0-9_]*' bin/start.sh | tr -d '${' | sort -u)
assigned=$(grep -oE '(^|;[[:space:]]*|\()[A-Z][A-Z0-9_]*=' bin/start.sh | sed -E 's/^[;(]//; s/^[[:space:]]+//; s/=$//' | sort -u)
inputs=$(comm -23 <(printf '%s\n' "$refs") <(printf '%s\n' "$assigned"))
# Consumed by Claude Code or the OS, not by start.sh, but documented for the user.
known=$(printf '%s\n' "$inputs" ANTHROPIC_MODEL TZ)
documented=$(sed -n '/^| Variable/,/^$/p' README.md | grep -oE '^\| `[A-Z][A-Z0-9_]*`' | tr -d '|` ')
example=$(grep -oE '^#? ?[A-Z][A-Z0-9_]*=' .env.example | tr -d '# =')

check "start.sh reads at least the Telegram and Claude credentials" listed TELEGRAM_BOT_TOKEN "$inputs"
for v in $inputs; do check "README documents $v, which start.sh reads" listed "$v" "$documented"; done
for v in $documented; do check "$v, documented in README, is something the code uses" listed "$v" "$known"; done
for v in $example; do check ".env.example's $v is documented in README" listed "$v" "$documented"; done

# The repository layout in the README: every path exists, and every top-level directory is listed.
layout=$(sed -n '/^## Repository layout/,/^## /p' README.md | sed -n '/^```$/,/^```$/p' | grep -v '^```$' | awk '{ print $1 }')
for p in $layout; do check "README layout: $p exists" exists "$p"; done
for d in $(git ls-files | cut -d/ -f1 | sort -u); do
  [ -d "$d" ] && check "README layout lists the directory $d/" grep -q "^$d/" <<<"$layout"
done

# Relative links in the documents resolve.
broken=""
for f in README.md CONTRIBUTING.md SECURITY.md docs/*.md; do
  while IFS= read -r l; do
    t=${l#](}; t=${t%)}; t=${t%%#*}
    case $t in http*|mailto:*|"") continue ;; esac
    [ -e "$(dirname "$f")/$t" ] || broken="$broken $f->$t"
  done < <(grep -oE '\]\([^)]+\)' "$f")
done
check "relative links in the documents resolve" test -z "$broken"
[ -z "$broken" ] || echo "     broken:$broken"

check "every Dockerfile FROM is pinned by digest (Dependabot keeps it current)" test -z "$(grep -E '^FROM ' Dockerfile | grep -vE '@sha256:[0-9a-f]{64}')"

echo "$FAILS failed"; exit $((FAILS > 0))
