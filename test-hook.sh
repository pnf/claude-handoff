#!/usr/bin/env bash
# Manual test for the user-prompt-submit hook

cat <<'EOF' | handoff-plugin/hooks/entrypoints/user-prompt-submit.sh
{
  "session_id": "test-session-123",
  "prompt": "/claude-handoff:handoff implement this for teams",
  "transcript_path": "/tmp/test-transcript.jsonl",
  "hook_event_name": "UserPromptSubmit"
}
EOF
