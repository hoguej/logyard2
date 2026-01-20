# Announce Queue

## Purpose
Central communication channel where agents announce their activities, status updates, completions, errors, and questions. This is the primary way agents communicate with humans and other agents.

## Queue Type
`announce`

## Input
- **Announcement type** (work-taken, work-completed, error, question, status)
- **Message content** (what to announce)
- **Context** (related task, agent, workspace, etc.)
- **Priority** (urgency level)

## Output
- **Announcement** (displayed to humans, logged, stored)
- **Response handling** (if questions, wait for answers)
- **Action items** (if errors, may queue fix tasks)

## Task Structure
```json
{
  "title": "ANNOUNCE: <type> - <summary>",
  "description": "<detailed message>",
  "context": {
    "type": "work-taken|work-completed|error|question|status",
    "agent_name": "<agent-name>",
    "task_id": <task-id>,
    "workspace": "<workspace-path>",
    "message": "<announcement-message>",
    "requires_response": true|false,
    "related_urls": ["<url1>", "<url2>"]
  },
  "priority": 3
}
```

## Announcement Types

### 1. Work Taken
- **When**: Agent claims a task
- **Content**: 
  - Agent name
  - Task title/description
  - Expected completion time
  - Workspace location
- **Priority**: Low (informational)

### 2. Work Completed
- **When**: Agent completes a task
- **Content**:
  - Agent name
  - Task title/description
  - What was accomplished
  - Outputs/deliverables
  - Next steps queued
  - Links to PRs, documents, etc.
- **Priority**: Medium (important update)

### 3. Error
- **When**: Agent encounters an error
- **Content**:
  - Agent name
  - Task that failed
  - Error message/details
  - Stack trace/logs
  - What was attempted
  - Suggested fix (if known)
  - Fix tasks queued (if applicable)
- **Priority**: High (needs attention)

### 4. Question
- **When**: Agent needs clarification
- **Content**:
  - Agent name
  - Task context
  - Specific question
  - Options/choices (if applicable)
  - Blocking status
- **Priority**: High (blocks work)
- **Response handling**: Wait for human response

### 5. Status
- **When**: Agent provides progress update
- **Content**:
  - Agent name
  - Current task
  - Progress percentage
  - Current activity
  - Estimated time remaining
- **Priority**: Low (informational)

## Workflow
1. **Agent creates announcement** - Queues to `announce` queue
2. **Announcement processed**:
   - Displayed to humans (dashboard, notifications)
   - Logged for history
   - Stored in database
3. **Response handling** (if question):
   - Wait for human response
   - Update original task with answer
   - Agent continues work
4. **Action items** (if error):
   - May queue fix tasks
   - May escalate to humans
   - May trigger retry logic
5. **Mark complete** - Announcement delivered

## Display Methods
- **Dashboard**: Real-time announcement feed
- **Notifications**: Push notifications for high-priority items
- **Logs**: Persistent log of all announcements
- **Email/Slack**: Integration with communication tools (optional)

## Response Handling
- Questions wait for human response
- Response linked back to original task
- Agent notified when response received
- Work continues with new information

## Error Escalation
- Critical errors: Immediate human notification
- Repeated errors: Escalate to humans
- Blocking errors: High priority, urgent attention
- Non-blocking errors: Logged, fix tasks queued

## Integration Points
- **Input**: Receives from all other queues
- **Output**: 
  - Displays to humans
  - May queue fix tasks (for errors)
  - Updates task context (for questions)
- **All queues**: Use this for communication

## Success Criteria
- Announcements are delivered promptly
- Humans are notified appropriately
- Questions receive responses
- Errors are addressed
- Status is tracked and visible

## Announcement Format
```
[ANNOUNCE: <type>] <agent-name>
Task: <task-title>
Message: <announcement-content>
Context: <additional-context>
Links: <related-urls>
```

## Priority Levels
- **Low**: Informational (work-taken, status)
- **Medium**: Important (work-completed)
- **High**: Urgent (error, question)

