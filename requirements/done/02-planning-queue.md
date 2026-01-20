# Planning Queue

## Purpose
Takes detailed requirements documents and breaks them down into bite-sized, fully-detailed tasks. Each task should include implementation approach, files to change/create, dependencies, and clear acceptance criteria.

## Queue Type
`planning`

## Input
- **Researched requirements document** (from `requirements-research` queue)
- **Optional existing plan** (for updates/revisions)

## Output
- **Task breakdown document** (markdown file)
- **Multiple execution tasks** (queued to `execution` queue)
- **Dependency graph** (task ordering and dependencies)
- **Implementation plan** (high-level approach)

## Task Structure
```json
{
  "title": "PLAN: <feature-title>",
  "description": "Break down requirements into executable tasks",
  "context": {
    "requirements_doc": "requirements/researched/<doc-id>.md",
    "feature_title": "<feature-name>",
    "related_features": []
  },
  "priority": 3,
  "output_location": "plans/<feature-id>.md"
}
```

## Workflow
1. **Agent claims task** from `planning` queue
2. **Read requirements document** - Understand full scope
3. **Break down into tasks**:
   - Identify logical work units
   - Determine task dependencies
   - Estimate complexity
   - Assign priorities
4. **Detail each task**:
   - Implementation approach
   - Files to create/modify
   - Dependencies on other tasks
   - Acceptance criteria
   - Testing requirements
5. **Create execution tasks**:
   - Queue each task to `execution` queue
   - Set proper priorities
   - Link dependencies
6. **Document plan**:
   - Create planning document
   - Include task breakdown
   - Document dependencies
   - Include timeline estimates
7. **Create execution tasks**:
   - Queue each task to `execution` queue
   - Set proper priorities
   - Link dependencies
   - Include all task details from breakdown
8. **Announce completion**: Queue to `announce` queue with breakdown summary
9. **Mark complete** - Planning done, execution tasks queued

## Task Detail Requirements
Each execution task should include:
- **Title**: Clear, descriptive task name
- **Description**: What needs to be done
- **Implementation approach**: How to do it
- **Files to change**: Specific files/paths
- **Files to create**: New files with structure
- **Dependencies**: Other tasks that must complete first
- **Acceptance criteria**: How to know it's done
- **Testing**: What tests to write/run

## Error Handling
- If requirements unclear: Queue back to `requirements-research`
- If breakdown incomplete: Create follow-up planning task
- If blocked: Queue to `announce` with blocker information

## Integration Points
- **Input**: Receives from `requirements-research` queue (Step 01)
- **Output**: Queues multiple tasks to `execution` queue (Step 03)
- **Questions**: Uses `announce` queue for clarifications
- **Blockers**: Uses `announce` queue to report issues
- **Announcements**: Announces work start, completion, and status

## Agent Script
- **Script**: `agent-planning.sh`
- **Workspace**: No workspace needed (planning only, no code changes)
- **Cursor Agent**: Invokes Cursor agent to perform task breakdown
- **Auto-Queue**: Automatically queues execution tasks on completion

## Queue Process Requirements

### Process Architecture
- **Dedicated Process**: Runs in continuous loop, monitors `planning` queue
- **Multiple Instances**: Can run multiple processes in parallel for scalability
- **Generic Logic**: Uses shared queue handling (claiming, status updates, heartbeats)
- **Queue-Specific Logic**: 
  - Task breakdown workflow execution
  - Dependency graph creation
  - Multiple execution task creation
  - No workspace management needed

### Process Lifecycle
- **Modification Date Tracking**: Monitors script file modification date
- **Graceful Shutdown**: On code change, completes current task and exits
- **Restart Required**: Must be manually restarted after code updates

### Process Flow
1. Loop: Check for available tasks in `planning` queue
2. Claim: Atomically claim a task (if available)
3. Execute: Invoke Cursor agent to perform task breakdown
4. Update: Mark task complete, create execution tasks
5. Announce: Create announcement via announce queue
6. Monitor: Check script modification date
7. Repeat: Return to step 1 (or exit if code changed)

## Success Criteria
- All requirements are broken into executable tasks
- Each task is fully detailed and actionable
- Dependencies are clearly identified
- Tasks are properly prioritized
- Execution tasks are queued and ready

## Best Practices & Strategic Guidance

### Task Breakdown Strategy: INVEST Principle
Break work into tasks that are:
- **Independent**: Can be worked on by different agents without constant locking
- **Negotiable**: Details can be refined during execution
- **Valuable**: Each task delivers value on its own
- **Estimable**: Can estimate effort and complexity
- **Small**: Ideally 15-30 minutes of work (if longer, break down further)
- **Testable**: Has clear "Definition of Done" (DoD) that can be verified

### Work Breakdown Structure (WBS) Best Practices

1. **Atomic Tasking**: Each breakdown item must be a "single-exit" task
   - One clear definition of "Done"
   - If task requires more than 30 minutes, break it down further
   - Avoid tasks with "and" (e.g., "Code UI and connect DB" → split into two tasks)

2. **Dependency Mapping**: Use Directed Acyclic Graph (DAG) approach
   - Clearly mark which tasks are blocked by others
   - Ensure RESEARCH and CLARIFY tasks are prerequisites for DESIGN
   - Prevent agents from working on stale information
   - Use `parent_task_id` or `dependencies` column in database

3. **Parallelism Identification**: Identify tasks that can run in parallel
   - Maximize efficiency of multi-agent pool
   - Test different modules simultaneously when possible
   - Design independent components concurrently

4. **Depth Limit**: Prevent infinite decomposition
   - Set maximum depth for task breakdown
   - Stop when tasks are small enough to execute in one cycle

5. **Sanity Check**: Before finalizing breakdown, verify sub-tasks satisfy original requirement
   - Run "sanity check" agent node
   - Ensure no requirements are missed
   - Verify all dependencies are captured

### Task Detail Requirements (Enhanced)
Each execution task must include:
- **Title**: Clear, descriptive, action-oriented
- **Description**: What needs to be done (not how)
- **Implementation approach**: How to do it (detailed enough for execution)
- **Files to change**: Specific files/paths with line numbers if possible
- **Files to create**: New files with structure/skeleton
- **Dependencies**: Other task IDs that must complete first
- **Acceptance criteria**: How to know it's done (testable)
- **Testing requirements**: What tests to write/run
- **Estimated effort**: Time/complexity estimate
- **Risks**: Potential issues or blockers

### Dependency Management
- **Blocking Dependencies**: Task cannot start until dependency completes
- **Soft Dependencies**: Task can start but may need dependency output later
- **Circular Dependency Detection**: Prevent circular dependencies in DAG
- **Dependency Resolution**: Automatic task unblocking when dependencies complete

### Task Prioritization Strategy
- **Priority Aging**: Increase priority of tasks sitting in queue too long
- **FIFO within Priority**: Among same priority, oldest first
- **Critical Path**: Prioritize tasks on critical path
- **Resource Constraints**: Consider agent availability and capabilities
