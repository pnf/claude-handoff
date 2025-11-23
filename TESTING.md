# Testing Guide for Claude-Handoff Plugin

This guide covers manual testing procedures for the claude-handoff plugin hooks.

## Quick Test Setup

### Enable Debug Logging

Uncomment the logging sections in both hook scripts:

**In `handoff-plugin/hooks/entrypoints/pre-compact.sh`:**
```bash
# Change:
# LOG_FILE="/tmp/handoff-precompact.log"
# To:
LOG_FILE="/tmp/handoff-precompact.log"

# And uncomment the exec/set -x/echo lines
```

**In `handoff-plugin/hooks/entrypoints/session-start.sh`:**
```bash
# Change:
# LOG_FILE="/tmp/handoff-sessionstart.log"
# To:
LOG_FILE="/tmp/handoff-sessionstart.log"

# And uncomment the exec/set -x/echo lines
```

### Monitor Logs in Real-Time

Open two terminal windows:

**Terminal 1: Monitor PreCompact**
```bash
touch /tmp/handoff-precompact.log
tail -f /tmp/handoff-precompact.log
```

**Terminal 2: Monitor SessionStart**
```bash
touch /tmp/handoff-sessionstart.log
tail -f /tmp/handoff-sessionstart.log
```

---

## Test 1: Manual /compact

**Goal:** Verify hooks fire when user runs `/compact`

### Steps

1. **Start a conversation** in Claude Code with substantial context:
   ```bash
   # In your project directory
   claude
   ```

2. **Build up context** (interact with Claude):
   - Read several files
   - Make code changes
   - Run commands
   - Aim for at least 20-30 tool uses

3. **Run manual compact:**
   ```
   /compact
   ```

4. **Check PreCompact log:**
   ```bash
   tail -20 /tmp/handoff-precompact.log
   ```

   **Expected output:**
   ```
   [2025-11-23T12:00:00+13:00] PreCompact hook triggered
   [2025-11-23T12:00:00+13:00] Received input: session_id=abc123... trigger=manual cwd=/path/to/project
   [2025-11-23T12:00:00+13:00] State saved to .git/handoff-pending/handoff-context.json
   ```

5. **Verify state file created:**
   ```bash
   cat .git/handoff-pending/handoff-context.json
   ```

   **Expected format:**
   ```json
   {
     "previous_session": "abc123...",
     "trigger": "manual",
     "cwd": "/path/to/project",
     "type": "compact"
   }
   ```

6. **After compact completes, check SessionStart log:**
   ```bash
   tail -30 /tmp/handoff-sessionstart.log
   ```

   **Expected output:**
   ```
   [2025-11-23T12:00:05+13:00] SessionStart hook triggered
   [2025-11-23T12:00:05+13:00] Received input: cwd=/path/to/project source=compact
   [2025-11-23T12:00:05+13:00] Found state file: .git/handoff-pending/handoff-context.json
   [2025-11-23T12:00:05+13:00] State: type=compact session=abc123... trigger=manual
   [2025-11-23T12:00:05+13:00] Invoking claude --resume abc123...
   [2025-11-23T12:00:15+13:00] Handoff length: 542 chars
   [2025-11-23T12:00:15+13:00] Handoff generated successfully, returning additionalContext
   ```

7. **Verify handoff injected** - Look in the new session for:
   ```
   <session-start-hook>
   ## What we were working on
   [Generated handoff content]
   </session-start-hook>
   ```

8. **Verify state cleanup:**
   ```bash
   ls .git/handoff-pending/
   # Should return: "No such file or directory"
   ```

### Success Criteria

- ✅ PreCompact log shows hook triggered with `trigger=manual`
- ✅ State file created with correct JSON structure
- ✅ SessionStart log shows hook triggered with `source=compact`
- ✅ `claude --resume` invoked with previous session ID
- ✅ Handoff content appears in new session
- ✅ State file cleaned up after completion

---

## Test 2: Auto-compact at 95%

**Goal:** Verify hooks fire on automatic compaction

### Steps

1. **Start a conversation** and build up context aggressively:
   - Read large files repeatedly
   - Generate extensive outputs
   - Use tools that produce verbose results
   - Monitor context % in status line

2. **Watch for auto-compact** (happens at ~95% context):
   - Status line will show compaction occurring
   - Session will briefly pause

3. **Check PreCompact log:**
   ```bash
   grep "trigger=auto" /tmp/handoff-precompact.log
   ```

   **Expected:** Should show `trigger=auto` instead of `manual`

4. **Follow same verification steps as Test 1** (steps 5-8)

### Success Criteria

- ✅ PreCompact log shows `trigger=auto`
- ✅ All other success criteria from Test 1

---

## Test 3: /clear Still Works

**Goal:** Verify /clear handoff functionality remains intact

### Steps

1. **Start a conversation** with some context

2. **Run /clear:**
   ```
   /clear
   ```

3. **Check SessionEnd log** (not SessionStart):
   ```bash
   # session-end.sh doesn't have logging by default, so check state file:
   cat .git/handoff-pending/handoff-context.json
   ```

   **Expected:**
   ```json
   {
     "previous_session": "xyz789...",
     "cwd": "/path/to/project",
     "type": "clear"
   }
   ```

   Note: `type` should be `"clear"` not `"compact"`

4. **After /clear, check SessionStart log:**
   ```bash
   tail -30 /tmp/handoff-sessionstart.log
   ```

   **Expected:** Should show handoff generation with `type=clear`

5. **Verify handoff customization:**
   - Look for: `"The previous session was cleared by the user"`
   - NOT: `"The previous session was compacted"`

### Success Criteria

