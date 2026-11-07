#!/usr/bin/env bash
# Diagnostics: which policy is loaded and why each tool call was rejected. Usage: denials.sh [lines]
echo "== block-audit hooks in the loaded policy (expected: 2 or more) =="
grep -c -E "PermissionDenied|PostToolUseFailure" /etc/claude-code/managed-settings.json
echo "== prompt-suggestion variable (expected: false) =="
printenv CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION
echo "== tool errors in the latest session (includes denied permissions) =="
f=$(ls -t /data/config/projects/-data-workspace/*.jsonl 2>/dev/null | head -1)
[ -n "$f" ] || { echo "no session transcript"; exit 0; }
jq -r 'select(.type=="user") | .message.content? | arrays | .[] | select(.type=="tool_result" and .is_error==true) | (.content|tostring)' "$f" | tail -"${1:-8}" | cut -c1-400
