# handoff-errors.bats - Integration tests for handoff error scenarios
#
# Purpose: Test error handling including "No conversation found" and retry logic
# Tests: Mock failing claude binary, verify state file preservation for retry

# bats file_tags=integration,error-handling

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

# Setup: Create git test repo
setup() {
  setup_test_repo
  MOCK_CLAUDE_DIR="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_CLAUDE_DIR"
}

# Teardown: Clean up
teardown() {
  cleanup_test_repo
  rm -rf "$MOCK_CLAUDE_DIR"
}

# Test 1: "No conversation found" error preserves state file for retry
# bats test_tags=critical,error-handling,retry
@test "should preserve state file when claude returns 'No conversation found'" {
  # Create mock claude that returns "No conversation found" error
  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
echo "Error: No conversation found for session ID: 550e8400-e29b-41d4-a716-446655440000"
exit 1
EOF
  chmod +x "$MOCK_CLAUDE_DIR/claude"
  export PATH="$MOCK_CLAUDE_DIR:$PATH"

  # Create valid state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "550e8400-e29b-41d4-a716-446655440000" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "implement feature",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify state file exists before running hook
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-not-found",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully (silent failure)
  assert_success

  # Should have no output (silent exit for retry)
  assert_output ""

  # State file should STILL EXIST (preserved for retry)
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify state file content unchanged
  assert_json_field_equals "$TEST_REPO/.git/handoff-pending/handoff-context.json" \
    ".previous_session" "550e8400-e29b-41d4-a716-446655440000"
}

# Test 2: claude non-zero exit code preserves state file
# bats test_tags=critical,error-handling,retry
@test "should preserve state file when claude exits with non-zero code" {
  # Create mock claude that exits with error
  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
echo "Error: Connection failed"
exit 42
EOF
  chmod +x "$MOCK_CLAUDE_DIR/claude"
  export PATH="$MOCK_CLAUDE_DIR:$PATH"

  # Create valid state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "550e8400-e29b-41d4-a716-446655440000" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "test retry",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-exit-error",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully (silent failure)
  assert_success

  # Should have no output
  assert_output ""

  # State file should STILL EXIST
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 3: Empty handoff output preserves state file
# bats test_tags=critical,error-handling,retry
@test "should preserve state file when claude returns empty output" {
  # Create mock claude that returns empty output
  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
# Return nothing
exit 0
EOF
  chmod +x "$MOCK_CLAUDE_DIR/claude"
  export PATH="$MOCK_CLAUDE_DIR:$PATH"

  # Create valid state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "550e8400-e29b-41d4-a716-446655440000" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "empty test",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-empty",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should STILL EXIST (preserved for retry)
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 4: Verify error conditions don't delete directory either
# bats test_tags=critical,cleanup-consistency
@test "should not delete directory when preserving state file on error" {
  # Create mock claude that fails
  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$MOCK_CLAUDE_DIR/claude"
  export PATH="$MOCK_CLAUDE_DIR:$PATH"

  # Create valid state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "550e8400-e29b-41d4-a716-446655440000" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "directory test",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify directory exists
  assert_dir_exist "$TEST_REPO/.git/handoff-pending"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-dir-test",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"
  assert_success

  # Both file AND directory should still exist
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_dir_exist "$TEST_REPO/.git/handoff-pending"
}

# Test 5: Specific test for "No conversation found" string matching
# bats test_tags=critical,string-matching
@test "should detect 'No conversation found' in claude output regardless of case" {
  # Create mock claude that returns the error mixed into other output
  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
echo "Searching for session..."
echo "No conversation found for the specified session ID"
echo "Please check your session ID and try again"
exit 0
EOF
  chmod +x "$MOCK_CLAUDE_DIR/claude"
  export PATH="$MOCK_CLAUDE_DIR:$PATH"

  # Create valid state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "550e8400-e29b-41d4-a716-446655440000" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "string match test",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-string-match",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully (detected error)
  assert_success

  # Should have no output (silent failure for retry)
  assert_output ""

  # State file should be preserved
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}
