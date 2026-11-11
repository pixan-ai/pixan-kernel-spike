# shellcheck shell=bash
# Shared by every test file: one check per behaviour, a count of failures.
FAILS=0
check() {  # check "description" command...
  local d=$1; shift
  if "$@"; then echo "ok   - $d"; else echo "FAIL - $d"; FAILS=$((FAILS + 1)); fi
}
