# Multi-Queue System Overview

## Purpose
Replace the single queue system with a specialized queue system where each type of work has its own dedicated queue. This allows for better task organization, priority management, and workflow automation.

## Queue Types

1. **requirements-research** - Transforms high-level requirements into detailed requirement documents
2. **planning** - Breaks down requirements into fully-detailed, executable tasks
3. **execution** - Executes planned tasks (actual coding work)
4. **pre-commit-check** - Validates code quality before committing
5. **commit-build** - Commits code, creates PR, monitors build
6. **deploy** - Merges PRs, monitors deployment
7. **e2e-test** - Runs end-to-end tests, handles failures
8. **announce** - Communication channel for agents to announce activities

## Workflow Flow

```
Human Input (/create-work command)
    ↓
[Step 01: requirements-research] → Detailed Requirements
    ↓ (auto-queues to planning)
[Step 02: planning] → Task Breakdown
    ↓ (creates execution tasks)
[Step 03: execution] → Code Changes (CREATES WORKSPACE)
    ↓ (auto-queues to pre-commit-check)
[Step 04: pre-commit-check] → Quality Validation (USES WORKSPACE)
    ↓ (auto-queues to commit-build)
[Step 05: commit-build] → PR Created, Build Monitored (USES WORKSPACE)
    ↓ (auto-queues to deploy)
[Step 06: deploy] → Code Merged, Deployment Monitored (DESTROYS WORKSPACE on success)
    ↓
Feature Complete

[e2e-test] → Can run in parallel at any stage, or via dedicated queue
[announce] → All agents announce their work throughout the process
```

## Agent Scripts

Each queue type requires its own agent script:
- `agent-requirements-research.sh` - Handles requirements research
- `agent-planning.sh` - Handles task breakdown
- `agent-execution.sh` - Handles code implementation (creates workspace)
- `agent-pre-commit-check.sh` - Handles quality validation (uses workspace)
- `agent-commit-build.sh` - Handles commit, PR, build (uses workspace)
- `agent-deploy.sh` - Handles deployment (destroys workspace on success)
- `agent-e2e-test.sh` - Handles E2E testing (optional, parallel)

## Queue Characteristics

### Queue Priority Levels
- **1 (Low)**: Background work, non-urgent
- **2 (Normal)**: Standard work, normal priority
- **3 (Medium)**: Important work, higher priority
- **4 (High)**: Urgent work, needs attention
- **5 (Critical)**: Blocking work, immediate attention

### Task States
- **queued**: Waiting to be claimed
- **in_progress**: Currently being worked on
- **completed**: Successfully finished
- **failed**: Encountered an error
- **cancelled**: Manually cancelled
- **blocked**: Waiting on dependency or response

### Agent Assignment
- Agents can specialize in queue types
- Agents can work across multiple queues
- Queue-specific agents for specialized work
- General agents for flexible work

## Database Schema Changes

### New Tables
- **queues**: Queue type definitions
- **queue_tasks**: Tasks organized by queue type
- **queue_agents**: Agent-queue assignments
- **announcements**: Announcement history

### Modified Tables
- **tasks**: Add `queue_type` field
- **agents**: Add `queue_preferences` field

## Integration Points

### Between Queues
- Automatic task queuing between queues
- Dependency tracking across queues
- Status propagation
- Error handling and escalation

### With External Systems
- GitHub (PRs, commits, builds)
- CI/CD pipelines (build status, deployment)
- Test infrastructure (E2E tests)
- Communication tools (Slack, email)

## Benefits

1. **Specialization**: Agents can specialize in specific queue types
2. **Priority Management**: Better control over task priorities per queue
3. **Workflow Automation**: Automatic progression through queues
4. **Error Handling**: Better error isolation and handling
5. **Visibility**: Clear view of work at each stage
6. **Scalability**: Easy to add new queue types
7. **Communication**: Centralized announcement system

## Workspace Lifecycle

1. **Creation**: Workspace created in Step 03 (execution) when agent claims task
2. **Usage**: Steps 04-05 (pre-commit-check, commit-build) use the existing workspace
3. **Destruction**: Step 06 (deploy) destroys workspace on successful deployment
4. **Error Handling**: If deploy fails, workspace is preserved for fix agents
5. **Isolation**: Each work item gets its own workspace (no reuse across work items)

## Agent Script Requirements

