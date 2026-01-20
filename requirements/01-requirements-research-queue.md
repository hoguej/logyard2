# Requirements Research Queue

## Purpose
Takes high-level requirements provided by humans and transforms them into fully-featured, detailed requirement documents with all background information filled in. This includes research on typical features, web research, codebase analysis, and best practices.

## Queue Type
`requirements-research`

## Input
- **High-level requirement description** (text from human)
- **Optional context** (related features, constraints, user stories, etc.)
- **Optional priority** (1-5, default: 3)

## Output
- **Detailed requirements document** (markdown file)
- **Research findings** (background information, similar features, best practices)
- **Clarifying questions** (if needed, queued back to human)
- **Next step**: Task automatically queued to `planning` queue

## Task Structure
```json
{
  "title": "RESEARCH: <requirement-title>",
  "description": "<high-level requirement description>",
  "context": {
    "requirement_text": "<original requirement>",
    "related_features": [],
    "constraints": [],
    "user_stories": []
  },
  "priority": 3,
  "output_location": "requirements/researched/<requirement-id>.md"
}
```

## Workflow
1. **Agent claims task** from `requirements-research` queue
2. **Analyze requirement** - Understand what's being asked
3. **Research phase**:
   - Search codebase for similar features
   - Web research on best practices
   - Review existing documentation
   - Check related code patterns
4. **Document findings**:
   - Create detailed requirements document
   - Include background context
   - Document assumptions
   - List dependencies
   - Identify risks
5. **Generate clarifying questions** (if needed):
   - Queue questions to human via `announce` queue
   - Wait for answers (or proceed with assumptions)
6. **Create planning task**:
   - Automatically queue to `planning` queue with researched requirements
   - Link researched requirements document to planning task
7. **Announce completion**: Queue to `announce` queue with research summary
8. **Mark complete** - Task done, planning task queued

## Error Handling
- If research is incomplete: Queue follow-up research task
- If requirement is unclear: Queue clarifying questions via `announce`
- If blocked: Queue to `announce` with blocker information

## Integration Points
- **Input**: Receives from humans via `/create-work` command
- **Output**: Queues to `planning` queue automatically (Step 02)
- **Questions**: Uses `announce` queue to ask humans
- **Blockers**: Uses `announce` queue to report issues
- **Announcements**: Announces work start, completion, and status

## Agent Script
- **Script**: `agent-requirements-research.sh`
- **Workspace**: No workspace needed (research only, no code changes)
- **Cursor Agent**: Invokes Cursor agent to perform research
- **Auto-Queue**: Automatically queues to planning queue on completion

## Queue Process Requirements

### Process Architecture
- **Dedicated Process**: Runs in continuous loop, monitors `requirements-research` queue
- **Multiple Instances**: Can run multiple processes in parallel for scalability
- **Generic Logic**: Uses shared queue handling (claiming, status updates, heartbeats)
- **Queue-Specific Logic**: 
  - Research workflow execution
  - Requirements document creation
  - Automatic queuing to planning queue
  - No workspace management needed

### Process Lifecycle
- **Modification Date Tracking**: Monitors script file modification date
- **Graceful Shutdown**: On code change, completes current task and exits
- **Restart Required**: Must be manually restarted after code updates

### Process Flow
1. Loop: Check for available tasks in `requirements-research` queue
2. Claim: Atomically claim a task (if available)
3. Execute: Invoke Cursor agent to perform research
4. Update: Mark task complete, queue to planning queue
5. Announce: Create announcement via announce queue
6. Monitor: Check script modification date
7. Repeat: Return to step 1 (or exit if code changed)

## Success Criteria
- Requirements document is comprehensive and detailed
- All background research is documented
- Assumptions are clearly stated
- Next step (planning) is automatically queued
- No critical information gaps remain

## Best Practices & Strategic Guidance

### Research Strategy: Multi-Stage Synthesis
**Approach**: Use a "Fetch-Decide-Verify" pattern to avoid information overload and hallucinations.

1. **Iterative Search**: Break research into smaller, specific questions rather than one massive query
   - Use "Decide relevance" step to filter results before deep processing
   - Avoid context stuffing by focusing on specific areas

2. **Source Cross-Referencing**: Require agents to cite multiple sources
   - Verify findings through secondary search tools
   - Assign confidence scores to sources (official docs > community forums > blog posts)

3. **Context Engineering**: Provide clear research goals and constraints
   - Define scope boundaries (e.g., "only look for 2024 data")
   - Prevent scope creep with explicit constraints

4. **Contextual RAG**: For codebase research, search local repository alongside web
   - Use tools like `grep` or vector embeddings for codebase analysis
   - Ground research in existing project context

5. **Reflection Loop**: After gathering data, perform reflection step
   - Evaluate if information is sufficient
   - Identify gaps that require new search queries
   - Compare findings against original goal

6. **Source Citation**: Always link findings back to specific files or URLs
   - Prevent "hallucinated" requirements
   - Enable verification and traceability

### Research Phases
1. **Metadata Discovery**: Fetch high-level metadata first (table schemas, API docs, file structures)
2. **Deep Dive**: Focus intensive research on relevant areas identified in phase 1
3. **Synthesis**: Combine findings into coherent requirements document
4. **Verification**: Cross-check critical assumptions and facts

### Output Quality Standards
- **Structured Discovery Document**: Serve as primary context for planning and design agents
- **Assumptions Documented**: Clearly state what was assumed vs. verified
- **Gaps Identified**: Explicitly list any information gaps or uncertainties
- **Source Attribution**: Every claim must have a source reference
