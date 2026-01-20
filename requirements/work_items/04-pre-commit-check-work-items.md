# Work Items: Pre-Commit Check Queue (04)

## Agent Script

### AGENT-04-001: Create agent-pre-commit-check.sh script
- Create dedicated script for pre-commit-check queue
- Implement main loop structure
- Integrate shared queue handling library
- Implement modification date monitoring

### AGENT-04-002: Implement task claiming logic
- Use shared library for atomic task claiming
- Claim from pre-commit-check queue only
- Handle no tasks available case
- Update root work item status to 'checking' when task is claimed

### AGENT-04-003: Implement workspace loading
- Read workspace path from task context
- Verify workspace exists
- Checkout feature branch
- Verify branch exists

### AGENT-04-004: Implement Cursor agent invocation
- Invoke Cursor agent to run quality checks in workspace
- Pass workspace path and changed files
- Handle Cursor agent errors

### AGENT-04-005: Implement quality check execution
- Run linter (eslint, pylint, etc.)
- Run formatter (prettier, black, etc.)
- Run type checker (TypeScript, mypy, etc.)
- Run unit tests
- Run integration tests
- Check code coverage

### AGENT-04-006: Implement check result analysis
- Collect all errors/warnings
- Categorize by type (critical, warning, info)
- Determine fix approach
- Identify specific files and line numbers

### AGENT-04-007: Implement fix task creation
- Create fix tasks in execution queue for failures
- Link back to original execution task
- Set appropriate priorities
- Include error context (messages, stack traces, file paths)
- Set parent_task_id to current pre-commit-check task
- Preserve root_work_item_id from pre-commit-check task
- Update work_item_chain with pre-commit-check task ID

### AGENT-04-008: Implement automatic queuing to commit-build
- If all checks pass, automatically queue to commit-build
- Pass workspace path in task context
- Link to original execution task
- Set parent_task_id to current pre-commit-check task
- Preserve root_work_item_id from pre-commit-check task
- Update work_item_chain with pre-commit-check task ID

### AGENT-04-009: Implement announcement creation
- Announce work start via announce queue
- Announce completion with check results
- Include pass/fail status
- Include fix tasks created (if any)

### AGENT-04-010: Implement error handling
- Handle check failures (create fix tasks)
- Handle repeatedly failing (queue to announce for review)
- Handle blockers (queue to announce)
- Handle Cursor agent failures

## Pre-Commit Check Best Practices Implementation

### CHECK-04-001: Implement comprehensive check suite
- Linting: Code style, best practices, potential bugs
- Formatting: Code formatting consistency
- Type checking: Type safety validation
- Unit tests: Fast, isolated component tests
- Integration tests: Component interaction tests
- Coverage: Ensure adequate test coverage

### CHECK-04-002: Implement environment isolation
- Run checks in isolated environment
- Avoid corrupting main workspace
- Clean up after checks complete

### CHECK-04-003: Implement error categorization
- Categorize by type and severity
- Critical: Blocks commit (errors, failing tests)
- Warning: Should fix but not blocking
- Info: Suggestions for improvement

### CHECK-04-004: Implement fix task creation best practices
- Create targeted fix tasks (one per issue category)
- Include specific file paths and line numbers
- Provide error messages and context
- Link to original execution task

### CHECK-04-005: Implement retry and escalation logic
- Track retry count per task
- Escalate after max retries (3-5 attempts)
- Queue to announce for human review
- Identify recurring error patterns

### CHECK-04-006: Implement quality gates
- All critical checks must pass
- Enforce minimum coverage thresholds
- Verify no performance regressions
- Document exceptions if needed
