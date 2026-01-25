#!/bin/bash
# Execution Agent
# Monitors execution queue and implements code changes
# Usage: ./scripts/agent-execution.sh [--loop] [--interval SECONDS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"
AGENT_NAME="execution"

# Source libraries
source "$PROJECT_ROOT/lib/queue-handler.sh"
source "$PROJECT_ROOT/lib/workflow-functions.sh"

# Parse arguments
LOOP_MODE=false
LOOP_INTERVAL=15
INSTANCE_ID=""
SCRIPT_PATH="$0"
LAST_MODIFIED_FILE="/tmp/agent-execution-last-modified"
PID_FILE=""

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
        --instance-id)
            INSTANCE_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Generate instance ID if not provided
if [ -z "$INSTANCE_ID" ]; then
    INSTANCE_ID=$(date +%Y%m%d_%H%M%S_%N | cut -c1-23)
fi

# Set PID file
PID_FILE="/tmp/agent-${AGENT_NAME}-${INSTANCE_ID}.pid"

# Write PID to file
echo $$ > "$PID_FILE"

# Register in database with PID
sqlite3 "$DB_FILE" "
    INSERT OR REPLACE INTO agents (name, instance_id, pid, status, last_heartbeat, last_activity)
    VALUES ('$AGENT_NAME', '$INSTANCE_ID', $$, 'idle', datetime('now'), 'Started');
" 2>/dev/null || log_warn "Could not register in database"

# Setup graceful shutdown
cleanup() {
    log_info "Shutting down execution agent (instance: $INSTANCE_ID)..."
    update_heartbeat "$AGENT_NAME" "Shutting down" "$INSTANCE_ID" "offline"
    # Clean up PID file
    rm -f "$PID_FILE"
    exit 0
}
setup_graceful_shutdown cleanup

# Create workspaces directory
mkdir -p "$PROJECT_ROOT/workspaces"