- ✅ SessionEnd creates state file with `type: "clear"`
- ✅ SessionStart detects clear type
- ✅ Handoff prompt uses "cleared" language
- ✅ Handoff appears in new session

---

## Test 4: SessionStart on Normal Startup (Should Skip)

**Goal:** Verify SessionStart doesn't fire on normal startup

### Steps

1. **Exit Claude Code completely:**
   ```
   exit
   ```

2. **Clear logs:**
   ```bash
   > /tmp/handoff-sessionstart.log
   ```

3. **Start Claude Code normally:**
   ```bash
   claude
   ```

4. **Check SessionStart log:**
   ```bash
   cat /tmp/handoff-sessionstart.log
   ```

   **Expected:**
   - Either empty (hook didn't run)
   - Or shows "No state file found, exiting"

5. **Verify no handoff injection in session**

### Success Criteria

- ✅ No handoff appears on normal startup
- ✅ Hook exits silently when no state file present

---

## Test 5: Standalone Script Testing (No Claude Code)

**Goal:** Test hooks in isolation with fake inputs

### Test PreCompact Standalone

```bash
cd handoff-plugin/hooks/entrypoints

# Test with fake input
echo '{
  "session_id": "test-session-123",
  "trigger": "manual",
  "cwd": "'$(pwd)'"
}' | bash pre-compact.sh

# Verify output
cat ../../../.git/handoff-pending/handoff-context.json

# Expected: Valid JSON with session_id, trigger, type=compact

# Cleanup
rm -rf ../../../.git/handoff-pending
```

### Test SessionStart Standalone

```bash
cd handoff-plugin/hooks/entrypoints

# First, find a real session ID from your history
ls ~/.claude/projects/*/
# Pick a project and note the session dir name

# Create fake state
mkdir -p ../../../.git/handoff-pending
echo '{
  "previous_session": "REPLACE_WITH_REAL_SESSION_ID",
  "type": "compact",
  "trigger": "manual",
  "cwd": "'$(pwd)'"
}' > ../../../.git/handoff-pending/handoff-context.json

# Test with fake input
echo '{
  "cwd": "'$(pwd)'",
  "source": "compact"
}' | bash session-start.sh

# Expected: JSON output with hookSpecificOutput.additionalContext containing handoff

# Cleanup
rm -rf ../../../.git/handoff-pending
```

---

## Troubleshooting

### No Logs Appearing

**Cause:** Debug logging not enabled

**Fix:**
1. Edit both hook scripts
2. Uncomment all lines with `LOG_FILE`, `exec`, `set -x`, and `echo` commands
3. Create log files manually: `touch /tmp/handoff-*.log`

### State File Persists After Run

**Cause:** Hook errored before cleanup

**Fix:**
```bash
# Manual cleanup
rm -rf .git/handoff-pending

# Check logs for errors
tail -50 /tmp/handoff-sessionstart.log
```

### "No conversation found" Error

**Cause:** Session ID invalid or transcript file missing

**Fix:**
1. Verify session ID exists:
   ```bash
   ls ~/.claude/projects/*/
   ```
2. Check transcript exists:
   ```bash
   ls ~/.claude/projects/YOUR_SESSION_ID/transcript.jsonl
   ```
3. Use a recent session ID from a conversation with actual content

### Handoff Not Appearing in New Session

**Possible causes:**

1. **SessionStart exited early:** Check log for "No state file" or "Invalid handoff type"
2. **claude --resume failed:** Check for error output in SessionStart log
3. **JSON malformed:** SessionStart returned invalid JSON

**Debug:**
```bash
# Enable all debug logging
# Run /compact
# Check both logs thoroughly:
tail -100 /tmp/handoff-precompact.log
tail -100 /tmp/handoff-sessionstart.log
```

### PreCompact Not Firing

**Cause:** Hooks not registered in Claude Code

**Fix:**
1. Verify hooks.json is valid JSON:
   ```bash
   jq . handoff-plugin/hooks/hooks.json
   ```
2. Reload plugin:
   ```bash
   # Exit Claude Code
   # Start again
   claude
   ```
3. Check hook registration in verbose mode:
   ```bash
   claude --verbose
   # Run /compact and look for hook execution messages
   ```

---

## Cleanup After Testing

```bash
# Clear debug logs
rm /tmp/handoff-*.log

# Remove any stuck state files
rm -rf .git/handoff-pending

# Disable debug logging (comment out LOG_FILE lines in both scripts)
```

---

## Advanced: Debugging with --verbose

Run Claude Code in verbose mode to see all hook executions:

```bash
claude --verbose
```

When you run `/compact`, you should see:
```
[hooks] Executing PreCompact hooks...
[hooks] PreCompact hook exited with code 0
[hooks] Executing SessionStart hooks...
[hooks] SessionStart hook exited with code 0
```

If hooks are not listed, there's a registration issue with `hooks.json`.

---

## Test Checklist

Before declaring success, verify all tests pass:

- [ ] Test 1: Manual /compact works
- [ ] Test 2: Auto-compact at 95% works
- [ ] Test 3: /clear still works
- [ ] Test 4: Normal startup doesn't trigger handoff
- [ ] Test 5: Standalone script tests pass
- [ ] Logs show correct trigger values (manual/auto)
- [ ] State files are cleaned up after each run
- [ ] Handoffs are relevant and actionable
- [ ] No errors in hook logs

---

## Next Steps After Testing

Once all tests pass:

1. **Disable debug logging** for production use (comment out LOG_FILE lines)
2. **Document any edge cases** you discovered
3. **Consider adding error handling** for specific failure modes
4. **Share findings** about handoff quality and usefulness
