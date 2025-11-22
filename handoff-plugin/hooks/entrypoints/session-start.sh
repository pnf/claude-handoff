#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook: Inject handoff context after /clear

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
source=$(echo "$input" | jq -r '.source // ""')

# Only process if triggered by /clear
if [[ "$source" != "clear" ]]; then
  exit 0
fi

# Check for pending handoff state
state_dir=".git/handoff-pending"
state_file="$state_dir/handoff-context.json"

if [[ ! -f "$state_file" ]]; then
  # No handoff pending, exit silently
  exit 0
fi

# Read handoff context
handoff_context=$(cat "$state_file" 2>/dev/null || echo "")

if [[ -z "$handoff_context" ]]; then
  exit 0
fi

# Extract the handoff draft
draft=$(echo "$handoff_context" | jq -r '.draft // ""')

if [[ -z "$draft" ]]; then
  exit 0
fi

# Clean up state file
rm -f "$state_file"
rmdir "$state_dir" 2>/dev/null || true

# Return JSON with additionalContext
jq -n --arg draft "$draft" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $draft
  }
}'

exit 0