# Check if dependencies are complete
check_dependencies() {
    local task_id="$1"
    
    # Get parent task ID
    local parent_task_id
    parent_task_id=$(sqlite3 "$DB_FILE" "SELECT parent_task_id FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "")
    
    if [ -z "$parent_task_id" ] || [ "$parent_task_id" = "NULL" ] || [ "$parent_task_id" = "" ]; then
        return 0  # No dependencies
    fi
    
    # Check if parent task is completed
    local parent_status
    parent_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id = $parent_task_id;" 2>/dev/null || echo "")
    
    if [ "$parent_status" = "completed" ]; then
        return 0  # Dependencies satisfied
    else
        log_info "Waiting for dependency: task $parent_task_id (status: $parent_status)"
        return 1  # Dependencies not ready
    fi
}

# Process a single execution task
process_execution_task() {
    local task_id="$1"
    
    log_info "Processing execution task: $task_id"
    
    # Check dependencies
    if ! check_dependencies "$task_id"; then
        log_warn "Dependencies not ready for task $task_id, skipping"
        return 1
    fi
    
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
    
    log_info "Executing: $title"
    log_info "Root work item: $rtitle (ID: $root_work_item_id)"
    
    # Update root work item status to 'executing' (only on first execution task)
    if [ "$rstatus" != "executing" ] && [ "$rstatus" != "checking" ] && [ "$rstatus" != "building" ] && [ "$rstatus" != "deploying" ]; then
        update_root_work_item_status "$root_work_item_id" "executing"
    fi
    
    # Announce work start
    create_announcement \
        "work-taken" \
        "$AGENT_NAME" \
        "$task_id" \
        "Starting execution: $title" \
        "{\"root_work_item_id\": $root_work_item_id}" \
        2
    
    # Create workspace (ONLY step that creates workspace)
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local workspace_name="exec_${root_work_item_id}_${timestamp}"
    local workspace_path="$PROJECT_ROOT/workspaces/$workspace_name"
    
    log_info "Creating workspace: $workspace_path"
    
    # Clone repository
    if [ ! -d "$workspace_path" ]; then
        git clone "$PROJECT_ROOT" "$workspace_path" 2>/dev/null || {
            # If not a git repo, create directory structure
            mkdir -p "$workspace_path"
            cp -r "$PROJECT_ROOT"/* "$workspace_path"/ 2>/dev/null || true
        }
    fi
    
    cd "$workspace_path"
    
    # Create feature branch
    local branch_name
    branch_name=$(echo "$title" | sed 's/^[^:]*: //' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g' | cut -c1-50)
    branch_name="feature/${root_work_item_id}-${branch_name}"
    
    if git rev-parse --git-dir > /dev/null 2>&1; then
        git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name" 2>/dev/null || true
    fi
    
    # Create workspace context
    cat > "$workspace_path/.context.json" <<EOF
{
  "workspace_name": "$workspace_name",
  "workspace_path": "$workspace_path",
  "branch_name": "$branch_name",
  "task_id": $task_id,
  "task_title": "$title",
  "root_work_item_id": $root_work_item_id,
  "root_work_item_title": "$rtitle"
}
EOF
    
    # Store workspace path in task context (simple JSON string)
    local new_context="{\"workspace_path\": \"$workspace_path\", \"branch_name\": \"$branch_name\", \"root_work_item_id\": $root_work_item_id}"
    sqlite3 "$DB_FILE" "UPDATE tasks SET context = '$new_context' WHERE id = $task_id;"
    
    # Create tmp directory for agent prompts
    mkdir -p "$PROJECT_ROOT/tmp"
    
    # Create execution instructions in tmp file
    local prompt_file="$PROJECT_ROOT/tmp/agent-execution-${task_id}.md"
    cat > "$prompt_file" <<EOF
# Execution Task

You are an execution agent. Your task is to implement the code changes.

## Task
- **ID**: $task_id
- **Title**: $title
- **Description**: $description

## Root Work Item
- **ID**: $root_work_item_id
- **Title**: $rtitle

## Instructions

1. **Read the planning document**: Check \`plans/plan-${root_work_item_id}.md\`
2. **Implement the code**: Make the necessary code changes
3. **Follow the plan**: Use the implementation approach specified
4. **Create/modify files**: As specified in the plan
5. **Write tests**: Include tests as required
6. **Self-review**: Check code quality and acceptance criteria
7. **Update documentation**:
   - Update README.md if adding new features or changing behavior
   - Update API documentation if adding/modifying endpoints
   - Add code comments for complex logic and non-obvious decisions
   - Document why certain approaches were chosen

## Workspace
- **Path**: $workspace_path
- **Branch**: $branch_name

## Important
- All changes must be in this workspace
- Follow project coding standards
- Ensure tests are written
- Verify acceptance criteria are met
- **Documentation is required**: Update relevant docs as part of implementation

When complete, the code should be ready for pre-commit checks.
EOF
    
    log_info "Invoking headless Cursor agent for execution..."
    log_info "Prompt file: $prompt_file"

    if ! run_cursor_agent "$workspace_path" "$prompt_file"; then
        log_error "Cursor agent failed for execution task $task_id"
        update_task_status "$task_id" "failed" "" "Cursor agent failed"
        return 1
    fi

    if git rev-parse --git-dir > /dev/null 2>&1; then
        if [ -z "$(git status --porcelain)" ]; then
            log_warn "No workspace changes detected after execution task $task_id"
        fi
    fi
    
    log_success "Code execution completed in workspace: $workspace_path"
    
    # Queue to pre-commit-check
    local check_task_id
    check_task_id=$(create_task_with_traceability \
        "pre-commit-check" \
        "CHECK: $title" \
        "Run pre-commit checks on execution task $task_id. Workspace: $workspace_path" \
        "{\"root_work_item_id\": $root_work_item_id, \"execution_task_id\": $task_id, \"workspace_path\": \"$workspace_path\", \"branch_name\": \"$branch_name\"}" \
        "$root_work_item_id" \
        "$task_id" \
        2
    )
    
    if [ -n "$check_task_id" ]; then
        log_success "Pre-commit-check task created: $check_task_id"
    else
        log_error "Failed to create pre-commit-check task"
    fi
    
    # Announce completion
    create_announcement \
        "work-completed" \
        "$AGENT_NAME" \
        "$task_id" \
        "Execution completed: $title. Workspace: $workspace_path. Pre-commit-check task: $check_task_id" \
        "{\"root_work_item_id\": $root_work_item_id, \"workspace_path\": \"$workspace_path\", \"check_task_id\": $check_task_id}" \
        3
    
    # Mark task as completed
    local current_status
    current_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "")
    if [ "$current_status" != "in_progress" ]; then
        update_task_status "$task_id" "in_progress"
    fi
    update_task_status "$task_id" "completed" "Code implemented in workspace: $workspace_path"
    
    cd "$PROJECT_ROOT"
    
    log_success "Execution task $task_id completed"
    return 0
}

# Main execution
if [ "$LOOP_MODE" = true ]; then
    log_info "Starting execution agent in loop mode"
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
        update_heartbeat "$AGENT_NAME" "Monitoring queue" "$INSTANCE_ID" "idle"
        
        # Check for stale agents
        check_stale_agents "$LOOP_INTERVAL"
        
        # Try to claim a task
        task_id=$(claim_task "execution" "$AGENT_NAME" || true)
        
        if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
            log_info "Claimed task: $task_id"
            
            # Process the task
            if process_execution_task "$task_id"; then
                log_success "Task $task_id processed successfully"
            else
                log_error "Task $task_id failed"
                update_task_status "$task_id" "failed" "" "Execution failed"
            fi
        else
            # No tasks available
            sleep "$LOOP_INTERVAL"
        fi
    done
else
    # Single run mode
    log_info "Running execution agent (single task mode)"
    
    task_id=$(claim_task "execution" "$AGENT_NAME")
    
    if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
        log_info "Claimed task: $task_id"
        if process_execution_task "$task_id"; then
            log_success "Task $task_id processed successfully"
        else
            log_error "Task $task_id failed"
            update_task_status "$task_id" "failed" "" "Execution failed"
            exit 1
        fi
    else
        log_info "No tasks available in execution queue"
        exit 0
    fi
fi
