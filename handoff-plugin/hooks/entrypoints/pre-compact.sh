#!/usr/bin/env bash
# pre-compact.sh - PreCompact hook for claude-handoff plugin
#
# PURPOSE:
#   Generates goal-focused handoff content when user runs `/compact handoff:<instructions>`
#   by forking current session and extracting relevant context immediately.
#
# HOOK EVENT: PreCompact
#   - Fires BEFORE compact operations (manual /compact)
#   - Only activates when custom_instructions match "handoff:..." format
#   - Receives: session_id, transcript_path, trigger, custom_instructions
#
# ARCHITECTURE:
#   Uses `claude --resume $session_id --fork-session` to create a snapshot
#   of current session, then generates handoff context from the fork before
#   the original session gets compacted.
#
# TESTING:
#   1. Enable debug logging in hooks/lib/logging.sh (set LOGGING_ENABLED=true)
#   2. Start a conversation, add substantial context (multiple tool uses)
#   3. Run: /compact handoff:now implement feature X
#   4. Check logs:
#        tail -f /tmp/handoff-precompact.log
#   5. Verify state file created with handoff_content:
#        cat .git/handoff-pending/handoff-context.json
#   6. Expected state file structure:
#        {
#          "handoff_content": "<generated handoff markdown>",
#          "goal": "now implement feature X",
#          "trigger": "manual",
#          "type": "compact"
#        }
#
# NEGATIVE TEST (should not trigger):
#   /compact  # No state file created
#   /compact some other instructions  # No state file created
#
# EXIT BEHAVIOR:
#   - Always exits 0 (never blocks compact)
#   - Returns JSON: {"continue": true, "suppressOutput": true}
#
set -euo pipefail

# Load logging module
source "${BASH_SOURCE%/*}/../lib/logging.sh"
init_logging "precompact"

# Fail-open: always succeed, never block compact
trap 'jq -n "{continue:true,suppressOutput:true}" && exit 0' ERR

# Parse hook input from stdin
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
trigger=$(echo "$input" | jq -r '.trigger // "auto"')
cwd=$(echo "$input" | jq -r '.cwd // "."')
manual_instructions=$(echo "$input" | jq -r '.custom_instructions // ""')

log "Received input: session_id=$session_id trigger=$trigger cwd=$cwd manual_instructions=$manual_instructions"

# Only proceed if manual instructions match "handoff:..." format
if [[ ! "$manual_instructions" =~ ^handoff: ]]; then
  log "Manual instructions don't match 'handoff:' pattern, skipping handoff"
  jq -n '{continue: true, suppressOutput: true}'
  exit 0
fi

# Extract user instructions after "handoff:" prefix
user_instructions="${manual_instructions#handoff:}"
# Trim leading whitespace
user_instructions="${user_instructions#"${user_instructions%%[![:space:]]*}"}"

log "Handoff triggered with user instructions: $user_instructions"

# Change to project directory
cd "$cwd" || exit 0

# Create state directory
mkdir -p .git/handoff-pending

log "Forking session $session_id to generate handoff context..."

# Build handoff extraction prompt
handoff_prompt="Context window compaction imminent. You are analyzing the current to generate a focused Handoff for the next session.

Create a focused Handoff message for the next agent to immediately pick up where we left off. This Handoff will be used by the next agent to continue the most recent work related to the user's goal:

<user_instructions>
  custom_instructions: $user_instructions
</user_instructions>

Information to potentially include:

1. **Context from previous session** - What we were working on that's relevant to the new goal
2. **Key decisions/patterns** - Approaches, conventions, or constraints already established
3. **Relevant files** - Paths to files that matter for the new goal (paths only)
4. **Current state** - Where things were left that affects the new work
5. **Blockers/dependencies** - Any issues or prerequisites the new session should know about

Return a concise markdown summary (max 500 words) structured as:

<format>
  ## Immediate Handoff
  [Restate the immediate next steps]

  ## Relevant Context
  [Bullet points of relevant technical context]

  ## Key Details
  [Specific implementation details, file paths, function names, shell commands]

  ## Important Notes
  [Warnings, blockers, or critical information]
</format>"

# Fork the current session and generate goal-focused handoff content
# --fork-session creates a snapshot without affecting original session
# --model haiku for speed and cost
# --print for headless execution
handoff_exit_code=0
handoff_content=$(claude --resume "$session_id" --fork-session --model haiku --print "$handoff_prompt") || handoff_exit_code=$?

# Check if handoff generation succeeded
if [[ $handoff_exit_code -ne 0 ]] || [[ -z "$handoff_content" ]]; then
  log "ERROR: Failed to generate handoff content (exit code: $handoff_exit_code)"
  jq -n '{continue: true, suppressOutput: true}'
  exit 0
fi

log "Successfully generated handoff content (${#handoff_content} chars)"

# Save generated handoff content for SessionStart to inject
jq -n \
  --arg content "$handoff_content" \
  --arg goal "$user_instructions" \
  --arg trigger "$trigger" \
  '{
    handoff_content: $content,
    goal: $goal,
    trigger: $trigger,
    type: "compact"
  }' \
  >.git/handoff-pending/handoff-context.json

log "Handoff content saved to .git/handoff-pending/handoff-context.json"

# Success - allow compact to proceed, suppress output so user doesn't see handoff generation
jq -n '{continue: true, suppressOutput: true}'
exit 0
