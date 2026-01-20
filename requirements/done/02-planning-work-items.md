# Work Items: Planning Queue (02)

## Agent Script

### AGENT-02-001: Create agent-planning.sh script
- Create dedicated script for planning queue
- Implement main loop structure
- Integrate shared queue handling library
- Implement modification date monitoring

### AGENT-02-002: Implement task claiming logic
- Use shared library for atomic task claiming
- Claim from planning queue only
- Handle no tasks available case
- Update root work item status to 'planning' when task is claimed

### AGENT-02-003: Implement Cursor agent invocation
- Invoke Cursor agent to perform task breakdown
- Pass requirements document and context
- Handle Cursor agent errors

### AGENT-02-004: Implement requirements document reading
- Read researched requirements document
- Parse requirements and context
- Understand full scope

### AGENT-02-005: Implement task breakdown logic
- Identify logical work units
- Determine task dependencies
- Estimate complexity
- Assign priorities
- Apply INVEST principle

### AGENT-02-006: Implement task detailing
- For each task, create detailed specification:
  - Implementation approach
  - Files to create/modify
  - Dependencies on other tasks
  - Acceptance criteria
  - Testing requirements
  - Estimated effort
  - Risks

### AGENT-02-007: Implement dependency graph creation
- Create Directed Acyclic Graph (DAG) of tasks
- Detect circular dependencies
- Identify parallelizable tasks
- Set blocking vs soft dependencies

### AGENT-02-008: Implement execution task creation
- Queue each task to execution queue
- Set proper priorities
- Link dependencies
- Include all task details in context
- Set parent_task_id to current planning task
- Preserve root_work_item_id from planning task
- Update work_item_chain with planning task ID

### AGENT-02-009: Implement planning document creation
- Create planning document (markdown)
- Include task breakdown
- Document dependencies
- Include timeline estimates
- Save to plans/ directory

### AGENT-02-010: Implement announcement creation
- Announce work start via announce queue
- Announce completion with breakdown summary
- Include number of tasks created
- Include dependency graph summary

### AGENT-02-011: Implement error handling
- Handle unclear requirements (queue back to requirements-research)
- Handle incomplete breakdown (create follow-up planning task)
- Handle blockers (queue to announce)
- Handle Cursor agent failures

## Planning Best Practices Implementation

### PLAN-02-001: Implement INVEST principle validation
- Validate tasks are Independent, Negotiable, Valuable, Estimable, Small, Testable
- Break down tasks that don't meet criteria
- Ensure tasks are 15-30 minutes of work

### PLAN-02-002: Implement atomic tasking
- Ensure each task is single-exit
- Split tasks containing "and"
- Break down tasks longer than 30 minutes

### PLAN-02-003: Implement dependency mapping
- Use DAG approach for dependencies
- Mark blocking vs soft dependencies
- Prevent circular dependencies
- Use parent_task_id or dependencies column

### PLAN-02-004: Implement parallelism identification
- Identify tasks that can run in parallel
- Maximize multi-agent pool efficiency
- Mark parallelizable tasks

### PLAN-02-005: Implement depth limit
- Set maximum depth for task breakdown
- Prevent infinite decomposition
- Stop when tasks are small enough

### PLAN-02-006: Implement sanity check
- Verify sub-tasks satisfy original requirement
- Ensure no requirements are missed
- Verify all dependencies are captured

### PLAN-02-007: Implement priority aging
- Increase priority of tasks sitting in queue too long
- Implement FIFO within priority
- Prioritize tasks on critical path
