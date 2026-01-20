# Commit & Build Queue

## Purpose
Commits code changes, pushes to remote, creates PR, and watches for build errors. If build errors occur, creates tasks to fix them. Monitors CI/CD pipeline.

## Queue Type
`commit-build`

## Input
- **Code changes** (from `pre-commit-check` queue, passed checks)
- **Feature branch** (with committed changes ready to push)
- **Workspace** (agent workspace)

## Output
- **Committed code** (pushed to remote)
- **Pull Request** (created on GitHub)
- **Build status** (monitoring results)
- **Fix tasks** (queued to `execution` queue if build fails)

## Task Structure
```json
{
  "title": "COMMIT-BUILD: <feature-branch>",
  "description": "Commit, push, create PR, and monitor build",
  "context": {
    "workspace": "<agent-workspace-path>",
    "branch": "<feature-branch-name>",
    "execution_task_id": <task-id>,
    "commit_message": "<commit-message>",
    "pr_title": "<pr-title>",
    "pr_description": "<pr-description>"
  },
  "priority": 2
}
```

## Workflow
1. **Agent claims task** from `commit-build` queue
2. **Navigate to existing workspace** - Use workspace created by execution step
   - Read workspace path from task context
   - Verify workspace exists
   - Ensure on feature branch
3. **Commit changes**:
   - Stage all changes
   - Create commit with proper message
   - Format: `[agent-name] <descriptive-message>`
4. **Push to remote**:
   - Push feature branch
   - Handle conflicts if needed
5. **Create Pull Request**:
   - Use GitHub API or CLI
   - Include PR description from context
   - Link to related tasks/issues
6. **Monitor build**:
   - Watch CI/CD pipeline
   - Check build status
   - Monitor test results
   - Wait for completion
7. **Handle build results**:
   - **If passes**: Queue to `deploy` queue (Step 06)
   - **If fails**: Create fix tasks in `execution` queue
8. **Announce status**: Queue to `announce` queue with results
9. **Mark complete** - PR created, build monitored

## Build Monitoring
- Watch CI/CD pipeline status
- Check for:
  - Compilation errors
  - Test failures
  - Linting errors
  - Type errors
  - Deployment errors
- Timeout after reasonable period
- Retry logic for transient failures

## Error Handling
- If commit fails: Queue to `announce` for manual intervention
- If push fails (conflicts): Queue conflict resolution to `execution`
- If PR creation fails: Queue to `announce` for manual creation
- If build fails: Create fix tasks in `execution` queue
- If build timeout: Queue to `announce` for investigation

## Fix Task Creation
When build fails, create tasks like:
- `FIX: Build error in <component>`
- `FIX: Test failure in <test-suite>`
- `FIX: CI/CD pipeline error`
- `FIX: Dependency issue in <package>`

## Integration Points
- **Input**: Receives from `pre-commit-check` queue (Step 04)
- **Output**: 
  - Queues to `deploy` queue (if build passes) (Step 06)
  - Queues fix tasks to `execution` queue (if build fails)
- **Status**: Uses `announce` queue to report PR and build status
- **Blockers**: Uses `announce` queue for manual intervention needs
- **Announcements**: Announces work start, completion, and status

## Agent Script
- **Script**: `agent-commit-build.sh`
- **Workspace**: **USES EXISTING WORKSPACE** (created by execution step)
- **Cursor Agent**: Invokes Cursor agent to commit, push, create PR
- **Auto-Queue**: Automatically queues to deploy on build success
- **Workspace Lifecycle**: Uses workspace, does not create or destroy

## Queue Process Requirements

### Process Architecture
- **Dedicated Process**: Runs in continuous loop, monitors `commit-build` queue
- **Multiple Instances**: Can run multiple processes in parallel for scalability
- **Generic Logic**: Uses shared queue handling (claiming, status updates, heartbeats)
- **Queue-Specific Logic**: 
  - Workspace path retrieval from task context
  - Commit, push, PR creation workflow
  - Build monitoring and status checking
  - Fix task creation for build failures
  - Automatic queuing to deploy on build success

### Process Lifecycle
- **Modification Date Tracking**: Monitors script file modification date
- **Graceful Shutdown**: On code change, completes current task and exits
- **Restart Required**: Must be manually restarted after code updates