## History & Logging
- All announcements stored permanently
- Searchable by agent, task, type, date
- Used for analytics and debugging
- Reference for similar issues

## Best Practices & Strategic Guidance

### Communication Strategy: Event-Driven Observability

1. **Structured Event Logging**: Use standardized event types
   - **State Transitions**: `CLAIMED`, `IN_PROGRESS`, `SUCCESS`, `FAILED`, `RETRY`
   - **Clear Status Indicators**: Visual status (empty circle, filled, check, square)
   - **Event-Driven Feedback**: Concise summaries when work completes

2. **Heartbeat Mechanism**: Monitor agent health
   - Update `last_seen` timestamp every 15-30 seconds
   - Identify "dead" agents (no heartbeat for 2x interval)
   - Automatically return work to queue for dead agents
   - Track agent PID and current task ID

3. **Batched Processing**: Reduce database overhead
   - Batch announcements when multiple events occur quickly
   - Use transactions for multiple announcements
   - Consolidate related updates into single announcement

### Announcement Best Practices

1. **Contextual Information**: Include all relevant context
   - Agent name and task ID
   - Workspace path and branch
   - Related URLs (PRs, documents, logs)
   - Error details (for errors)
   - Success metrics (for completions)

2. **Structured Format**: Use consistent format
   - Standardized announcement template
   - Machine-readable structure (JSON)
   - Human-readable summary
   - Searchable metadata

3. **Priority-Based Delivery**: Route based on priority
   - **High Priority**: Immediate notification (errors, questions)
   - **Medium Priority**: Important updates (completions)
   - **Low Priority**: Informational (status, work-taken)

### Question Handling Best Practices

1. **Structured Questions**: Present options, not open-ended questions
   - Multiple choice options (A, B, C)
   - Yes/No questions when possible
   - Specific questions with clear answers
   - Minimize back-and-forth

2. **State Persistence**: Save agent state before asking
   - Allow agent to pause and resume
   - Store current progress
   - Resume exactly where left off after response

3. **Uncertainty Thresholds**: Trigger clarification when confidence low
   - Set confidence threshold (e.g., 0.7)
   - Automatically queue clarification if below threshold
   - Prevent proceeding with uncertain assumptions

### Error Announcement Best Practices

1. **Comprehensive Error Context**: Include all error details
   - Error message and stack trace
   - Last 50-100 lines of logs
   - Command that failed
   - What was attempted
   - Suggested fix (if known)

2. **Error Categorization**: Categorize errors by type
   - **Transient**: Retryable (network, timeouts)
   - **Logic**: Require code changes
   - **Infrastructure**: Environment issues
   - **Data**: Data-related issues

3. **Fix Task Linking**: Link to fix tasks when created
   - Enable traceability
   - Track error resolution
   - Monitor fix progress

### Status Update Best Practices

1. **Progress Tracking**: Provide meaningful progress updates
   - Progress percentage
   - Current activity description
   - Estimated time remaining
   - Milestones reached

2. **Success Metrics**: Include metrics in completion announcements
   - Task duration
   - Token usage (if applicable)
   - Files changed
   - Tests written/run
   - Lines of code

3. **TL;DR Summaries**: Provide concise summaries
   - What was done (summary)
   - What failed or was skipped (and why)
   - Location of final output (results)
   - Next steps queued

### Database Best Practices

1. **Event-Driven Logging**: Use dedicated announcements table
   - Avoid file-based logging (lock contention)
   - Enable concurrent access
   - Support querying and filtering
   - Enable analytics

2. **Audit Trail**: Maintain complete history
   - All state changes logged
   - Searchable by agent, task, type, date
   - Used for post-mortem analysis
   - Reference for similar issues

3. **Performance Optimization**: Optimize for high volume
   - Index on common query fields
   - Batch inserts when possible
   - Archive old announcements
   - Use efficient query patterns
