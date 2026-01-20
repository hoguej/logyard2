# E2E Test Queue

## Purpose
Queues up end-to-end tests to run against deployed code. If tests fail, queues work to fix the issues. Ensures features work correctly in the full system context.

**Note**: E2E tests can be run in parallel by any step in the workflow, or via this dedicated queue for parallel processing. This queue is optional and can run concurrently with other steps.

## Queue Type
`e2e-test`

## Input
- **Deployed feature** (from `deploy` queue, deployment succeeded)
- **Feature details** (what was deployed, PR info)
- **Test suite** (which E2E tests to run)

## Output
- **Test results** (pass/fail with details)
- **Fix tasks** (queued to `execution` queue if tests fail)
- **Next step**: If passes, feature is complete

## Task Structure
```json
{
  "title": "E2E-TEST: <feature-name>",
  "description": "Run end-to-end tests for deployed feature",
  "context": {
    "feature_name": "<feature-name>",
    "pr_number": <pr-number>,
    "deployment_url": "<deployment-url>",
    "test_suite": ["test1", "test2"],
    "deploy_task_id": <task-id>
  },
  "priority": 2
}
```

## Workflow
1. **Agent claims task** from `e2e-test` queue
2. **Wait for deployment** (if needed):
   - Ensure deployment is complete
   - Verify services are ready
   - Wait for health checks
3. **Run E2E tests**:
   - Execute test suite
   - Monitor test execution
   - Collect test results
   - Capture screenshots/logs if failures
4. **Analyze results**:
   - Identify failing tests
   - Categorize failures
   - Determine root causes
5. **Create fix tasks** (if tests fail):
   - Queue fix tasks to `execution` queue
   - Link to original feature
   - Set appropriate priorities
6. **Announce results**: Queue to `announce` queue with test results
7. **Mark complete** - Tests run, fixes queued or feature complete

## Test Execution
- Run full E2E test suite or subset
- Tests may include:
  - User flow tests
  - Integration tests
  - API tests
  - UI tests
  - Performance tests
- Monitor test execution time
- Capture detailed failure information

## Error Handling
- If deployment not ready: Wait and retry
- If tests fail: Create fix tasks in `execution` queue
- If test infrastructure issues: Queue to `announce` for investigation
- If repeatedly failing: Queue to `announce` for human review
- If timeout: Queue to `announce` for investigation

## Fix Task Creation
When tests fail, create tasks like:
- `FIX: E2E test failure - <test-name>`
- `FIX: User flow broken - <flow-name>`
- `FIX: API endpoint issue - <endpoint>`
- `FIX: UI regression - <component>`
- `FIX: Performance issue - <metric>`

## Integration Points
- **Input**: Can receive from any step, or run in parallel independently
- **Output**: 
  - Queues fix tasks to `execution` queue (if tests fail)
  - Feature complete if tests pass
- **Status**: Uses `announce` queue to report test results
- **Blockers**: Uses `announce` queue for infrastructure issues
- **Announcements**: Announces work start, completion, and status

## Agent Script
- **Script**: `agent-e2e-test.sh`
- **Workspace**: No workspace needed (tests run against deployed environment)
- **Cursor Agent**: Invokes Cursor agent to run E2E tests
- **Parallel Processing**: Can run concurrently with other workflow steps

## Queue Process Requirements

### Process Architecture
- **Dedicated Process**: Runs in continuous loop, monitors `e2e-test` queue
- **Multiple Instances**: Can run multiple processes in parallel for scalability
- **Generic Logic**: Uses shared queue handling (claiming, status updates, heartbeats)
- **Queue-Specific Logic**: 
  - E2E test execution workflow
  - Test result analysis
  - Fix task creation for test failures
  - Parallel execution support

### Process Lifecycle
- **Modification Date Tracking**: Monitors script file modification date
- **Graceful Shutdown**: On code change, completes current task and exits
- **Restart Required**: Must be manually restarted after code updates

### Process Flow
1. Loop: Check for available tasks in `e2e-test` queue
2. Claim: Atomically claim a task (if available)
3. Execute: Invoke Cursor agent to run E2E tests against deployed environment
4. Analyze: Process test results, identify failures
5. Update: 
   - If tests pass: Mark task complete
   - If tests fail: Create fix tasks
