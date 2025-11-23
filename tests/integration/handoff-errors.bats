# handoff-errors.bats - Integration tests for handoff error scenarios
#
# Purpose: Test error handling and edge cases
# NOTE: With new fork-session architecture, SessionStart has no external dependencies,
#       so tests focus on missing/invalid state file handling
# Tests: Missing state file, missing handoff_content, empty content

# bats file_tags=integration,error-handling,fork-session-architecture

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
}

# Teardown: Clean up
teardown() {
  cleanup_test_repo
}

# Test 1: No state file should exit silently
# bats test_tags=critical,error-handling
@test "should exit silently when no state file exists" {
  # Do NOT create any state file

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "test-session",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # Verify no state directory was created
  assert_dir_not_exists "$TEST_REPO/.git/handoff-pending"
}

# Test 2: Missing handoff_content in state file should exit silently
# bats test_tags=critical,error-handling
@test "should exit silently when handoff_content missing from state file" {
  # Create state file WITHOUT handoff_content (old format or corrupted)
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg goal "test goal" \
    '{
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "test-session-2",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should still exist (didn't remove it in case of other state)
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 3: Empty handoff_content should exit silently
# bats test_tags=critical,error-handling
@test "should exit silently when handoff_content is empty" {
  # Create state file with empty handoff_content
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg content "" \
    --arg goal "test goal" \
    '{
      handoff_content: $content,
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "test-session-3",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should still exist (didn't clean up for safety)
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 4: Non-"compact" source should be ignored
# bats test_tags=critical,filtering
@test "should ignore non-compact source and exit silently" {
  # Create state file (shouldn't matter)
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg content "test content" \
    '{
      handoff_content: $content,
      goal: "test",
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON with source != "compact"
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "test-session-4",
      cwd: $cwd,
      source: "manual"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should NOT be cleaned up (didn't process handoff)
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}
