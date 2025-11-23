# handoff-success.bats - Integration tests for successful handoff injection
#
# Purpose: Test the SessionStart hook injecting pre-generated handoff content
# NOTE: This tests the NEW architecture where PreCompact generates content
#       and SessionStart just injects it (no more claude --resume calls)
# Tests: State file with handoff_content, systemMessage output, cleanup

# bats file_tags=integration,success-path,fork-session-architecture

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

# Teardown: Clean up git repo
teardown() {
  cleanup_test_repo
}

# Test 1: Success path returns valid JSON with systemMessage
# bats test_tags=critical,success-path,systemMessage
@test "should return valid JSON with systemMessage on success" {
  # Create state file with PRE-GENERATED handoff content (as created by PreCompact)
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  local handoff_text="## Goal
Implement OAuth integration for auth system

## Relevant Context
- Basic login already implemented
- Need to add OAuth provider support
- Using passport.js for auth

## Key Details
- src/auth.ts - main auth module
- tests/auth.test.ts - test suite
- Need to support GitHub and Google providers

## Important Notes
- Keep login flow backward compatible
- OAuth tokens stored in secure session"

  jq -n \
    --arg content "$handoff_text" \
    --arg goal "implement OAuth integration" \
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
      session_id: "abc123-continued",
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

  # systemMessage should contain the pre-generated handoff content
  local message_content
  message_content=$(echo "$output" | jq -r '.systemMessage')
  assert_regex "$message_content" "OAuth integration"
  assert_regex "$message_content" "passport.js"
}

# Test 2: Success path cleans up state file and directory
# bats test_tags=critical,cleanup
@test "should clean up state file and directory on success" {
  # Create state file with pre-generated content
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg content "## Goal\nFix authentication bug\n## Context\n- Bug in OAuth flow" \
    --arg goal "fix authentication bug" \
    '{
      handoff_content: $content,
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify state file exists
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "xyz789-continued",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"
  assert_success

  # State file should be deleted after injection
  assert_file_not_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Directory should be deleted (since we only had one file)
  assert_dir_not_exists "$TEST_REPO/.git/handoff-pending"
}

# Test 3: Verify systemMessage JSON structure matches schema
# bats test_tags=critical,schema-validation
@test "should return systemMessage with exact JSON schema" {
  # Create state file with pre-generated content
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg content "## Goal\nSchema test\n## Context\nTest" \
    --arg goal "test schema validation" \
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
      session_id: "schema-test-session",
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

  # systemMessage value should be a string (the pre-generated handoff content)
  local message_type
  message_type=$(echo "$output_json" | jq -r '.systemMessage | type')
  assert_equal "$message_type" "string"

  # systemMessage should contain the actual content we passed
  local message_content
  message_content=$(echo "$output_json" | jq -r '.systemMessage')
  assert_regex "$message_content" "Schema test"
}
