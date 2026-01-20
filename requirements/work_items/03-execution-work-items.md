# Work Items: Execution Queue (03)

## Agent Script

### AGENT-03-001: Create agent-execution.sh script
- Create dedicated script for execution queue
- Implement main loop structure
- Integrate shared queue handling library
- Implement modification date monitoring

### AGENT-03-002: Implement task claiming logic
- Use shared library for atomic task claiming
- Claim from execution queue only
- Check dependencies before claiming
- Handle no tasks available case

### AGENT-03-003: Implement dependency checking
- Check if dependent tasks are complete
- Wait if dependencies not ready
- Proceed when dependencies complete
- Handle dependency failures

### AGENT-03-004: Implement workspace creation
- Clone repository to unique workspace directory
- Create feature branch from task title
- Set up workspace context (.context.json)
- Store workspace path in task context
- This is the ONLY step that creates workspace

### AGENT-03-005: Implement Cursor agent invocation
- Invoke Cursor agent to implement code in workspace
- Pass task details, implementation approach, files to change
- Handle Cursor agent errors

### AGENT-03-006: Implement code execution workflow
- Make code changes according to plan
- Create new files as specified
- Follow implementation approach
- Write code according to project standards

### AGENT-03-007: Implement self-review process
- Check code quality
- Verify acceptance criteria
- Ensure tests are written
- Compare implementation to plan

### AGENT-03-008: Implement automatic queuing to pre-commit-check
- After execution complete, automatically queue to pre-commit-check
- Pass workspace path in task context
- Link to original execution task

### AGENT-03-009: Implement announcement creation
- Announce work start via announce queue
- Announce completion with execution summary
- Include files changed/created
- Include next step (pre-commit-check task ID)

### AGENT-03-010: Implement error handling
- Handle unclear implementation (queue question to announce)
- Handle blocked by dependency (wait or queue blocker)
- Handle Cursor agent failures
- Handle workspace creation failures

## Execution Best Practices Implementation

### EXEC-03-001: Implement idempotency patterns
- Use CREATE TABLE IF NOT EXISTS patterns
- Check if resources exist before creating
- Handle partial failures gracefully
- Enable safe retry logic

### EXEC-03-002: Implement self-documentation
- Include inline comments explaining why
- Use type hints and clear variable names
- Document complex logic and decisions
- Write code for future agents

### EXEC-03-003: Implement modular construction
- Write modular, testable code
- Avoid monolithic scripts
- Separate concerns into functions/classes
- Enable unit testing

### EXEC-03-004: Implement strict scoping
- Only modify files identified in plan
- Use restricted environments if needed
- Prevent accidental system damage
- Follow principle of least privilege

### EXEC-03-005: Implement code quality standards
- Follow project coding conventions
- Match existing code style
- Use project's linting/formatting rules
- Follow architectural patterns

### EXEC-03-006: Implement comprehensive error handling
- Handle edge cases and error conditions
- Provide meaningful error messages
- Log errors appropriately

### EXEC-03-007: Implement testing requirements
- Write unit tests for new functions
- Write integration tests for components
- Update existing tests if behavior changes

### EXEC-03-008: Implement documentation updates
- Update README for new features
- Update API documentation for new endpoints
- Add code comments for complex logic
