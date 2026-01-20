# Work Items: Overview (00)

## Database Schema Changes

### DB-001: Create queues table
- Create `queues` table to store queue type definitions
- Fields: id, name, description, priority_default, created_at, updated_at
- Add indexes for name lookup

### DB-002: Create queue_tasks table
- Create `queue_tasks` table to organize tasks by queue type
- Fields: id, queue_id, task_id, status, priority, created_at, updated_at
- Add foreign keys and indexes

### DB-003: Create queue_agents table
- Create `queue_agents` table for agent-queue assignments
- Fields: agent_name, queue_id, priority, created_at, updated_at
- Add indexes for agent and queue lookups

### DB-004: Create announcements table
- Create `announcements` table for announcement history
- Fields: id, type, agent_name, task_id, message, context (JSON), priority, created_at
- Add indexes for querying by agent, task, type, date

### DB-005: Add queue_type field to tasks table
- Add `queue_type` column to existing `tasks` table
- Update existing tasks with default queue type
- Add index on queue_type

### DB-006: Add queue_preferences field to agents table
- Add `queue_preferences` column (JSON) to existing `agents` table
- Store agent's preferred queue types and priorities

## Shared Queue Handling Library

### LIB-001: Create shared queue library script
- Create `lib/queue-handler.sh` or similar
- Implement shared functions for all queue processes
- Include error handling and logging

### LIB-002: Implement atomic task claiming
- Function to atomically claim tasks from queue
- Use SQL transactions to prevent duplicate claims
- Handle race conditions

### LIB-003: Implement status management
- Functions to update task status (queued → in_progress → completed/failed)
- Validate state transitions
- Update timestamps

### LIB-004: Implement heartbeat management
- Function to update agent heartbeat timestamps
- Check for stale agents (no heartbeat for 2x interval)
- Return stale agent tasks to queue

### LIB-005: Implement announcement creation
- Function to create standardized announcements
- Format announcements consistently
- Queue announcements to announce queue

### LIB-006: Implement modification date monitoring
- Function to check script file modification date
- Compare with last known modification date
- Trigger graceful shutdown if changed

### LIB-007: Implement graceful shutdown handler
- Function to handle graceful shutdown
- Stop claiming new tasks
- Complete current task
- Clean up resources
- Exit cleanly

## Queue Process Infrastructure

### PROC-001: Design process lifecycle management
- Document startup sequence
- Document loop structure
- Document shutdown sequence
- Document restart requirements

### PROC-002: Design concurrency model
- Document how multiple instances work together
- Document atomic operations
- Document process isolation
- Document load distribution

### PROC-003: Design error recovery
- Document error handling strategy
- Document retry logic
- Document escalation paths
- Document crash recovery

### PROC-004: Design monitoring and observability
- Document process health monitoring
- Document queue status monitoring
- Document metrics collection
- Document alerting

## Workflow Integration

### WF-001: Design automatic task routing
- Document how tasks move between queues
- Document routing rules
- Document dependency handling
- Document error propagation

### WF-002: Design workspace lifecycle management
- Document workspace creation (execution step)
- Document workspace usage (pre-commit-check, commit-build)
- Document workspace destruction (deploy step)
- Document workspace preservation on errors

### WF-003: Implement /create-work command
- Create Cursor command file
- Accept high-level requirement description
- Enqueue to requirements-research queue
- Return task ID and status

## Migration & Cleanup

### MIG-001: Audit existing queue system
- Identify all scripts using old single queue system
- Document current queue usage patterns
- Identify dependencies on old queue structure
- Create migration plan

### MIG-002: Migrate existing tasks to new queue system
- Map old task types to new queue types
- Migrate queued tasks to appropriate new queues
- Preserve task history and context
- Update task statuses appropriately

### MIG-003: Update existing scripts to use new queue system
- Update agent-queue.sh to support queue types
- Update queue-status.sh to show all queues
- Update any other scripts using old queue
- Maintain backward compatibility during transition

### MIG-004: Remove old queue system code
- Remove single queue logic from agent-queue.sh
- Remove old queue database schema (if separate)
- Clean up unused queue-related code
- Update documentation to reflect new system

### MIG-005: Update queue-status script for multi-queue system
- Display status for all queue types
- Show queue-specific statistics (queued, in_progress, completed, failed)
- Show active agents per queue type
- Show queue priorities and task distribution
- Add filtering by queue type
- Add real-time updates (watch mode)

### MIG-006: Create queue monitoring dashboard
- Visual dashboard showing all queues
- Real-time status updates
- Queue health indicators
- Agent activity per queue
- Task flow visualization
- Historical metrics
