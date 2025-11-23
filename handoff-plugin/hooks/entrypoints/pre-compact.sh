#!/usr/bin/env bash
# pre-compact.sh - PreCompact hook for claude-handoff plugin
#
# PURPOSE:
#   Saves session state before /compact (manual or auto) so that SessionStart
#   can generate and inject an intelligent handoff using claude --resume.
#
# HOOK EVENT: PreCompact
#   - Fires BEFORE compact operations (manual /compact or auto at 95%)
#   - Receives: session_id, transcript_path, trigger ("manual"|"auto"), custom_instructions
#
# TESTING:
#   1. Enable debug logging by uncommenting the LOG_FILE line below
#   2. Start a conversation, add substantial context (multiple tool uses)
#   3. Run /compact manually OR fill context to 95% for auto-compact
#   4. Check logs:
#        tail -f /tmp/handoff-precompact.log
#   5. Verify state file created:
#        cat .git/handoff-pending/handoff-context.json
#   6. Expected state file structure:
#        {
#          "previous_session": "abc123...",
#          "trigger": "manual" or "auto",
#          "cwd": "/path/to/project",
#          "type": "compact"
#        }
#
# MANUAL TESTING WITH FAKE INPUT:
#   echo '{"session_id":"test-123","trigger":"manual","cwd":"'$(pwd)'"}' | bash pre-compact.sh
#   cat .git/handoff-pending/handoff-context.json
#   rm -rf .git/handoff-pending  # cleanup
#
# EXIT BEHAVIOR:
#   - Always exits 0 (never blocks compact)
#   - Returns JSON: {"continue": true, "suppressOutput": true}
#
set -euo pipefail

# Debug logging (uncomment to enable)
LOG_FILE="/tmp/handoff-precompact.log"
exec 2>>"$LOG_FILE"
set -x
echo "[$(date -Iseconds)] PreCompact hook triggered" >>"$LOG_FILE"

# Fail-open: always succeed, never block compact
trap 'jq -n "{continue:true,suppressOutput:true}" && exit 0' ERR

# Parse hook input from stdin
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
trigger=$(echo "$input" | jq -r '.trigger // "auto"')
cwd=$(echo "$input" | jq -r '.cwd // "."')

# Debug: Log received input (uncomment to enable)
echo "[$(date -Iseconds)] Received input: session_id=$session_id trigger=$trigger cwd=$cwd" >>"$LOG_FILE"

# Change to project directory
cd "$cwd" || exit 0

# Create state directory and save session metadata for SessionStart
mkdir -p .git/handoff-pending

# Write state file that SessionStart will read
jq -n \
  --arg session "$session_id" \
  --arg trigger "$trigger" \
  --arg cwd "$cwd" \
  '{
    previous_session: $session,
    trigger: $trigger,
    cwd: $cwd,
    type: "compact"
  }' \
  >.git/handoff-pending/handoff-context.json

# Debug: Confirm state saved (uncomment to enable)
echo "[$(date -Iseconds)] State saved to .git/handoff-pending/handoff-context.json" >>"$LOG_FILE"

# Success - allow compact to proceed
jq -n '{continue: true, suppressOutput: true}'
exit 0
