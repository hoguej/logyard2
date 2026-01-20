# Pre-Commit Check Queue

## Purpose
Validates code quality before committing. Runs linters, formatters, type checkers, and basic tests to ensure code meets quality standards. Creates fix tasks for any issues found.

## Queue Type
`pre-commit-check`

## Input
- **Code changes** (from `execution` queue)
- **Feature branch** (with uncommitted changes)
- **Workspace** (agent workspace)

## Output
- **Quality check results** (pass/fail with details)
- **Fix tasks** (queued to `execution` queue if issues found)
- **Next step**: If passes, queues to `commit-build` queue

## Task Structure
```json
{
  "title": "PRE-COMMIT-CHECK: <feature-branch>",
  "description": "Validate code quality before commit",
  "context": {
    "workspace": "<agent-workspace-path>",
    "branch": "<feature-branch-name>",
    "execution_task_id": <task-id>,
    "changed_files": ["path/to/file1", "path/to/file2"]
  },
  "priority": 2,
  "checks": [
    "lint",
    "format",
    "type-check",
    "unit-tests",
    "integration-tests"
  ]
}
```

## Workflow
1. **Agent claims task** from `pre-commit-check` queue
2. **Navigate to existing workspace** - Use workspace created by execution step
   - Read workspace path from task context
   - Verify workspace exists
   - Checkout feature branch
3. **Run quality checks**:
   - Linter (eslint, pylint, etc.)
   - Formatter (prettier, black, etc.)
   - Type checker (TypeScript, mypy, etc.)
   - Unit tests
   - Integration tests
   - Code coverage check
4. **Analyze results**:
   - Collect all errors/warnings
   - Categorize by type
   - Determine fix approach
5. **Create fix tasks** (if issues found):
   - Queue fix tasks to `execution` queue
   - Link back to original execution task
   - Set appropriate priorities
6. **Queue next step** (if passes):
   - Automatically queue to `commit-build` queue (Step 05)
   - Pass workspace path in task context
7. **Announce completion**: Queue to `announce` queue with check results
8. **Mark complete** - Check done, fixes queued or ready for commit

## Check Types
- **Linting**: Code style, best practices
- **Formatting**: Code formatting consistency
- **Type checking**: Type safety validation
- **Unit tests**: Fast, isolated tests
- **Integration tests**: Component integration tests
- **Coverage**: Code coverage thresholds

## Error Handling
- If checks fail: Create fix tasks in `execution` queue
- If fix tasks created: Original execution task marked as "needs-fix"
- If repeatedly failing: Queue to `announce` for human review
- If blocked: Queue to `announce` with blocker information

## Integration Points
- **Input**: Receives from `execution` queue (Step 03)
- **Output**: 
  - Queues fix tasks to `execution` queue (if issues)
  - Queues to `commit-build` queue (if passes) (Step 05)
- **Blockers**: Uses `announce` queue for persistent issues
- **Announcements**: Announces work start, completion, and status

## Agent Script
- **Script**: `agent-pre-commit-check.sh`
- **Workspace**: **USES EXISTING WORKSPACE** (created by execution step)
- **Cursor Agent**: Invokes Cursor agent to run quality checks
- **Auto-Queue**: Automatically queues to commit-build on success
- **Workspace Lifecycle**: Uses workspace, does not create or destroy

## Queue Process Requirements

### Process Architecture
- **Dedicated Process**: Runs in continuous loop, monitors `pre-commit-check` queue
- **Multiple Instances**: Can run multiple processes in parallel for scalability
- **Generic Logic**: Uses shared queue handling (claiming, status updates, heartbeats)
- **Queue-Specific Logic**: 
  - Workspace path retrieval from task context
  - Quality check execution (lint, format, type-check, tests)
  - Fix task creation for failures
  - Automatic queuing to commit-build on success

### Process Lifecycle
- **Modification Date Tracking**: Monitors script file modification date
- **Graceful Shutdown**: On code change, completes current task and exits
- **Restart Required**: Must be manually restarted after code updates

### Process Flow
1. Loop: Check for available tasks in `pre-commit-check` queue
2. Claim: Atomically claim a task (if available)
3. Load Workspace: Read workspace path from task context, verify exists
4. Execute: Invoke Cursor agent to run quality checks in workspace
5. Update: 
   - If passes: Mark task complete, queue to commit-build
   - If fails: Create fix tasks, mark task as needs-fix
6. Announce: Create announcement via announce queue
7. Monitor: Check script modification date
8. Repeat: Return to step 1 (or exit if code changed)

## Success Criteria
- All quality checks pass
- Code meets project standards
- Tests pass
- Coverage thresholds met
- Ready for commit and build

## Fix Task Creation
When issues are found, create tasks like:
- `FIX: Linting errors in <file>`
- `FIX: Type errors in <file>`
- `FIX: Failing tests in <test-file>`
- `FIX: Formatting issues in <file>`

## Best Practices & Strategic Guidance

### Code Quality Validation Strategy

1. **Automated Validation First**: Run automated checks before manual review
   - Use linters, formatters, type checkers
   - Run test suites automatically
   - Check coverage thresholds
   - Catch issues early in the pipeline

2. **Comprehensive Check Suite**: Run all relevant checks
   - **Linting**: Code style, best practices, potential bugs
   - **Formatting**: Consistency in code style
   - **Type Checking**: Type safety validation
   - **Unit Tests**: Fast, isolated component tests
   - **Integration Tests**: Component interaction tests
   - **Coverage**: Ensure adequate test coverage

3. **Environment Isolation**: Run checks in isolated environment
   - Use temporary or shadowed environment
   - Avoid corrupting main workspace
   - Clean up after checks complete

4. **Error Categorization**: Categorize issues by type and severity
   - **Critical**: Blocks commit (errors, failing tests)
   - **Warning**: Should fix but not blocking (style issues)
   - **Info**: Suggestions for improvement

### Fix Task Creation Best Practices

1. **Specific Fix Tasks**: Create targeted fix tasks
   - One task per issue category (linting, tests, types)
   - Include specific file paths and line numbers
   - Provide error messages and context

2. **Link to Original Task**: Connect fix tasks to execution task
   - Enable traceability
   - Track which execution task needs fixes
   - Prevent duplicate fixes

3. **Priority Assignment**: Set appropriate priorities
   - Critical issues: High priority
   - Warnings: Normal priority
   - Info: Low priority

4. **Error Context**: Include full error context in fix tasks
   - Error messages and stack traces
   - File paths and line numbers
   - Test output and logs
   - Last 50-100 lines of relevant logs

### Retry and Escalation Logic

1. **Retry Limits**: Prevent infinite fix loops
   - Track retry count per task
   - Escalate after max retries (e.g., 3-5 attempts)
   - Queue to `announce` for human review

2. **Pattern Recognition**: Identify recurring issues
   - Track common error patterns
   - Flag if same error occurs multiple times
   - May indicate design or approach issue

3. **Human Escalation**: Escalate persistent issues
   - After max retries, queue to `announce`
   - Request human intervention
   - May need to re-queue to `planning` or `requirements-research`

### Quality Gates

1. **All Checks Must Pass**: No exceptions for critical checks
   - Tests must pass
   - No critical linting errors
   - Type checking must pass

2. **Coverage Thresholds**: Enforce minimum coverage
   - New code must meet coverage threshold
   - Overall coverage should not decrease
   - Document exceptions if needed

3. **Performance Checks**: Verify no performance regressions
   - Run performance benchmarks if applicable
   - Check for obvious performance issues
   - Flag significant slowdowns