6. Announce: Create announcement via announce queue
7. Monitor: Check script modification date
8. Repeat: Return to step 1 (or exit if code changed)

## Success Criteria
- E2E tests pass
- Feature works correctly in full system
- No regressions introduced
- Performance is acceptable
- Status is announced

## Test Types
- **User flow tests**: Complete user journeys
- **Integration tests**: Component interactions
- **API tests**: Backend functionality
- **UI tests**: Frontend functionality
- **Performance tests**: Load and response times
- **Accessibility tests**: A11y compliance

## Retry Logic
- Retry transient failures
- Skip flaky tests (with notification)
- Re-run after fixes are deployed

## Best Practices & Strategic Guidance

### E2E Testing Strategy: Comprehensive Validation

1. **Test Coverage**: Cover all critical user flows
   - **Happy Path**: Primary user journeys work correctly
   - **Unhappy Path**: Error handling and edge cases
   - **Integration**: Component interactions
   - **Performance**: Response times and load handling

2. **Test Environment**: Use production-like environment
   - Match production configuration
   - Use production data (anonymized if needed)
   - Test with realistic load
   - Verify external service integrations

3. **Test Isolation**: Ensure tests don't interfere with each other
   - Clean up test data between runs
   - Use unique test data per run
   - Reset state between tests
   - Avoid shared state

### Test Execution Best Practices

1. **Comprehensive Test Suite**: Run all relevant tests
   - **User Flow Tests**: Complete user journeys end-to-end
   - **Integration Tests**: Component interactions
   - **API Tests**: Backend functionality and endpoints
   - **UI Tests**: Frontend functionality and interactions
   - **Performance Tests**: Load and response times
   - **Accessibility Tests**: A11y compliance

2. **Failure Analysis**: Deep dive into test failures
   - **Root Cause Analysis**: Identify why test failed
   - **Categorization**: Classify failure type
   - **Impact Assessment**: Determine severity
   - **Fix Strategy**: Determine how to fix

3. **Test Data Management**: Manage test data effectively
   - Use realistic test data
   - Clean up after tests
   - Avoid data pollution
   - Handle test data dependencies

### Fix Task Creation for Test Failures

1. **Specific Fix Tasks**: Create targeted tasks for each failure
   - Link to specific test and failure
   - Include test output and logs
   - Reference specific components/endpoints

2. **Priority Based on Impact**: Set priority based on failure severity
   - Critical user flows: High priority
   - Edge cases: Normal priority
   - Performance issues: Medium priority

3. **Link to Original Task**: Connect fix tasks to execution task
   - Enable full traceability
   - Track which code changes caused failures

### Retry and Flaky Test Handling

1. **Transient Failure Retry**: Retry transient failures
   - Network timeouts
   - Service unavailability
   - Race conditions
   - Set max retry count (e.g., 3 attempts)

2. **Flaky Test Detection**: Identify and handle flaky tests
   - Track test failure patterns
   - Flag tests that fail intermittently
   - Skip flaky tests with notification
   - Create tasks to fix flaky tests

3. **Re-run After Fixes**: Re-run tests after fixes deployed
   - Verify fixes work
   - Ensure no regressions
   - Confirm all tests pass

### Test Result Analysis

1. **Failure Categorization**: Categorize failures by type
   - **Functional**: Feature not working as expected
   - **Performance**: Response times too slow
   - **Integration**: Component interaction issues
   - **Infrastructure**: Test environment issues

2. **Root Cause Analysis**: Identify root causes
   - Analyze error messages and logs
   - Check related code changes
   - Verify test environment
   - Identify patterns across failures

3. **Impact Assessment**: Determine failure impact
   - **Critical**: Blocks feature release
   - **High**: Significant user impact
   - **Medium**: Moderate impact
   - **Low**: Minor issue

### Status Communication

1. **Announce Test Start**: Notify via `announce` queue
   - Include test suite and scope
   - Link to deployment and related tasks
   - Provide estimated duration

2. **Announce Test Results**: Update on completion
   - Success: Feature complete
   - Failure: Link to fix tasks created
   - Include test duration and metrics
   - Provide summary of failures
