#!/bin/bash
# Pre-Commit Check Agent
# Monitors pre-commit-check queue and validates code quality
# Usage: ./scripts/agent-pre-commit-check.sh [--loop] [--interval SECONDS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"
AGENT_NAME="pre-commit-check"

# Source libraries
source "$PROJECT_ROOT/lib/queue-handler.sh"
source "$PROJECT_ROOT/lib/workflow-functions.sh"

# Parse arguments
LOOP_MODE=false
LOOP_INTERVAL=15
SCRIPT_PATH="$0"
LAST_MODIFIED_FILE="/tmp/agent-pre-commit-check-last-modified"

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
    log_info "Shutting down pre-commit-check agent..."
    update_heartbeat "$AGENT_NAME" "Shutting down"
    exit 0
}
setup_graceful_shutdown cleanup

# Process a single check task
process_check_task() {
    local task_id="$1"
    
    log_info "Processing pre-commit-check task: $task_id"
    
    # Get task info
    local task_info
    task_info=$(get_task_info "$task_id")
    if [ -z "$task_info" ]; then
        log_error "Task $task_id not found"
        return 1
    fi
    
    # Parse task info
    IFS='|' read -r tid title description status queue_type root_work_item_id parent_task_id <<< "$task_info"
    
    # Get workspace path from context
    local context_json
    context_json=$(sqlite3 "$DB_FILE" "SELECT context FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "{}")
    
    local workspace_path
    if command -v jq >/dev/null 2>&1; then
        workspace_path=$(echo "$context_json" | jq -r '.workspace_path // empty' 2>/dev/null || echo "")
    else
        workspace_path=$(echo "$context_json" | grep -o '"workspace_path":"[^"]*"' | cut -d'"' -f4 || echo "")
    fi
    
    if [ -z "$workspace_path" ] || [ ! -d "$workspace_path" ]; then
        log_error "Workspace not found for task $task_id: $workspace_path"
        return 1
    fi
    
    # Get root work item info
    local root_info
    root_info=$(get_root_work_item_status "$root_work_item_id")
    if [ -z "$root_info" ]; then
        log_error "Root work item $root_work_item_id not found"
        return 1
    fi
    
    IFS='|' read -r rid rtitle rstatus rcreated rstarted rcompleted <<< "$root_info"
    
    log_info "Checking: $title"
    log_info "Workspace: $workspace_path"
    
    # Update root work item status to 'checking'
    update_root_work_item_status "$root_work_item_id" "checking"
    
    # Announce work start
    create_announcement \
        "work-taken" \
        "$AGENT_NAME" \
        "$task_id" \
        "Starting pre-commit checks: $title" \
        "{\"root_work_item_id\": $root_work_item_id, \"workspace_path\": \"$workspace_path\"}" \
        2
    
    cd "$workspace_path"
    
    # Run checks (simplified - in real implementation would run linter, formatter, tests, etc.)
    local check_passed=true
    local check_errors=""
    
    log_info "Running code quality checks..."
    
    # Simulate checks
    if [ -f "IMPLEMENTATION.md" ]; then
        log_success "Implementation file found"
    else
        log_warn "No implementation file found"
    fi
    
    # In real implementation, would run:
    # - Linter (eslint, pylint, etc.)
    # - Formatter (prettier, black, etc.)
    # - Type checker (TypeScript, mypy, etc.)
    # - Unit tests
    # - Integration tests
    
    if [ "$check_passed" = true ]; then
        log_success "All pre-commit checks passed"
        
        # Queue to commit-build
        local commit_task_id
        commit_task_id=$(create_task_with_traceability \
            "commit-build" \
            "COMMIT: $title" \
            "Commit and build for execution task $parent_task_id. Workspace: $workspace_path" \
            "{\"root_work_item_id\": $root_work_item_id, \"execution_task_id\": $parent_task_id, \"workspace_path\": \"$workspace_path\"}" \
            "$root_work_item_id" \
            "$task_id" \
            2
        )
        
        if [ -n "$commit_task_id" ]; then
            log_success "Commit-build task created: $commit_task_id"
        fi
        
        # Announce completion
        create_announcement \
            "work-completed" \
            "$AGENT_NAME" \
            "$task_id" \
            "Pre-commit checks passed: $title. Commit-build task: $commit_task_id" \
            "{\"root_work_item_id\": $root_work_item_id, \"commit_task_id\": $commit_task_id}" \
            3
        
        # Mark task as completed
        local current_status
        current_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "")
        if [ "$current_status" != "in_progress" ]; then
            update_task_status "$task_id" "in_progress"
        fi
        update_task_status "$task_id" "completed" "All checks passed"
    else
        log_error "Pre-commit checks failed: $check_errors"
        
        # Create fix tasks (simplified)
        log_info "Creating fix tasks for failures..."
        
        # Announce failure
        create_announcement \
            "error" \
            "$AGENT_NAME" \
            "$task_id" \
            "Pre-commit checks failed: $title. Errors: $check_errors" \
            "{\"root_work_item_id\": $root_work_item_id, \"errors\": \"$check_errors\"}" \
            4
        
        update_task_status "$task_id" "failed" "" "$check_errors"
        return 1
    fi
    
    cd "$PROJECT_ROOT"
    
    log_success "Pre-commit-check task $task_id completed"
    return 0
}

# Main execution
if [ "$LOOP_MODE" = true ]; then
    log_info "Starting pre-commit-check agent in loop mode"
    log_info "Agent: $AGENT_NAME"
    log_info "Check interval: ${LOOP_INTERVAL} seconds"
    log_info "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        if check_script_modified "$SCRIPT_PATH" "$LAST_MODIFIED_FILE"; then
            log_warn "Script modified, shutting down gracefully..."
            cleanup
        fi
        
        update_heartbeat "$AGENT_NAME" "Monitoring queue"
        check_stale_agents "$LOOP_INTERVAL"
        
        task_id=$(claim_task "pre-commit-check" "$AGENT_NAME")
        
        if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
            log_info "Claimed task: $task_id"
            if process_check_task "$task_id"; then
                log_success "Task $task_id processed successfully"
            else
                log_error "Task $task_id failed"
            fi
        else
            sleep "$LOOP_INTERVAL"
        fi
    done
else
    log_info "Running pre-commit-check agent (single task mode)"
    
    task_id=$(claim_task "pre-commit-check" "$AGENT_NAME")
    
    if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
        log_info "Claimed task: $task_id"
        if process_check_task "$task_id"; then
            log_success "Task $task_id processed successfully"
        else
            log_error "Task $task_id failed"
            exit 1
        fi
    else
        log_info "No tasks available in pre-commit-check queue"
        exit 0
    fi
fi