### Process Flow
1. Loop: Check for available tasks in `commit-build` queue
2. Claim: Atomically claim a task (if available)
3. Load Workspace: Read workspace path from task context, verify exists
4. Execute: Invoke Cursor agent to commit, push, create PR in workspace
5. Monitor Build: Watch CI/CD pipeline, check build status
6. Update: 
   - If build passes: Mark task complete, queue to deploy
   - If build fails: Create fix tasks, mark task as needs-fix
7. Announce: Create announcement via announce queue
8. Monitor: Check script modification date
9. Repeat: Return to step 1 (or exit if code changed)

## Success Criteria
- Code is committed and pushed
- PR is created successfully
- Build passes (or fix tasks are queued)
- Status is announced
- Next step (deploy) is queued if successful

## PR Details
- **Title**: Descriptive, includes feature name
- **Description**: 
  - What was changed
  - Why it was changed
  - How to test
  - Related tasks/issues
- **Labels**: Auto-apply appropriate labels
- **Reviewers**: Request reviews if configured

## Best Practices & Strategic Guidance

### Commit Best Practices

1. **Meaningful Commit Messages**: Follow conventional commit format
   - Format: `[agent-name] <type>: <description>`
   - Types: feat, fix, docs, style, refactor, test, chore
   - Include context about what and why
   - Reference related tasks/issues

2. **Atomic Commits**: One logical change per commit
   - Easier to review and understand
   - Better for rollback if needed
   - Clearer git history

3. **Small, Focused PRs**: Keep PRs manageable
   - Easier to review
   - Faster to merge
   - Lower risk of conflicts

### Pull Request Best Practices

1. **Comprehensive PR Description**: Include all relevant information
   - **What**: Summary of changes
   - **Why**: Motivation and context
   - **How**: Implementation approach (high-level)
   - **Testing**: How to test the changes
   - **Screenshots**: If UI changes
   - **Related**: Links to tasks, issues, other PRs

2. **Auto-Labeling**: Apply appropriate labels automatically
   - Feature type (frontend, backend, infrastructure)
   - Priority level
   - Breaking changes
   - Documentation updates

3. **Reviewer Assignment**: Request appropriate reviewers
   - Based on files changed
   - Based on feature area
   - Include code owners if configured

### Build Monitoring Best Practices

1. **Watch CI/CD Pipeline**: Monitor all stages
   - Build stage (compilation)
   - Test stage (unit, integration)
   - Lint stage (code quality)
   - Deploy stage (if applicable)

2. **Timeout Handling**: Set reasonable timeouts
   - Don't wait indefinitely
   - Retry transient failures
   - Escalate if consistently timing out

3. **Error Analysis**: Categorize build failures
   - **Compilation errors**: Code syntax/type issues
   - **Test failures**: Functional issues
   - **Lint errors**: Code quality issues
   - **Infrastructure**: CI/CD pipeline issues
   - **Dependencies**: Package/dependency issues

### Fix Task Creation for Build Failures

1. **Specific Fix Tasks**: Create targeted tasks for each failure type
   - Link to specific build log sections
   - Include error messages and stack traces
   - Reference specific files and line numbers

2. **Priority Based on Impact**: Set priority based on failure severity
   - Critical failures: High priority
   - Test failures: Medium priority
   - Warnings: Low priority

3. **Link to Original Task**: Connect fix tasks to execution task
   - Enable full traceability
   - Track which code changes caused failures

### Conflict Resolution

1. **Merge Conflicts**: Handle conflicts automatically when possible
   - Use merge strategies (merge, rebase, squash)
   - Auto-resolve simple conflicts
   - Queue to `execution` for complex conflicts

2. **Branch Updates**: Keep feature branch up to date
   - Rebase on main/master regularly
   - Resolve conflicts early
   - Avoid large merge conflicts

### Status Communication

1. **Announce PR Creation**: Notify via `announce` queue
   - Include PR URL
   - Link to related tasks
   - Provide summary of changes

2. **Announce Build Status**: Update on build completion
   - Success: Link to deploy queue
   - Failure: Link to fix tasks created
   - Include build duration and key metrics
