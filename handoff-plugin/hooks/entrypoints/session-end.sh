#!/usr/bin/env bash
set -euo pipefail

# Fail-open: always succeed, never block /clear
trap 'jq -n "{continue:true,suppressOutput:false,stopReason:\"\"}" && exit 0' ERR

# Parse input
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd // "."')

# Prompt Claude to analyze and generate handoff (use Haiku for speed)
handoff=$(claude --resume "$session_id" --print --model haiku \
  "Analyze this conversation and create a focused handoff prompt for the next session.

Include:
1. **What we were working on** - Current task/goal
2. **Key decisions made** - Important choices or approaches agreed upon
3. **Relevant files** - Paths to files read/modified (paths only, no content)
4. **Next steps** - What should happen next
5. **Blockers** - Any errors, issues, or open questions

Format as concise markdown. Be specific and actionable. Omit meta-discussion about creating this handoff.")

# Create state directory
mkdir -p .git/handoff-pending

# Store for SessionStart
jq -n \
  --arg draft "$handoff" \
  --arg session "$session_id" \
  --arg cwd "$cwd" \
  '{draft: $draft, previous_session: $session, cwd: $cwd}' \
  >.git/handoff-pending/handoff-context.json

# Success
jq -n '{continue: true, suppressOutput: false, stopReason: ""}'
exit 0
