# Deploy Queue

## Purpose
Merges approved PRs, watches deployment process, and monitors for deployment errors. If errors occur, creates tasks to fix them. Ensures successful deployment to production/staging.

## Queue Type
`deploy`

## Input
- **Pull Request** (from `commit-build` queue, build passed)
- **PR details** (number, branch, changes)
- **Deployment target** (staging, production, etc.)

## Output
- **Merged PR** (code merged to main/master)
- **Deployment status** (success/failure)
- **Fix tasks** (queued to `execution` queue if deployment fails)
- **Next step**: Queues to `e2e-test` queue if deployment succeeds

## Task Structure
```json
{
  "title": "DEPLOY: PR #<pr-number> - <feature-name>",
  "description": "Merge PR and monitor deployment",
  "context": {
    "pr_number": <pr-number>,
    "pr_url": "<pr-url>",
    "branch": "<feature-branch-name>",
    "target": "staging|production",
    "commit_build_task_id": <task-id>
  },
  "priority": 2
}
```

## Workflow
1. **Agent claims task** from `deploy` queue
2. **Note**: This step does NOT use workspace (just merges PR and monitors)
3. **Check PR status**:
   - Verify PR is approved (if required)
   - Check for merge conflicts
   - Ensure all checks pass
3. **Merge PR**:
   - Merge to main/master branch
   - Use appropriate merge strategy
   - Handle merge conflicts if needed
4. **Monitor deployment**:
   - Watch deployment pipeline
   - Monitor deployment logs
   - Check deployment status
   - Verify services are healthy
5. **Run smoke tests**:
   - Basic functionality checks
   - Service health checks
   - API endpoint checks
6. **Handle deployment results**:
   - **If succeeds**: 
     - Destroy workspace (cleanup)
     - Optionally queue to `e2e-test` queue (parallel processing)
   - **If fails**: 
     - Preserve workspace (for fix agents to use)
     - Create fix tasks in `execution` queue
7. **Announce status**: Queue to `announce` queue with results
8. **Mark complete** - Deployment monitored, workspace destroyed on success

## Deployment Monitoring
- Watch deployment pipeline:
  - Build stage
  - Deploy stage
  - Health checks
  - Service startup
- Monitor for:
  - Deployment errors
  - Service crashes
  - Health check failures
  - Performance degradation
- Timeout after reasonable period
- Retry logic for transient failures

## Error Handling
- If PR not approved: Queue to `announce` for approval
- If merge conflicts: Queue conflict resolution to `execution`
- If merge fails: Queue to `announce` for manual merge
- If deployment fails: Create fix tasks in `execution` queue
- If deployment timeout: Queue to `announce` for investigation
- If services unhealthy: Create fix tasks in `execution` queue

## Fix Task Creation
When deployment fails, create tasks like:
- `FIX: Deployment error in <service>`
- `FIX: Service crash in <component>`
- `FIX: Health check failure in <service>`
- `FIX: Configuration error in <env>`
- `FIX: Database migration issue`
- `FIX: Dependency issue in deployment`

## Integration Points
- **Input**: Receives from `commit-build` queue (Step 05)
- **Output**: 
  - Optionally queues to `e2e-test` queue (if deployment succeeds, parallel processing)
  - Queues fix tasks to `execution` queue (if deployment fails)
- **Status**: Uses `announce` queue to report deployment status
- **Blockers**: Uses `announce` queue for manual intervention needs
- **Announcements**: Announces work start, completion, and status

## Agent Script
- **Script**: `agent-deploy.sh`
- **Workspace**: **DESTROYS WORKSPACE** on successful deployment
- **Cursor Agent**: Invokes Cursor agent to merge PR and monitor deployment
- **Workspace Lifecycle**: 
  - Does NOT use workspace (just merges PR)
  - Destroys workspace on successful deployment
  - Preserves workspace on failure (for fix agents)

## Queue Process Requirements

### Process Architecture
- **Dedicated Process**: Runs in continuous loop, monitors `deploy` queue
- **Multiple Instances**: Can run multiple processes in parallel for scalability
- **Generic Logic**: Uses shared queue handling (claiming, status updates, heartbeats)
- **Queue-Specific Logic**: 
  - PR merge workflow
  - Deployment monitoring
  - Workspace destruction on success
  - Workspace preservation on failure
  - Fix task creation for deployment failures

### Process Lifecycle
- **Modification Date Tracking**: Monitors script file modification date
- **Graceful Shutdown**: On code change, completes current task and exits
- **Restart Required**: Must be manually restarted after code updates

