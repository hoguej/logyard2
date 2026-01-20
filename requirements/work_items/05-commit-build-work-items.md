# Work Items: Commit & Build Queue (05)

## Agent Script

### AGENT-05-001: Create agent-commit-build.sh script
- Create dedicated script for commit-build queue
- Implement main loop structure
- Integrate shared queue handling library
- Implement modification date monitoring

### AGENT-05-002: Implement task claiming logic
- Use shared library for atomic task claiming
- Claim from commit-build queue only
- Handle no tasks available case
- Update root work item status to 'building' when task is claimed

### AGENT-05-003: Implement workspace loading
- Read workspace path from task context
- Verify workspace exists
- Ensure on feature branch
- Verify branch exists

### AGENT-05-004: Implement Cursor agent invocation
- Invoke Cursor agent to commit, push, create PR in workspace
- Pass workspace path and commit message
- Handle Cursor agent errors

### AGENT-05-005: Implement commit workflow
- Stage all changes
- Create commit with proper message format: `[agent-name] <type>: <description>`
- Follow conventional commit format
- Handle commit failures

### AGENT-05-006: Implement push workflow
- Push feature branch to remote
- Handle merge conflicts
- Handle push failures
- Retry transient failures

### AGENT-05-007: Implement PR creation
- Use GitHub API or CLI to create PR
- Include comprehensive PR description:
  - What was changed
  - Why it was changed
  - How to test
  - Related tasks/issues
- Auto-apply appropriate labels
- Request appropriate reviewers

### AGENT-05-008: Implement build monitoring
- Watch CI/CD pipeline status
- Check build status periodically
- Monitor test results
- Wait for completion with timeout
- Handle build timeouts

### AGENT-05-009: Implement build result handling
- If build passes: Queue to deploy queue
  - Set parent_task_id to current commit-build task
  - Preserve root_work_item_id from commit-build task
  - Update work_item_chain with commit-build task ID
- If build fails: Create fix tasks in execution queue
  - Set parent_task_id to current commit-build task
  - Preserve root_work_item_id from commit-build task
  - Update work_item_chain with commit-build task ID
- Categorize build failures (compilation, tests, lint, infrastructure, dependencies)
- Link fix tasks to original execution task

### AGENT-05-010: Implement announcement creation
- Announce PR creation via announce queue
- Include PR URL and summary
- Announce build status on completion
- Include build duration and metrics

### AGENT-05-011: Implement error handling
- Handle commit failures (queue to announce)
- Handle push failures/conflicts (queue conflict resolution)
- Handle PR creation failures (queue to announce)
- Handle build failures (create fix tasks)
- Handle build timeouts (queue to announce)

## Commit & Build Best Practices Implementation

### COMMIT-05-001: Implement meaningful commit messages
- Follow conventional commit format
- Include context about what and why
- Reference related tasks/issues
- Use appropriate commit types

### COMMIT-05-002: Implement atomic commits
- One logical change per commit
- Easier to review and understand
- Better for rollback if needed

### COMMIT-05-003: Implement comprehensive PR descriptions
- Include what, why, how, testing info
- Add screenshots if UI changes
- Link to related tasks/issues
- Provide clear context

### COMMIT-05-004: Implement build monitoring best practices
- Monitor all CI/CD pipeline stages
- Set reasonable timeouts
- Retry transient failures
- Escalate if consistently timing out

### COMMIT-05-005: Implement build error analysis
- Categorize build failures
- Compilation errors: Code syntax/type issues
- Test failures: Functional issues
- Lint errors: Code quality issues
- Infrastructure: CI/CD pipeline issues
- Dependencies: Package/dependency issues

### COMMIT-05-006: Implement fix task creation for build failures
- Create targeted tasks for each failure type
- Link to specific build log sections
- Include error messages and stack traces
- Reference specific files and line numbers

### COMMIT-05-007: Implement conflict resolution
- Handle merge conflicts automatically when possible
- Use merge strategies (merge, rebase, squash)
- Queue to execution for complex conflicts
- Keep feature branch up to date
