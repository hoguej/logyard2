# Work Items: E2E Test Queue (07)

## Agent Script

### AGENT-07-001: Create agent-e2e-test.sh script
- Create dedicated script for e2e-test queue
- Implement main loop structure
- Integrate shared queue handling library
- Implement modification date monitoring
- Note: Optional, can run in parallel with other steps

### AGENT-07-002: Implement task claiming logic
- Use shared library for atomic task claiming
- Claim from e2e-test queue only
- Handle no tasks available case

### AGENT-07-003: Implement Cursor agent invocation
- Invoke Cursor agent to run E2E tests against deployed environment
- Pass deployment URL and test suite
- Handle Cursor agent errors
- Note: No workspace needed (tests run against deployed environment)

### AGENT-07-004: Implement deployment readiness check
- Ensure deployment is complete
- Verify services are ready
- Wait for health checks
- Retry if deployment not ready

### AGENT-07-005: Implement E2E test execution
- Execute test suite
- Monitor test execution
- Collect test results
- Capture screenshots/logs if failures
- Monitor test execution time

### AGENT-07-006: Implement test result analysis
- Identify failing tests
- Categorize failures (functional, performance, integration, infrastructure)
- Determine root causes
- Assess impact (critical, high, medium, low)

### AGENT-07-007: Implement fix task creation
- Create fix tasks in execution queue for failures
- Link to original feature/task
- Set appropriate priorities based on impact
- Include test output and logs

### AGENT-07-008: Implement announcement creation
- Announce test start via announce queue
- Include test suite and scope
- Announce test results on completion
- Include test duration and metrics
- Provide summary of failures

### AGENT-07-009: Implement error handling
- Handle deployment not ready (wait and retry)
- Handle test failures (create fix tasks)
- Handle test infrastructure issues (queue to announce)
- Handle repeatedly failing (queue to announce for review)
- Handle timeouts (queue to announce)

## E2E Test Best Practices Implementation

### E2E-07-001: Implement comprehensive test suite
- User flow tests: Complete user journeys
- Integration tests: Component interactions
- API tests: Backend functionality and endpoints
- UI tests: Frontend functionality and interactions
- Performance tests: Load and response times
- Accessibility tests: A11y compliance

### E2E-07-002: Implement test environment setup
- Use production-like environment
- Match production configuration
- Use production data (anonymized if needed)
- Test with realistic load
- Verify external service integrations

### E2E-07-003: Implement test isolation
- Clean up test data between runs
- Use unique test data per run
- Reset state between tests
- Avoid shared state

### E2E-07-004: Implement failure analysis
- Root cause analysis: Identify why test failed
- Categorization: Classify failure type
- Impact assessment: Determine severity
- Fix strategy: Determine how to fix

### E2E-07-005: Implement retry and flaky test handling
- Retry transient failures (network, timeouts, race conditions)
- Set max retry count (e.g., 3 attempts)
- Identify and handle flaky tests
- Skip flaky tests with notification
- Create tasks to fix flaky tests

### E2E-07-006: Implement test data management
- Use realistic test data
- Clean up after tests
- Avoid data pollution
- Handle test data dependencies

### E2E-07-007: Implement re-run after fixes
- Re-run tests after fixes deployed
- Verify fixes work
- Ensure no regressions
- Confirm all tests pass
