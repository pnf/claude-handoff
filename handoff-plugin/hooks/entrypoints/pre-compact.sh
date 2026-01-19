#!/usr/bin/env bash
# pre-compact.sh - PreCompact hook for claude-handoff plugin
#
# PURPOSE:
#   Generates goal-focused handoff content when user runs `/compact handoff:<instructions>`
#   or `/compact handoff!<instructions>` by forking current session and extracting relevant
#   context immediately. Using "handoff!" also saves the content to HANDOFF.md.
#
# HOOK EVENT: PreCompact
#   - Fires BEFORE compact operations (manual /compact)
#   - Only activates when custom_instructions match "handoff:..." or "handoff!..." format
#   - "handoff!" also saves the handoff to HANDOFF.md in the current directory
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
#      Or: /compact handoff!now implement feature X  (also saves to HANDOFF.md)
#   4. Check logs:
#        tail -f /tmp/handoff-precompact.log
#   5. Verify state file created with handoff_content:
#        cat .git/handoff-pending/handoff-context.json
#   6. If using "handoff!", also verify: cat HANDOFF.md
#   7. Expected state file structure:
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

# Only proceed if manual instructions match "handoff:" or "handoff!" format
if [[ ! "$manual_instructions" =~ ^handoff[:!] ]]; then
  log "Manual instructions don't match 'handoff:' or 'handoff!' pattern, skipping handoff"
  jq -n '{continue: true, suppressOutput: true}'
  exit 0
fi

# Determine separator and extract user instructions
if [[ "$manual_instructions" =~ ^handoff! ]]; then
  separator="!"
  user_instructions="${manual_instructions#handoff!}"
else
  separator=":"
  user_instructions="${manual_instructions#handoff:}"
fi
# Trim leading whitespace
user_instructions="${user_instructions#"${user_instructions%%[![:space:]]*}"}"

log "Handoff triggered with user instructions: $user_instructions"

# Change to project directory
cd "$cwd" || exit 0

# Create state directory
mkdir -p .git/handoff-pending

log "Forking session $session_id to generate handoff context..."

# Build handoff extraction prompt
handoff_prompt="You are generating a goal-focused Handoff for the next session. Context compaction is imminent.

<goal>
$user_instructions
</goal>

Your task: Extract ONLY the context from this session that the next agent needs to execute the goal above. Be ruthlessly selective—irrelevant context is worse than missing context.

Before providing your handoff, analyze the conversation in <analysis> tags:

1. Restate the goal in your own words
2. Chronologically scan the session for information relevant to THIS GOAL:
   - Decisions, patterns, or constraints that affect the goal
   - Files modified or examined that relate to the goal
   - Errors encountered and how they were resolved
   - Current state of work that impacts the goal
3. Explicitly list what you are EXCLUDING and why
4. Verify: Does every item you're including directly serve the goal?

<analysis>
[Your systematic analysis here]
</analysis>

Then provide your handoff in this exact structure:

<handoff>
## Goal
[Restate the goal as a clear, actionable directive]

## Relevant Context
[3-7 bullet points of technical context that directly enables the goal]
[Each bullet must pass the test: \"The next agent cannot execute the goal without knowing this\"]

## Key Details
[Specific implementation details: file paths, function names, commands, error messages]
[Use exact names and paths—no paraphrasing]

## Warnings
[Blockers, gotchas, or critical constraints]
[Omit this section entirely if nothing applies]
</handoff>

Constraints:
- Maximum 400 words in the <handoff> section
- File paths only, not full code snippets (the agent can read files)
- Include verbatim quotes for anything where paraphrasing risks drift
- If the goal is unclear or disconnected from session context, say so explicitly in your analysis and provide best-effort handoff

Do not:
- Include context \"just in case\" it might be useful
- Summarize the full session—that's not your job
- Invent next steps beyond what the goal specifies
- Include resolved issues unless they inform the goal"

# Fork the current session and generate goal-focused handoff content
# --fork-session creates a snapshot without affecting original session
# --model haiku for speed and cost
# --print for headless execution
#
# IMPORTANT: Write output directly to temp file to avoid bash variable expansion
# corrupting content (backticks, $(), globs, null bytes all break variable capture)
handoff_exit_code=0
temp_content=$(mktemp)
trap "rm -f '$temp_content'" EXIT

claude --resume "$session_id" --fork-session --model haiku --print "$handoff_prompt" >"$temp_content" || handoff_exit_code=$?

# Check if handoff generation succeeded
if [[ $handoff_exit_code -ne 0 ]] || [[ ! -s "$temp_content" ]]; then
  log "ERROR: Failed to generate handoff content (exit code: $handoff_exit_code)"
  jq -n '{continue: true, suppressOutput: true}'
  exit 0
fi

content_size=$(wc -c <"$temp_content" | tr -d ' ')
log "Successfully generated handoff content ($content_size bytes)"

# If using handoff! syntax, copy content to HANDOFF.md in current directory
if [[ "$separator" == "!" ]]; then
  cp "$temp_content" "$cwd/HANDOFF.md"
  log "Copied handoff content to HANDOFF.md"
fi

# Save generated handoff content for SessionStart to inject
# Use --rawfile so jq reads file directly (bypasses bash variable expansion)
jq -n \
  --rawfile content "$temp_content" \
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
