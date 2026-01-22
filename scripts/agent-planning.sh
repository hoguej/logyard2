#!/bin/bash
# Planning Agent
# Monitors planning queue and breaks down requirements into executable tasks
# Usage: ./scripts/agent-planning.sh [--loop] [--interval SECONDS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"
AGENT_NAME="planning"

# Source libraries
source "$PROJECT_ROOT/lib/queue-handler.sh"
source "$PROJECT_ROOT/lib/workflow-functions.sh"

# Parse arguments
LOOP_MODE=false
LOOP_INTERVAL=15
SCRIPT_PATH="$0"
LAST_MODIFIED_FILE="/tmp/agent-planning-last-modified"

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
    log_info "Shutting down planning agent..."
    update_heartbeat "$AGENT_NAME" "Shutting down"
    exit 0
}
setup_graceful_shutdown cleanup

# Create plans directory
mkdir -p "$PROJECT_ROOT/plans"

# Process a single planning task
process_planning_task() {
    local task_id="$1"
    
    log_info "Processing planning task: $task_id"
    
    # Get task info
    local task_info
    task_info=$(get_task_info "$task_id")
    if [ -z "$task_info" ]; then
        log_error "Task $task_id not found"
        return 1
    fi
    
    # Parse task info
    IFS='|' read -r tid title description status queue_type root_work_item_id parent_task_id <<< "$task_info"
    
    # Get root work item info
    local root_info
    root_info=$(get_root_work_item_status "$root_work_item_id")
    if [ -z "$root_info" ]; then
        log_error "Root work item $root_work_item_id not found"
        return 1
    fi
    
    IFS='|' read -r rid rtitle rstatus rcreated rstarted rcompleted <<< "$root_info"
    
    log_info "Planning: $title"
    log_info "Root work item: $rtitle (ID: $root_work_item_id)"
    
    # Update root work item status to 'planning'
    update_root_work_item_status "$root_work_item_id" "planning"
    
    # Announce work start
    create_announcement \
        "work-taken" \
        "$AGENT_NAME" \
        "$task_id" \
        "Starting planning for: $title" \
        "{\"root_work_item_id\": $root_work_item_id}" \
        2
    
    # Extract requirements document path from context
    local req_doc
    req_doc=$(sqlite3 "$DB_FILE" "SELECT context FROM tasks WHERE id = $task_id;" 2>/dev/null | grep -o '"requirements_doc":"[^"]*"' | cut -d'"' -f4 || echo "")
    
    if [ -z "$req_doc" ] || [ ! -f "$req_doc" ]; then
        # Try to find requirements document
        req_doc="$PROJECT_ROOT/requirements/researched/requirements-${root_work_item_id}.md"
    fi
    
    if [ ! -f "$req_doc" ]; then
        log_warn "Requirements document not found: $req_doc"
        log_info "Proceeding with task description as requirements"
        req_doc=""
    else
        log_info "Reading requirements from: $req_doc"
    fi
    
    # Create workspace for planning
    local workspace_dir
    workspace_dir=$(mktemp -d -t planning-XXXXXX)
    
    # Create planning context file
    cat > "$workspace_dir/.planning-context.md" <<EOF
# Planning Context

## Root Work Item
- ID: $root_work_item_id
- Title: $rtitle
- Status: $rstatus

## Planning Task
- ID: $task_id
- Title: $title
- Description: $description

## Requirements Document
$([ -n "$req_doc" ] && echo "- Path: $req_doc" || echo "- Using task description as requirements")

## Planning Goals
1. Break down requirements into executable tasks
2. Identify dependencies between tasks
3. Create detailed task specifications
4. Apply INVEST principle (Independent, Negotiable, Valuable, Estimable, Small, Testable)
5. Ensure tasks are 15-30 minutes of work
6. Create dependency graph
7. Queue execution tasks

## Output
Create planning document at: plans/plan-\${root_work_item_id}.md
Create execution tasks in execution queue
EOF
    
    if [ -f "$req_doc" ]; then
        cp "$req_doc" "$workspace_dir/requirements.md"
    fi
    
    # Create instructions for Cursor agent
    # Create tmp directory for agent prompts
    mkdir -p "$PROJECT_ROOT/tmp"
    
    # Create instructions for Cursor agent in tmp file
    local prompt_file="$PROJECT_ROOT/tmp/agent-planning-${task_id}.md"
    cat > "$prompt_file" <<EOF
# Planning Task

You are a planning agent. Your task is to break down the requirements into detailed, executable tasks.

## Requirements
$([ -f "$workspace_dir/requirements.md" ] && cat "$workspace_dir/requirements.md" || echo "$description")

## Instructions

1. **Analyze Requirements**: Understand what needs to be built
2. **Break Down Tasks**: Create 3-5 executable tasks (15-30 minutes each)
3. **Identify Dependencies**: Determine which tasks depend on others
4. **Create Task Specifications**: For each task, specify:
   - Implementation approach
   - Files to create/modify
   - Dependencies on other tasks
   - Acceptance criteria
   - Testing requirements
   - Estimated effort
   - Risks

5. **Apply INVEST Principle**: Ensure tasks are:
   - Independent (can be done in any order, respecting dependencies)
   - Negotiable (details can be adjusted)
   - Valuable (delivers value)
   - Estimable (can estimate effort)
   - Small (15-30 minutes)
   - Testable (has clear acceptance criteria)

6. **Create Planning Document**: Save to \`plans/plan-${root_work_item_id}.md\`

## Output Format

Create a planning document with:
- Task breakdown (list of tasks)
- Dependency graph
- Task details (for each task)
- Timeline estimates

When complete, the planning document should be saved and execution tasks should be queued.
EOF
    
    log_info "Invoking Cursor agent for planning..."
    log_info "Prompt file: $prompt_file"
    
    # Invoke Cursor agent (simulated for now)
    if command -v cursor >/dev/null 2>&1; then
        cursor "$workspace_dir" "$prompt_file" 2>/dev/null || true
    else
        log_warn "Cursor CLI not found, simulating planning completion..."
        sleep 2
    fi
    
    # Create planning document (in real implementation, Cursor agent would create this)
    local plan_doc="$PROJECT_ROOT/plans/plan-${root_work_item_id}.md"
    cat > "$plan_doc" <<EOF
# Planning: $rtitle

**Root Work Item ID**: $root_work_item_id  
**Planning Task ID**: $task_id  
**Created**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Overview

$description

## Task Breakdown

### Task 1: [To be filled by planning agent]
- **Implementation**: [Approach]
- **Files**: [Files to create/modify]
- **Dependencies**: None
- **Acceptance Criteria**: [Criteria]
- **Testing**: [Test requirements]
- **Effort**: 20 minutes
- **Risks**: [Risks]

### Task 2: [To be filled by planning agent]
- **Implementation**: [Approach]
- **Files**: [Files to create/modify]
- **Dependencies**: Task 1
- **Acceptance Criteria**: [Criteria]
- **Testing**: [Test requirements]
- **Effort**: 25 minutes
- **Risks**: [Risks]

## Dependency Graph

\`\`\`
Task 1 → Task 2 → Task 3
\`\`\`

## Timeline Estimate

- Total tasks: [Count]
- Estimated total time: [Time]
- Parallelizable: [Yes/No]

---
*This document was generated by the planning agent*
EOF
    
    log_success "Planning document created: $plan_doc"
    
    # Create execution tasks (simplified - in real implementation, Cursor would create these)
    local exec_tasks=()
    exec_tasks+=("EXECUTE: Implement core functionality")
    exec_tasks+=("EXECUTE: Add error handling")
    exec_tasks+=("EXECUTE: Write tests")
    
    local task_count=0
    for exec_title in "${exec_tasks[@]}"; do
        local exec_task_id
        exec_task_id=$(create_task_with_traceability \
            "execution" \
            "$exec_title" \
            "Execute: $exec_title. See planning document: $plan_doc" \
            "{\"root_work_item_id\": $root_work_item_id, \"planning_task_id\": $task_id, \"plan_doc\": \"$plan_doc\", \"task_index\": $task_count}" \
            "$root_work_item_id" \
            "$task_id" \
            2
        )
        
        if [ -n "$exec_task_id" ]; then
            task_count=$((task_count + 1))
            log_info "Created execution task: $exec_task_id - $exec_title"
        fi
    done
    
    # Announce completion
    create_announcement \
        "work-completed" \
        "$AGENT_NAME" \
        "$task_id" \
        "Planning completed for: $title. Created $task_count execution tasks. Planning document: $plan_doc" \
        "{\"root_work_item_id\": $root_work_item_id, \"plan_doc\": \"$plan_doc\", \"execution_tasks_created\": $task_count}" \
        3
    
    # Mark task as completed
    local current_status
    current_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "")
    if [ "$current_status" != "in_progress" ]; then
        update_task_status "$task_id" "in_progress"
    fi
    update_task_status "$task_id" "completed" "Planning document created: $plan_doc. $task_count execution tasks queued."
    
    # Cleanup workspace
    rm -rf "$workspace_dir"
    
    log_success "Planning task $task_id completed"
    return 0
}

# Main execution
if [ "$LOOP_MODE" = true ]; then
    log_info "Starting planning agent in loop mode"
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
        task_id=$(claim_task "planning" "$AGENT_NAME")
        
        if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
            log_info "Claimed task: $task_id"
            
            # Process the task
            if process_planning_task "$task_id"; then
                log_success "Task $task_id processed successfully"
            else
                log_error "Task $task_id failed"
                update_task_status "$task_id" "failed" "" "Planning failed"
            fi
        else
            # No tasks available
            sleep "$LOOP_INTERVAL"
        fi
    done
else
    # Single run mode
    log_info "Running planning agent (single task mode)"
    
    task_id=$(claim_task "planning" "$AGENT_NAME")
    
    if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
        log_info "Claimed task: $task_id"
        if process_planning_task "$task_id"; then
            log_success "Task $task_id processed successfully"
        else
            log_error "Task $task_id failed"
            update_task_status "$task_id" "failed" "" "Planning failed"
            exit 1
        fi
    else
        log_info "No tasks available in planning queue"
        exit 0
    fi
fi
