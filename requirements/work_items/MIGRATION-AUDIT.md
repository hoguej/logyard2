# Migration Audit: Old Queue System to Multi-Queue System

## MIG-001: Audit Existing Queue System

### Old System Components

1. **`scripts/agent-queue.sh`**
   - Single queue management script
   - Commands: `register`, `claim`, `release`, `complete`, `heartbeat`, `add`, `status`, `list`, `whoami`
   - Uses `tasks` and `agents` tables directly
   - No queue type separation
   - No traceability to root work items

2. **`scripts/new-agent.sh`**
   - Creates agent workspace
   - Uses `agent-queue.sh` to register and claim tasks
   - Single workflow for all task types
   - No queue-specific logic

3. **`scripts/breakdown-feature.sh`**
   - Creates 12 predefined workflow tasks
   - Uses old `tasks` table directly
   - No queue type assignment
   - No traceability

4. **`scripts/commit-and-pr.sh`**
   - Uses `agent-queue.sh complete` to mark tasks done
   - Works with old system

### Database Schema (Old System)

- `tasks` table: Single table for all tasks
- `agents` table: Agent registration and status
- No `queues` table
- No `queue_tasks` table
- No `root_work_items` table
- No traceability fields (`parent_task_id`, `root_work_item_id`)

### New System Components

1. **Multi-queue system**
   - 8 dedicated queues: requirements-research, planning, execution, pre-commit-check, commit-build, deploy, e2e-test, announce
   - `queues` table for queue definitions
   - `queue_tasks` table linking tasks to queues
   - `root_work_items` table for tracking human requests

2. **Dedicated agent scripts**
   - `agent-requirements-research.sh`
   - `agent-planning.sh`
   - `agent-execution.sh`
   - `agent-pre-commit-check.sh`
   - `agent-commit-build.sh`
   - `agent-deploy.sh`
   - `agent-e2e-test.sh`

3. **Shared libraries**
   - `lib/queue-handler.sh`: Core queue operations
   - `lib/workflow-functions.sh`: Workflow-specific functions

4. **Entry point**
   - `scripts/create-work.sh`: Creates root work items and enqueues to requirements-research

## MIG-002: Migration Strategy

### Task Migration

Any existing tasks in the old `tasks` table should be:
1. Analyzed to determine appropriate queue type
2. Migrated to `queue_tasks` table with appropriate `queue_id`
3. Linked to a root work item if possible (or create a generic one)
4. Preserve priority and status

### Script Updates

- `new-agent.sh`: Keep as legacy, but document it's superseded by dedicated agent scripts
- `breakdown-feature.sh`: Keep as legacy, but document it's superseded by `/create-work`
- `agent-queue.sh`: Mark as deprecated, but keep for backward compatibility
- `commit-and-pr.sh`: Already updated to work with new system

## MIG-003: Script Status

### Updated Scripts
- ✅ `scripts/create-work.sh`: New entry point
- ✅ `scripts/queue-status.sh`: Updated for multi-queue system
- ✅ `scripts/commit-and-pr.sh`: Works with new system
- ✅ All dedicated agent scripts: Use new queue system

### Legacy Scripts (Still Functional)
- ⚠️ `scripts/new-agent.sh`: Old single-queue workflow (superseded by dedicated agents)
- ⚠️ `scripts/breakdown-feature.sh`: Old task creation (superseded by `/create-work`)
- ⚠️ `scripts/agent-queue.sh`: Old queue management (superseded by `lib/queue-handler.sh`)

## MIG-004: Old Code Removal

### Recommendation: Keep for Now
- Old scripts are still functional and may be used by existing workflows
- Mark as deprecated in documentation
- Remove in future version after full migration

### Deprecation Notice
Add deprecation warnings to:
- `scripts/new-agent.sh`
- `scripts/breakdown-feature.sh`
- `scripts/agent-queue.sh`

## MIG-005: Queue Status Update

✅ **Completed**: `queue-status.sh` updated to show:
- Multi-queue system status (all 8 queues)
- Root work item status (active human requests)
- Backward compatible with old system

## MIG-006: Queue Monitoring Dashboard

**Status**: Optional enhancement
- Could create a web-based dashboard
- Could add more detailed metrics
- Not critical for core functionality
