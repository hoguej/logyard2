# Work Items: Deploy Queue (06)

## Agent Script

### AGENT-06-001: Create agent-deploy.sh script
- Create dedicated script for deploy queue
- Implement main loop structure
- Integrate shared queue handling library
- Implement modification date monitoring

### AGENT-06-002: Implement task claiming logic
- Use shared library for atomic task claiming
- Claim from deploy queue only
- Handle no tasks available case

### AGENT-06-003: Implement Cursor agent invocation
- Invoke Cursor agent to merge PR and monitor deployment
- Pass PR details and deployment target
- Handle Cursor agent errors
- Note: Does NOT use workspace (just merges PR)

### AGENT-06-004: Implement PR status checking
- Verify PR is approved (if required)
- Check for merge conflicts
- Ensure all checks pass
- Wait for approvals if needed

### AGENT-06-005: Implement PR merge workflow
- Merge PR to main/master branch
- Use appropriate merge strategy (merge, rebase, squash)
- Handle merge conflicts
- Verify merge success

### AGENT-06-006: Implement deployment monitoring
- Watch deployment pipeline
- Monitor deployment logs
- Check deployment status
- Verify services are healthy
- Monitor resource usage (CPU, memory)

### AGENT-06-007: Implement smoke tests
- Run basic functionality checks
- Check service health endpoints
- Verify API endpoint availability
- Check database connectivity
- Verify external service integrations

### AGENT-06-008: Implement deployment result handling
- If deployment succeeds:
  - Destroy workspace (cleanup)
  - Optionally queue to e2e-test queue (parallel processing)
- If deployment fails:
  - Preserve workspace (for fix agents)
  - Create fix tasks in execution queue

### AGENT-06-009: Implement workspace destruction
- Read workspace path from task context
- Verify workspace exists
- Destroy workspace directory
- Handle destruction errors
- Log destruction

### AGENT-06-010: Implement announcement creation
- Announce deployment start via announce queue
- Include deployment target and PR info
- Announce deployment status on completion
- Include deployment duration and metrics

### AGENT-06-011: Implement error handling
- Handle PR not approved (queue to announce)
- Handle merge conflicts (queue conflict resolution)
- Handle merge failures (queue to announce)
- Handle deployment failures (create fix tasks, preserve workspace)
- Handle deployment timeouts (queue to announce)
- Handle unhealthy services (create fix tasks)

## Deploy Best Practices Implementation

### DEPLOY-06-001: Implement staged deployment
- Deploy to staging before production
- Test in staging environment first
- Verify functionality before production
- Catch issues early

### DEPLOY-06-002: Implement health checks
- Check service health endpoints
- Verify database connections
- Confirm external service integrations
- Monitor resource usage

### DEPLOY-06-003: Implement comprehensive monitoring
- Watch all deployment stages (build, deploy, health checks, service startup)
- Monitor for deployment errors, service crashes, health check failures
- Monitor performance degradation
- Set reasonable timeouts

### DEPLOY-06-004: Implement rollback strategy
- Trigger rollback on critical failures
- Create rollback tasks when needed
- Monitor for issues post-deployment
- Create rollback tasks if issues arise

### DEPLOY-06-005: Implement fix task creation for deployment failures
- Create targeted tasks for each failure type
- Link to specific deployment logs
- Include error messages and stack traces
- Reference specific services/components

### DEPLOY-06-006: Implement merge strategy selection
- Choose appropriate merge strategy
- Handle merge conflicts
- Verify PR approval if required
- Verify merge correctness

### DEPLOY-06-007: Implement log collection
- Capture deployment logs
- Store logs for debugging
- Include in error reports
- Enable post-mortem analysis