Each queue type needs its own dedicated agent script that:
- Claims tasks from its specific queue
- Executes work using Cursor agent
- Automatically queues next step in workflow
- Announces work via announce queue
- Handles workspace lifecycle (create/use/destroy) as appropriate

## Queue Process Architecture

### Dedicated Process Per Queue Type

Each queue type has a dedicated process/script that:
- **Runs in a continuous loop** - Monitors queue for new work
- **Picks up new work** - Claims tasks from its specific queue
- **Handles queue operations** - Updates task status, manages queue state
- **Fires off Cursor agent** - Invokes Cursor agent to perform the actual work
- **Updates queue when done** - Marks tasks complete, queues next steps
- **Supports multiple instances** - Multiple processes can run in parallel for scalability

### Shared vs. Queue-Specific Logic

- **Generic Queue Handling Logic** - Shared across all queue processes:
  - Task claiming (atomic operations)
  - Status updates
  - Heartbeat management
  - Error handling
  - Announcement creation
  - Database operations
  
- **Queue-Specific Logic** - Unique to each queue type:
  - Workspace lifecycle (create/use/destroy)
  - Workflow progression (what to queue next)
  - Validation and checks
  - Queue-specific error handling
  - Queue-specific announcements

### Process Lifecycle Management

Each queue process script must:
- **Track modification date** - Record when script file was last modified
- **Monitor for changes** - Check script modification date periodically
- **Graceful shutdown** - If modification date changes:
  - Stop claiming new tasks
  - Complete current task (if any)
  - Exit gracefully
  - Log shutdown reason
- **Restart required** - Process must be manually restarted after code updates

### Implementation Requirements

1. **Script Structure**:
   - Main loop that checks for work
   - Task claiming logic
   - Cursor agent invocation
   - Queue update logic
   - Modification date monitoring

2. **Concurrency**:
   - Multiple instances can run simultaneously
   - Atomic task claiming prevents duplicate work
   - Process isolation ensures no conflicts

3. **Reliability**:
   - Graceful shutdown on code changes
   - Complete current work before exiting
   - Log all state changes
   - Handle crashes gracefully

4. **Monitoring**:
   - Track process uptime
   - Monitor modification date
   - Log when process restarts
   - Report process health

## Implementation Considerations

1. **Queue Management**: How to create, configure, and manage queues
2. **Task Routing**: How tasks automatically move between queues
3. **Agent Assignment**: How agents claim from specific queues
4. **Dependency Tracking**: How to handle cross-queue dependencies
5. **Error Recovery**: How to handle failures and retries
6. **Monitoring**: How to monitor queue health and status
7. **Configuration**: How to configure queue behavior
8. **Workspace Management**: How to create, use, and destroy workspaces
9. **Automatic Progression**: How tasks automatically queue to next step

## Queue Process Implementation Details

### Shared Queue Handling Library

A shared library/script should provide:
- **Atomic Task Claiming**: SQL transactions for safe task claiming
- **Status Management**: Update task status (queued → in_progress → completed/failed)
- **Heartbeat Management**: Update agent heartbeat timestamps
- **Error Handling**: Standard error handling and retry logic
- **Announcement Creation**: Standard announcement format and queuing
- **Database Operations**: Common database queries and updates
- **Modification Date Monitoring**: Check script modification date, trigger graceful shutdown

### Queue-Specific Scripts

Each queue type has its own script that:
- Imports/uses shared queue handling library
- Implements queue-specific workflow logic
- Handles queue-specific workspace lifecycle
- Manages queue-specific error handling
- Implements queue-specific announcements

### Process Management

- **Startup**: Process starts, begins monitoring queue
- **Loop**: Continuously checks for work, claims tasks, executes, updates
- **Shutdown Detection**: Periodically checks script modification date
- **Graceful Shutdown**: Completes current task, exits cleanly
- **Restart**: Manual restart required after code updates

### Concurrency and Scaling

- **Multiple Instances**: Can run multiple processes per queue type
- **Atomic Operations**: Database transactions prevent duplicate work
- **Process Isolation**: Each process works independently
- **Load Distribution**: Tasks distributed across available processes

## Next Steps

1. Review and refine requirements for each queue
2. Design database schema changes
3. Design shared queue handling library
4. Design queue-specific scripts
5. Design process lifecycle management
6. Design modification date monitoring
7. Design graceful shutdown mechanism
8. Design task routing logic
9. Design agent assignment logic
10. Design error handling and recovery
11. Design monitoring and observability
