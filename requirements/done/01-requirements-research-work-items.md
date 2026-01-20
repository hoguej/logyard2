# Work Items: Requirements Research Queue (01)

## Agent Script

### AGENT-01-001: Create agent-requirements-research.sh script
- Create dedicated script for requirements-research queue
- Implement main loop structure
- Integrate shared queue handling library
- Implement modification date monitoring

### AGENT-01-002: Implement task claiming logic
- Use shared library for atomic task claiming
- Claim from requirements-research queue only
- Handle no tasks available case
- Verify root_work_item_id is set from /create-work command
- Preserve traceability when claiming
- Update root work item status to 'researching' when task is claimed

### AGENT-01-003: Implement Cursor agent invocation
- Invoke Cursor agent to perform research
- Pass task context and requirements
- Handle Cursor agent errors

### AGENT-01-004: Implement research workflow
- Analyze requirement
- Search codebase for similar features
- Perform web research on best practices
- Review existing documentation
- Check related code patterns

### AGENT-01-005: Implement requirements document creation
- Create detailed requirements document (markdown)
- Include background context
- Document assumptions
- List dependencies
- Identify risks
- Save to requirements/researched/ directory

### AGENT-01-006: Implement clarifying questions handling
- Generate clarifying questions if needed
- Queue questions to announce queue
- Wait for answers or proceed with assumptions
- Update task context with answers

### AGENT-01-007: Implement automatic queuing to planning
- After research complete, automatically queue to planning queue
- Link researched requirements document to planning task
- Pass all research findings in task context
- Set parent_task_id to current research task
- Preserve root_work_item_id from research task
- Update work_item_chain with research task ID

### AGENT-01-008: Implement announcement creation
- Announce work start via announce queue
- Announce completion with research summary
- Include links to requirements document
- Include next step (planning task ID)

### AGENT-01-009: Implement error handling
- Handle incomplete research (queue follow-up task)
- Handle unclear requirements (queue clarifying questions)
- Handle blockers (queue to announce)
- Handle Cursor agent failures

## Research Best Practices Implementation

### RESEARCH-01-001: Implement multi-stage synthesis strategy
- Implement Fetch-Decide-Verify pattern
- Break research into smaller, specific questions
- Filter results before deep processing

### RESEARCH-01-002: Implement source cross-referencing
- Require multiple source citations
- Verify findings through secondary search
- Assign confidence scores to sources

### RESEARCH-01-003: Implement contextual RAG
- Search local repository alongside web
- Use grep or vector embeddings for codebase analysis
- Ground research in existing project context

### RESEARCH-01-004: Implement reflection loop
- Evaluate if information is sufficient
- Identify gaps requiring new search queries
- Compare findings against original goal

### RESEARCH-01-005: Implement source citation
- Link findings back to specific files or URLs
- Prevent hallucinated requirements
- Enable verification and traceability
