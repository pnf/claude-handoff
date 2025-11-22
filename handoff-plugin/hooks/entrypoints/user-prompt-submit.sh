#!/usr/bin/env bash
set -euo pipefail

# Proof of concept: Detect /handoff and inject context

# Read hook input from stdin
input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // ""')
session_id=$(echo "$input" | jq -r '.session_id')
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')

# Detect /handoff command
if [[ "$prompt" == *"/claude-handoff:handoff"* ]]; then
  # Extract goal after "handoff " - remove the slash command prefix
  goal="${prompt#*:handoff }"
  goal=$(echo "$goal" | xargs) # trim whitespace

  # Generate proof-of-concept response
  draft="## Handoff Proof of Concept

**Goal:** $goal

**Session ID:** $session_id
**Transcript:** $transcript_path

This is a test of the hook system. If you see this message, the hook is working correctly.

**Next Steps:**
1. Run \`/clear\` to start fresh
2. Use the following prompt:

---
$goal

Context: Previous thread completed initial research. Continue from here.
---

(This will be replaced with actual transcript analysis once POC is validated)"

  # Return JSON with additionalContext
  jq -n --arg draft "$draft" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $draft
    }
  }'
fi

# Always exit 0 (fail-open)
exit 0