### Process Flow
1. Loop: Check for available tasks in `deploy` queue
2. Claim: Atomically claim a task (if available)
3. Execute: Invoke Cursor agent to merge PR and monitor deployment
4. Monitor Deployment: Watch deployment pipeline, check service health
5. Update: 
   - If deployment succeeds: Mark task complete, destroy workspace
   - If deployment fails: Preserve workspace, create fix tasks
6. Announce: Create announcement via announce queue
7. Monitor: Check script modification date
8. Repeat: Return to step 1 (or exit if code changed)

## Success Criteria
- PR is merged successfully
- Deployment completes without errors
- Services are healthy and running
- Smoke tests pass
- Status is announced
- Next step (e2e-test) is queued if successful

## Deployment Targets
- **Staging**: Test environment, lower priority
- **Production**: Live environment, higher priority, more monitoring
- **Feature environments**: Per-feature deployments if configured

## Rollback Strategy
- If deployment fails critically: Queue rollback task
- Monitor for issues post-deployment
- Create rollback tasks if needed

## Best Practices & Strategic Guidance

### Deployment Strategy: Safe, Monitored Rollouts

1. **Staged Deployment**: Deploy to staging before production
   - Test in staging environment first
   - Verify functionality before production
   - Catch issues early

2. **Health Checks**: Verify services are healthy
   - Check service health endpoints
   - Verify database connections
   - Confirm external service integrations
   - Monitor resource usage (CPU, memory)

3. **Smoke Tests**: Run basic functionality checks
   - Critical user flows
   - API endpoint availability
   - Database connectivity
   - External service connectivity

4. **Gradual Rollout**: Use canary or blue-green deployments when possible
   - Deploy to subset of instances first
   - Monitor for issues
   - Gradually increase rollout
   - Rollback quickly if issues detected

### Deployment Monitoring Best Practices

1. **Comprehensive Monitoring**: Watch all deployment stages
   - **Build Stage**: Verify build completes successfully
   - **Deploy Stage**: Monitor deployment progress
   - **Health Checks**: Verify services start correctly
   - **Service Startup**: Confirm all services are running

2. **Error Detection**: Monitor for various failure types
   - **Deployment Errors**: Infrastructure, configuration issues
   - **Service Crashes**: Application crashes, OOM errors
   - **Health Check Failures**: Services not responding
   - **Performance Degradation**: Slow response times, high latency

3. **Timeout Handling**: Set reasonable timeouts
   - Don't wait indefinitely for deployment
   - Retry transient failures
   - Escalate if consistently timing out

4. **Log Collection**: Capture deployment logs
   - Store logs for debugging
   - Include in error reports
   - Enable post-mortem analysis

### Rollback Strategy Best Practices

1. **Automatic Rollback**: Trigger rollback on critical failures
   - Service crashes
   - Health check failures
   - Performance degradation beyond threshold
   - Data corruption detected

2. **Rollback Tasks**: Create rollback tasks when needed
   - Revert code changes
   - Restore database backups if needed
   - Rollback infrastructure changes
   - Verify rollback success

3. **Post-Deployment Monitoring**: Continue monitoring after deployment
   - Watch for issues in first hours/days
   - Monitor error rates
   - Track performance metrics
   - Create rollback tasks if issues arise

### Fix Task Creation for Deployment Failures

1. **Specific Fix Tasks**: Create targeted tasks for each failure type
   - Link to specific deployment logs
   - Include error messages and stack traces
   - Reference specific services/components

2. **Priority Based on Impact**: Set priority based on failure severity
   - Production failures: Critical priority
   - Staging failures: High priority
   - Non-critical issues: Normal priority

3. **Link to Original Task**: Connect fix tasks to commit-build task
   - Enable full traceability
   - Track which changes caused failures

### Merge Strategy Best Practices

1. **Merge Strategy Selection**: Choose appropriate merge strategy
   - **Merge commit**: Preserves full history
   - **Squash merge**: Cleaner history, single commit
   - **Rebase merge**: Linear history

2. **Conflict Resolution**: Handle merge conflicts
   - Auto-resolve simple conflicts
   - Queue to `execution` for complex conflicts
   - Verify merge correctness

3. **PR Approval**: Verify PR is approved if required
   - Check approval status
   - Wait for required approvals
   - Queue to `announce` if approval needed

### Status Communication

1. **Announce Deployment Start**: Notify via `announce` queue
   - Include deployment target
   - Link to PR and related tasks
   - Provide deployment timeline

2. **Announce Deployment Status**: Update on completion
   - Success: Link to e2e-test queue
   - Failure: Link to fix tasks created
   - Include deployment duration and metrics
