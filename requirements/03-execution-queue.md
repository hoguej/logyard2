# Execution Queue

## Purpose
Takes fully-planned, detailed tasks and executes them. This is where the actual coding work happens - implementing features, writing code, making changes.

## Queue Type
`execution`

## Input
- **Planned task** (from `planning` queue)
- **Task details** (implementation approach, files to change, etc.)
- **Workspace** (agent workspace for making changes)

## Output
- **Code changes** (committed to feature branch)
- **Task completion status**
- **Next step**: Automatically queues to `pre-commit-check` queue

## Task Structure
```json
{
  "title": "EXECUTE: <task-title>",
  "description": "<detailed task description>",
  "context": {
    "implementation_approach": "<how to implement>",
    "files_to_change": ["path/to/file1", "path/to/file2"],
    "files_to_create": ["path/to/newfile"],
    "dependencies": [<task-id-1>, <task-id-2>],
    "acceptance_criteria": "<criteria>",
    "testing_requirements": "<what tests needed>"
  },
  "priority": 2,
  "workspace": "<agent-workspace-path>"
}
```

## Workflow
1. **Agent claims task** from `execution` queue
2. **Review task details**:
   - Read implementation approach
   - Understand files to change/create
   - Check dependencies (wait if needed)
3. **Create workspace** (ONLY STEP THAT CREATES WORKSPACE):
   - Clone repository to unique workspace directory
   - Create feature branch
   - Set up workspace context
   - Store workspace path in task context
4. **Execute work**:
   - Make code changes
   - Create new files
   - Follow implementation approach
   - Write code according to standards
5. **Self-review**:
   - Check code quality
   - Verify acceptance criteria
   - Ensure tests are written
6. **Queue pre-commit check**:
   - Automatically queue to `pre-commit-check` queue (Step 04)
   - Pass workspace path in task context
7. **Announce completion**: Queue to `announce` queue with execution summary
8. **Mark complete** - Code changes ready for review, workspace created

## Code Quality Requirements
- Follow project coding standards
- Include appropriate comments
- Write/update tests as specified
- Handle error cases
- Update documentation if needed

## Error Handling
- If implementation unclear: Queue question to `announce` queue
- If blocked by dependency: Wait or queue blocker to `announce`
- If code quality issues: Pre-commit check will catch and queue fixes
- If tests fail: Pre-commit check will queue fixes

## Integration Points
- **Input**: Receives from `planning` queue (Step 02)
- **Output**: Queues to `pre-commit-check` queue automatically (Step 04)
- **Questions**: Uses `announce` queue for clarifications
- **Blockers**: Uses `announce` queue to report issues
- **Dependencies**: Waits for dependent tasks to complete
- **Announcements**: Announces work start, completion, and status

## Agent Script
- **Script**: `agent-execution.sh`
- **Workspace**: **CREATES WORKSPACE** (only step that creates workspace)
- **Cursor Agent**: Invokes Cursor agent to implement code in workspace
- **Auto-Queue**: Automatically queues to pre-commit-check on completion
- **Workspace Lifecycle**: Creates workspace, stores path for steps 4-5 to use

## Queue Process Requirements

### Process Architecture
- **Dedicated Process**: Runs in continuous loop, monitors `execution` queue
- **Multiple Instances**: Can run multiple processes in parallel for scalability
- **Generic Logic**: Uses shared queue handling (claiming, status updates, heartbeats)
- **Queue-Specific Logic**: 
  - Workspace creation (unique to this queue)
  - Code implementation workflow
  - Workspace path storage in task context
  - Automatic queuing to pre-commit-check queue

### Process Lifecycle
- **Modification Date Tracking**: Monitors script file modification date
- **Graceful Shutdown**: On code change, completes current task and exits
- **Restart Required**: Must be manually restarted after code updates

### Process Flow
1. Loop: Check for available tasks in `execution` queue
2. Claim: Atomically claim a task (if available)
3. Create Workspace: Clone repo, create feature branch, set up context
4. Execute: Invoke Cursor agent to implement code in workspace
5. Update: Mark task complete, queue to pre-commit-check with workspace path
6. Announce: Create announcement via announce queue
7. Monitor: Check script modification date
8. Repeat: Return to step 1 (or exit if code changed)

## Success Criteria
- Code changes are complete
- Implementation matches plan
- Acceptance criteria are met
- Tests are written/updated
- Code is ready for pre-commit check

## Best Practices & Strategic Guidance

### Implementation Strategy: Modular Idempotency

1. **Atomic Commits**: Produce small, focused diffs
   - One logical change per commit
   - Easier to review and rollback
   - Better for debugging

2. **Idempotency**: Design code to be safely re-runnable
   - Use `CREATE TABLE IF NOT EXISTS` patterns
   - Check if resources exist before creating
   - Handle partial failures gracefully
   - Critical for retry logic when agents crash

3. **Self-Documentation**: Write code for future agents
   - Include inline comments explaining *why* (not just *what*)
   - Use type hints and clear variable names
   - Document complex logic and decisions
   - Aids future "Refine" and "Fix" agents

4. **Modular Construction**: Write modular, testable code
   - Avoid monolithic scripts
   - Separate concerns into functions/classes
   - Enable unit testing of individual components

5. **Strict Scoping**: Narrow permissions and access
   - Only modify files identified in design phase
   - Use restricted environments (Docker, sandboxed shells)
   - Prevent accidental system damage
   - Follow principle of least privilege

### Code Quality Standards

1. **Follow Project Standards**: Adhere to existing coding conventions
   - Match existing code style
   - Use project's linting/formatting rules
   - Follow architectural patterns

2. **Error Handling**: Comprehensive error handling
   - Handle edge cases and error conditions
   - Provide meaningful error messages
   - Log errors appropriately

3. **Testing**: Write/update tests as specified
   - Unit tests for new functions
   - Integration tests for components
   - Update existing tests if behavior changes

4. **Documentation**: Update docs when needed
   - README updates for new features
   - API documentation for new endpoints
   - Code comments for complex logic

### Dependency Handling

1. **Wait for Dependencies**: Check if dependent tasks are complete
   - Query database for dependency status
   - Wait if dependencies not ready
   - Proceed when dependencies complete

2. **Dependency Output**: Use outputs from dependent tasks
   - Read files/APIs created by dependencies
   - Integrate with components built by dependencies
   - Verify dependency outputs before proceeding

### Self-Review Process

1. **Code Quality Check**: Review own code before marking complete
   - Check for obvious bugs
   - Verify acceptance criteria
   - Ensure tests are written

2. **Plan Verification**: Compare implementation to plan
   - Ensure all planned changes are made
   - Verify files match design specification
   - Confirm approach matches plan

3. **Acceptance Criteria**: Verify all criteria are met
   - Run manual checks if needed
   - Verify functionality works as expected
   - Document any deviations from plan
