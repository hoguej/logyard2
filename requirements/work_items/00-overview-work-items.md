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

### DB-007: Add traceability fields to tasks table
- Add `root_work_item_id` column to track original human input
- Add `parent_task_id` column to link to task that spawned this one
- Add `work_item_chain` column (JSON array) to track full chain from root
- Add indexes on root_work_item_id and parent_task_id for fast lookups

## Shared Queue Handling Library

### LIB-001: Create shared queue library script
- Create `lib/queue-handler.sh` or similar
- Implement shared functions for all queue processes
- Include error handling and logging

### LIB-002: Implement atomic task claiming
- Function to atomically claim tasks from queue
- Use SQL transactions to prevent duplicate claims
- Handle race conditions
- Preserve traceability fields (root_work_item_id, parent_task_id, work_item_chain) when claiming

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
- Create root work item record with unique ID
- Enqueue to requirements-research queue with root_work_item_id
- Return task ID, root work item ID, and status

### WF-004: Implement traceability linking
- Function to create task with traceability links
- Link to parent task (if spawned from another task)
- Link to root work item (original human input)
- Update work_item_chain array
- Ensure all tasks can trace back to root

### WF-005: Implement root work item tracking
- Create root_work_items table to track original human inputs
- Fields: id, user_input, title, description, created_at, status, started_at, completed_at, failed_at, cancelled_at
- Status values: 'pending', 'researching', 'planning', 'executing', 'checking', 'building', 'deploying', 'testing', 'completed', 'failed', 'cancelled'
- Link all workflow tasks to root work item
- Enable querying all tasks for a given root work item
- Store original user request verbatim for reference

### WF-007: Implement root work item status management
- Function to update root work item status based on current workflow stage
- Automatically update status when tasks move between queues:
  - 'pending' → 'researching' (when requirements-research task claimed)
  - 'researching' → 'planning' (when planning task claimed)
  - 'planning' → 'executing' (when first execution task claimed)
  - 'executing' → 'checking' (when pre-commit-check task claimed)
  - 'checking' → 'building' (when commit-build task claimed)
  - 'building' → 'deploying' (when deploy task claimed)
  - 'deploying' → 'testing' (when e2e-test task claimed, optional)
  - Any stage → 'completed' (when deploy succeeds)
  - Any stage → 'failed' (when critical task fails)
- Update started_at when first task is claimed
- Update completed_at when status becomes 'completed'
- Update failed_at when status becomes 'failed'

### WF-008: Implement root work item status query functions
- Function to get current status of a root work item
- Function to get status history/timeline for a root work item
- Function to list all root work items with their current status
- Function to query root work items by status
- Function to get progress percentage (based on workflow stage)
- Function to get estimated completion time

### WF-006: Implement traceability query functions
- Function to get all tasks for a root work item
- Function to get full task chain (root → current task)
- Function to get all child tasks for a parent task
- Function to get task lineage (all ancestors)
- Enable visualization of work item relationships

### WF-009: Integrate status updates into workflow
- Update root work item status in /create-work command (set to 'pending')
- Update root work item status when requirements-research agent claims task (set to 'researching')
- Update root work item status when planning agent claims task (set to 'planning')
- Update root work item status when execution agent claims first task (set to 'executing')
- Update root work item status when pre-commit-check agent claims task (set to 'checking')
- Update root work item status when commit-build agent claims task (set to 'building')
- Update root work item status when deploy agent claims task (set to 'deploying')
- Update root work item status when deploy succeeds (set to 'completed')
- Update root work item status when critical task fails (set to 'failed')
- Include status in announcements

## Milestones

### MILESTONE-001: Work item creation feature complete
- **After**: WF-003 (Implement /create-work command)
- **What's accomplished**: User can create work items via /create-work command and see them tracked in the system
- **How to verify**:
  - Run `/create-work "Feature Title" "Description"` command
  - Verify root work item created in `root_work_items` table
  - Check root work item has status 'pending'
  - Verify requirements-research task created and linked to root work item
  - Run `queue-status` and verify work item appears
  - Query database to see traceability links

### MILESTONE-002: Requirements research feature complete
- **After**: AGENT-01-009 (Requirements research agent complete)
- **What's accomplished**: Requirements research agent can claim work, perform research, and create detailed requirements documents
- **How to verify**:
  - Start requirements-research agent process
  - Verify agent claims research task from queue
  - Check root work item status updated to 'researching'
  - Verify research document created in `requirements/researched/` directory
  - Check planning task automatically queued with traceability links
  - Verify announcement created for work completion
  - Check root work item status updated appropriately

### MILESTONE-003: Task planning feature complete
- **After**: AGENT-02-011 (Planning agent complete)
- **What's accomplished**: Planning agent can break down requirements into detailed, executable tasks
- **How to verify**:
  - Start planning agent process
  - Verify agent claims planning task from queue
  - Check root work item status updated to 'planning'
  - Verify planning document created in `plans/` directory
  - Check execution tasks created in execution queue
  - Verify each execution task has proper traceability (parent_task_id, root_work_item_id)
  - Check dependency graph created correctly
  - Verify announcement created with task breakdown summary

### MILESTONE-004: Code execution feature complete
- **After**: AGENT-03-010 (Execution agent complete)
- **What's accomplished**: Execution agent can claim tasks, create workspaces, and write code
- **How to verify**:
  - Start execution agent process
  - Verify agent claims execution task from queue
  - Check root work item status updated to 'executing'
  - Verify workspace created in `workspaces/` directory
  - Check feature branch created in workspace
  - Verify code changes made according to plan
  - Check pre-commit-check task automatically queued
  - Verify workspace path stored in task context
  - Check announcement created with execution summary

### MILESTONE-005: Commit and PR feature complete
- **After**: AGENT-05-011 (Commit-build agent complete)
- **What's accomplished**: Commit-build agent can commit code, create PRs, and monitor builds
- **How to verify**:
  - Start commit-build agent process
  - Verify agent claims commit-build task from queue
  - Check root work item status updated to 'building'
  - Verify code committed with proper commit message
  - Check PR created on GitHub with comprehensive description
  - Verify build monitoring works (watches CI/CD pipeline)
  - Check deploy task queued if build succeeds
  - Verify announcement created with PR URL and build status

### MILESTONE-006: Full workflow feature complete
- **After**: AGENT-06-011 (Deploy agent complete)
- **What's accomplished**: Complete end-to-end workflow from user input to deployment
- **How to verify**:
  - Run full workflow from `/create-work` to deployment
  - Verify each stage completes successfully:
    - Requirements research → planning → execution → pre-commit-check → commit-build → deploy
  - Check root work item status progresses: pending → researching → planning → executing → checking → building → deploying → completed
  - Verify workspace destroyed on successful deployment
  - Check all tasks have proper traceability back to root work item
  - Verify queue-status shows complete workflow for the work item
  - Check announcements created at each stage
  - Verify final status shows 'completed' with completion timestamp

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
- Display active root work items (human inputs being worked on)
- Show root work item status for each active work item
- Show which queue each root work item is currently in
- Display root work item title/description
- Show progress through workflow stages for each root work item
- Group tasks by root work item for better visibility
- Show count of tasks per root work item

### MIG-006: Create queue monitoring dashboard
- Visual dashboard showing all queues
- Real-time status updates
- Queue health indicators
- Agent activity per queue
- Task flow visualization
- Historical metrics
