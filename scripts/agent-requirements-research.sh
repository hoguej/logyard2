#!/bin/bash
# Requirements Research Agent
# Monitors requirements-research queue and processes research tasks
# Usage: ./scripts/agent-requirements-research.sh [--loop] [--interval SECONDS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"
AGENT_NAME="requirements-research"

# Source libraries
source "$PROJECT_ROOT/lib/queue-handler.sh"
source "$PROJECT_ROOT/lib/workflow-functions.sh"

# Parse arguments
LOOP_MODE=false
LOOP_INTERVAL=15
SCRIPT_PATH="$0"
LAST_MODIFIED_FILE="/tmp/agent-requirements-research-last-modified"

while [[ $# -gt 0 ]]; do
    case $1 in
        --loop)
            LOOP_MODE=true
            shift
            ;;
        -n|--interval)
            LOOP_INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Setup graceful shutdown
cleanup() {
    log_info "Shutting down requirements-research agent..."
    update_heartbeat "$AGENT_NAME" "Shutting down"
    exit 0
}
setup_graceful_shutdown cleanup

# Create requirements/researched directory
mkdir -p "$PROJECT_ROOT/requirements/researched"

# Process a single research task
process_research_task() {
    local task_id="$1"
    
    log_info "Processing research task: $task_id"
    
    # Get task info
    local task_info
    task_info=$(get_task_info "$task_id")
    if [ -z "$task_info" ]; then
        log_error "Task $task_id not found"
        return 1
    fi
    
    # Parse task info (id|title|description|status|queue_type|root_work_item_id|parent_task_id)
    IFS='|' read -r tid title description status queue_type root_work_item_id parent_task_id <<< "$task_info"
    
    # Get root work item info
    local root_info
    root_info=$(get_root_work_item_status "$root_work_item_id")
    if [ -z "$root_info" ]; then
        log_error "Root work item $root_work_item_id not found"
        return 1
    fi
    
    # Parse root info (id|title|status|created_at|started_at|completed_at)
    IFS='|' read -r rid rtitle rstatus rcreated rstarted rcompleted <<< "$root_info"
    
    log_info "Researching: $title"
    log_info "Root work item: $rtitle (ID: $root_work_item_id)"
    
    # Update root work item status to 'researching'
    update_root_work_item_status "$root_work_item_id" "researching"
    
    # Announce work start
    create_announcement \
        "work-taken" \
        "$AGENT_NAME" \
        "$task_id" \
        "Starting research for: $title" \
        "{\"root_work_item_id\": $root_work_item_id}" \
        2
    
    # Create workspace for research (temporary)
    local workspace_dir
    workspace_dir=$(mktemp -d -t research-XXXXXX)
    
    # Create research context file
    cat > "$workspace_dir/.research-context.md" <<EOF
# Research Context

## Original Request
$description

## Root Work Item
- ID: $root_work_item_id
- Title: $rtitle
- Status: $rstatus

## Task
- ID: $task_id
- Title: $title

## Research Goals
1. Analyze the requirement in detail
2. Search codebase for similar features
3. Research best practices
4. Review existing documentation
5. Create comprehensive requirements document

## Output
Create a detailed requirements document at: requirements/researched/requirements-\${root_work_item_id}.md
EOF
    
    # Create instructions for Cursor agent
    cat > "$workspace_dir/START-RESEARCH.md" <<EOF
# Research Task

You are a requirements research agent. Your task is to research the following requirement and create a comprehensive requirements document.

## Original Request
$description

## Instructions

1. **Analyze the requirement**: Break down what is being asked for
2. **Search the codebase**: Look for similar features, patterns, or related code
3. **Research best practices**: Consider industry standards and best practices
4. **Review documentation**: Check existing docs in the requirements/ directory
5. **Create requirements document**: Write a detailed requirements document

## Output Requirements

Create a file: \`requirements/researched/requirements-${root_work_item_id}.md\`

The document should include:
- **Background**: Context and motivation
- **Requirements**: Detailed functional and non-functional requirements
- **Assumptions**: Any assumptions made
- **Dependencies**: What this feature depends on
- **Risks**: Potential risks or challenges
- **References**: Links to related code, docs, or external resources

## Important

- Be thorough and comprehensive
- Ground your research in the actual codebase
- Cite specific files or code patterns you find
- If you need clarification, create an announcement (but try to proceed with reasonable assumptions)

When complete, the requirements document should be saved and ready for the planning phase.
EOF
    
    log_info "Invoking Cursor agent for research..."
    
    # Invoke Cursor agent
    # Note: This assumes Cursor CLI is available
    # In practice, this would open the workspace and file in Cursor
    if command -v cursor >/dev/null 2>&1; then
        cd "$workspace_dir"
        cursor "$workspace_dir/START-RESEARCH.md" 2>/dev/null || true
        cd "$PROJECT_ROOT"
    else
        log_warn "Cursor CLI not found, simulating research completion..."
        # For testing: create a basic requirements document
        sleep 2
    fi
    
    # Create requirements document (in real implementation, Cursor agent would create this)
    local req_doc="$PROJECT_ROOT/requirements/researched/requirements-${root_work_item_id}.md"
    cat > "$req_doc" <<EOF
# Requirements: $rtitle

**Root Work Item ID**: $root_work_item_id  
**Research Task ID**: $task_id  
**Created**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Background

$description

## Requirements

### Functional Requirements
- [To be filled by research agent]

### Non-Functional Requirements
- [To be filled by research agent]

## Assumptions

- [To be filled by research agent]

## Dependencies

- [To be filled by research agent]

## Risks

- [To be filled by research agent]

## References

- [To be filled by research agent]

---
*This document was generated by the requirements-research agent*
EOF
    
    log_success "Requirements document created: $req_doc"
    
    # Queue to planning
    local planning_task_id
    planning_task_id=$(create_task_with_traceability \
        "planning" \
        "PLAN: $rtitle" \
        "Break down requirements from research into executable tasks. See: $req_doc" \
        "{\"root_work_item_id\": $root_work_item_id, \"research_task_id\": $task_id, \"requirements_doc\": \"$req_doc\"}" \
        "$root_work_item_id" \
        "$task_id" \
        2
    )
    
    if [ -n "$planning_task_id" ]; then
        log_success "Planning task created: $planning_task_id"
    else
        log_error "Failed to create planning task"
    fi
    
    # Announce completion
    create_announcement \
        "work-completed" \
        "$AGENT_NAME" \
        "$task_id" \
        "Research completed for: $title. Requirements document: $req_doc. Planning task: $planning_task_id" \
        "{\"root_work_item_id\": $root_work_item_id, \"requirements_doc\": \"$req_doc\", \"planning_task_id\": $planning_task_id}" \
        3
    
    # Mark task as completed (task should already be in_progress from claiming)
    # First ensure it's in_progress, then complete it
    local current_status
    current_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "")
    if [ "$current_status" != "in_progress" ]; then
        update_task_status "$task_id" "in_progress"
    fi
    update_task_status "$task_id" "completed" "Requirements document created: $req_doc"
    
    # Cleanup workspace
    rm -rf "$workspace_dir"
    
    log_success "Research task $task_id completed"
    return 0
}

# Main execution
if [ "$LOOP_MODE" = true ]; then
    log_info "Starting requirements-research agent in loop mode"
    log_info "Agent: $AGENT_NAME"
    log_info "Check interval: ${LOOP_INTERVAL} seconds"
    log_info "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        # Check if script was modified
        if check_script_modified "$SCRIPT_PATH" "$LAST_MODIFIED_FILE"; then
            log_warn "Script modified, shutting down gracefully..."
            cleanup
        fi
        
        # Update heartbeat
        update_heartbeat "$AGENT_NAME" "Monitoring queue"
        
        # Check for stale agents
        check_stale_agents "$LOOP_INTERVAL"
        
        # Try to claim a task
        task_id=$(claim_task "requirements-research" "$AGENT_NAME")
        
        if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
            log_info "Claimed task: $task_id"
            
            # Process the task
            if process_research_task "$task_id"; then
                log_success "Task $task_id processed successfully"
            else
                log_error "Task $task_id failed"
                update_task_status "$task_id" "failed" "" "Research failed"
            fi
        else
            # No tasks available
            sleep "$LOOP_INTERVAL"
        fi
    done
else
    # Single run mode
    log_info "Running requirements-research agent (single task mode)"
    
    task_id=$(claim_task "requirements-research" "$AGENT_NAME")
    
    if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
        log_info "Claimed task: $task_id"
        if process_research_task "$task_id"; then
            log_success "Task $task_id processed successfully"
        else
            log_error "Task $task_id failed"
            update_task_status "$task_id" "failed" "" "Research failed"
            exit 1
        fi
    else
        log_info "No tasks available in requirements-research queue"
        exit 0
    fi
fi
