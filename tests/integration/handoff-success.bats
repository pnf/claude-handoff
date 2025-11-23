# handoff-success.bats - Integration tests for successful handoff generation
#
# Purpose: Test the complete success path including systemMessage output
# Tests: Mock claude binary, verify JSON output format, verify cleanup

# bats file_tags=integration,success-path

# Load Bats libraries
load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/bats-file/load'

# Load custom helpers
load '../test_helper/git-test-helpers'
load '../test_helper/json-assertions'

# Hook path
SESSIONSTART_HOOK="$BATS_TEST_DIRNAME/../../handoff-plugin/hooks/entrypoints/session-start.sh"

# Disable logging for tests
export LOGGING_ENABLED=false

# Setup: Create git test repo and mock claude binary
setup() {
  setup_test_repo

  # Create mock claude binary that returns fake handoff content
  MOCK_CLAUDE_DIR="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_CLAUDE_DIR"

  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
# Mock claude binary for testing

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --resume)
      SESSION_ID="$2"
      shift 2
      ;;
    --model)
      shift 2
      ;;
    --print)
      shift
      ;;
    *)
      # This is the prompt
      PROMPT="$1"
      shift
      ;;
  esac
done

# Return fake handoff content
cat <<'HANDOFF'
## Handoff Context

This is a focused handoff generated from the previous session.

**Context**: Working on authentication feature
**Files**: src/auth.ts, tests/auth.test.ts
**Current state**: Basic login implemented, need OAuth integration
**Blockers**: None
HANDOFF

exit 0
EOF

  chmod +x "$MOCK_CLAUDE_DIR/claude"

  # Add mock claude to PATH
  export PATH="$MOCK_CLAUDE_DIR:$PATH"
}

# Teardown: Clean up git repo and mock binary
teardown() {
  cleanup_test_repo
  rm -rf "$MOCK_CLAUDE_DIR"
}

# Test 1: Success path returns valid JSON with systemMessage
# bats test_tags=critical,success-path,systemMessage
@test "should return valid JSON with systemMessage on success" {
  # Create valid state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "550e8400-e29b-41d4-a716-446655440000" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "implement OAuth integration",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-success",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Output should be valid JSON
  assert_valid_json "$output"

  # Output should contain systemMessage field
  local has_system_message
  has_system_message=$(echo "$output" | jq 'has("systemMessage")')
  assert_equal "$has_system_message" "true"

  # systemMessage should not be empty
  local message_content
  message_content=$(echo "$output" | jq -r '.systemMessage')
  refute [ -z "$message_content" ]

  # systemMessage should contain expected handoff content
  assert_output --partial "## Handoff Context"
  assert_output --partial "authentication feature"
}

# Test 2: Success path cleans up state file and directory
# bats test_tags=critical,cleanup
@test "should clean up state file and directory on success" {
  # Create valid state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "550e8400-e29b-41d4-a716-446655440000" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "fix bug",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify state file exists
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-cleanup",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"
  assert_success

  # State file should be deleted
  assert_file_not_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Directory should be deleted (or might remain if other files exist, hence 2>/dev/null || true)
  # For this test, directory should be gone since we only had one file
  assert_dir_not_exist "$TEST_REPO/.git/handoff-pending"
}

# Test 3: Verify systemMessage JSON structure matches schema
# bats test_tags=critical,schema-validation
@test "should return systemMessage with exact JSON schema" {
  # Create valid state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "550e8400-e29b-41d4-a716-446655440000" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "test goal",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-schema",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"
  assert_success

  # Parse JSON and verify structure
  local output_json="$output"

  # Should have exactly one key: systemMessage
  local key_count
  key_count=$(echo "$output_json" | jq 'keys | length')
  assert_equal "$key_count" "1"

  # That key should be "systemMessage"
  local key_name
  key_name=$(echo "$output_json" | jq -r 'keys[0]')
  assert_equal "$key_name" "systemMessage"

  # systemMessage value should be a string
  local message_type
  message_type=$(echo "$output_json" | jq -r '.systemMessage | type')
  assert_equal "$message_type" "string"
}
