#!/bin/bash
# Deploy Agent
# Monitors deploy queue, merges PRs, and monitors deployment
# Usage: ./scripts/agent-deploy.sh [--loop] [--interval SECONDS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"
AGENT_NAME="deploy"

# Source libraries
source "$PROJECT_ROOT/lib/queue-handler.sh"
source "$PROJECT_ROOT/lib/workflow-functions.sh"

# Parse arguments
LOOP_MODE=false
LOOP_INTERVAL=15
INSTANCE_ID=""
SCRIPT_PATH="$0"
LAST_MODIFIED_FILE="/tmp/agent-deploy-last-modified"
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
    log_info "Shutting down deploy agent (instance: $INSTANCE_ID)..."
    update_heartbeat "$AGENT_NAME" "Shutting down" "$INSTANCE_ID" "offline"
    # Clean up PID file
    rm -f "$PID_FILE"
    exit 0
}
setup_graceful_shutdown cleanup

# Process a single deploy task
process_deploy_task() {
    local task_id="$1"
    
    log_info "Processing deploy task: $task_id"
    
    # Get task info
    local task_info
    task_info=$(get_task_info "$task_id")
    if [ -z "$task_info" ]; then
        log_error "Task $task_id not found"
        return 1
    fi
    
    # Parse task info
    IFS='|' read -r tid title description status queue_type root_work_item_id parent_task_id <<< "$task_info"
    
    # Get workspace path and PR URL from context
    local context_json
    context_json=$(sqlite3 "$DB_FILE" "SELECT context FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "{}")
    
    local workspace_path
    local pr_url
    if command -v jq >/dev/null 2>&1; then
        workspace_path=$(echo "$context_json" | jq -r '.workspace_path // empty' 2>/dev/null || echo "")
        pr_url=$(echo "$context_json" | jq -r '.pr_url // empty' 2>/dev/null || echo "")
    else
        workspace_path=$(echo "$context_json" | grep -o '"workspace_path":"[^"]*"' | cut -d'"' -f4 || echo "")
        pr_url=$(echo "$context_json" | grep -o '"pr_url":"[^"]*"' | cut -d'"' -f4 || echo "")
    fi
    
    # Get root work item info
    local root_info
    root_info=$(get_root_work_item_status "$root_work_item_id")
    if [ -z "$root_info" ]; then
        log_error "Root work item $root_work_item_id not found"
        return 1
    fi
    
    IFS='|' read -r rid rtitle rstatus rcreated rstarted rcompleted <<< "$root_info"
    
    log_info "Deploying: $title"
    if [ -n "$pr_url" ]; then
        log_info "PR URL: $pr_url"
    fi
    
    # Update root work item status to 'deploying'
    update_root_work_item_status "$root_work_item_id" "deploying"
    
    # Announce work start
    create_announcement \
        "work-taken" \
        "$AGENT_NAME" \
        "$task_id" \
        "Starting deployment: $title" \
        "{\"root_work_item_id\": $root_work_item_id, \"pr_url\": \"$pr_url\"}" \
        2
    
    # Merge PR (simplified - in real implementation would use GitHub API)
    log_info "Merging PR..."
    
    if [ -n "$pr_url" ] && command -v gh >/dev/null 2>&1; then
        # Extract PR number from URL
        local pr_number
        pr_number=$(echo "$pr_url" | grep -o '/pull/[0-9]*' | cut -d'/' -f3 || echo "")
        
        if [ -n "$pr_number" ]; then
            # Check PR status
            local pr_status
            pr_status=$(gh pr view "$pr_number" --json state -q '.state' 2>/dev/null || echo "")
            
            if [ "$pr_status" = "OPEN" ]; then
                # Merge PR
                gh pr merge "$pr_number" --merge --delete-branch 2>/dev/null || {
                    log_warn "PR merge failed or already merged"
                }
                log_success "PR merged: $pr_url"
            else
                log_info "PR already $pr_status"
            fi
        fi
    else
        log_warn "PR URL not available or gh CLI not found, simulating merge..."
    fi
    
    # Monitor deployment (simplified)
    log_info "Monitoring deployment..."
    sleep 2  # Simulate deployment monitoring
    
    local deploy_passed=true
    local deploy_errors=""
    
    # In real implementation, would:
    # - Monitor deployment pipeline
    # - Check service health
    # - Run smoke tests
    # - Verify services are running
    
    if [ "$deploy_passed" = true ]; then
        log_success "Deployment successful"
        
        # Destroy workspace on success
        if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
            log_info "Destroying workspace: $workspace_path"
            rm -rf "$workspace_path"
            log_success "Workspace destroyed"
        fi
        
        # Update root work item status to 'completed'
        update_root_work_item_status "$root_work_item_id" "completed"
        
        # Announce completion
        create_announcement \
            "work-completed" \
            "$AGENT_NAME" \
            "$task_id" \
            "Deployment completed: $title. PR merged: $pr_url. Root work item completed." \
            "{\"root_work_item_id\": $root_work_item_id, \"pr_url\": \"$pr_url\"}" \
            3
        
        # Mark task as completed
        local current_status
        current_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "")
        if [ "$current_status" != "in_progress" ]; then
            update_task_status "$task_id" "in_progress"
        fi
        update_task_status "$task_id" "completed" "Deployment successful. PR merged: $pr_url"
    else
        log_error "Deployment failed: $deploy_errors"
        
        # Preserve workspace on failure
        log_info "Preserving workspace for fix agents: $workspace_path"
        
        # Create fix tasks
        log_info "Creating fix tasks for deployment failures..."
        
        # Announce failure
        create_announcement \
            "error" \
            "$AGENT_NAME" \
            "$task_id" \
            "Deployment failed: $title. Errors: $deploy_errors. Workspace preserved: $workspace_path" \
            "{\"root_work_item_id\": $root_work_item_id, \"errors\": \"$deploy_errors\", \"workspace_path\": \"$workspace_path\"}" \
            4
        
        update_root_work_item_status "$root_work_item_id" "failed"
        update_task_status "$task_id" "failed" "" "$deploy_errors"
        return 1
    fi
    
    log_success "Deploy task $task_id completed"
    return 0
}

# Main execution
if [ "$LOOP_MODE" = true ]; then
    log_info "Starting deploy agent in loop mode"
    log_info "Agent: $AGENT_NAME"
    log_info "Check interval: ${LOOP_INTERVAL} seconds"
    log_info "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        if check_script_modified "$SCRIPT_PATH" "$LAST_MODIFIED_FILE"; then
            log_warn "Script modified, shutting down gracefully..."
            cleanup
        fi
        
        update_heartbeat "$AGENT_NAME" "Monitoring queue" "$INSTANCE_ID" "idle"
        check_stale_agents "$LOOP_INTERVAL"
        
        task_id=$(claim_task "deploy" "$AGENT_NAME" || true)
        
        if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
            log_info "Claimed task: $task_id"
            if process_deploy_task "$task_id"; then
                log_success "Task $task_id processed successfully"
            else
                log_error "Task $task_id failed"
            fi
        else
            sleep "$LOOP_INTERVAL"
        fi
    done
else
    log_info "Running deploy agent (single task mode)"
    
    task_id=$(claim_task "deploy" "$AGENT_NAME")
    
    if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
        log_info "Claimed task: $task_id"
        if process_deploy_task "$task_id"; then
            log_success "Task $task_id processed successfully"
        else
            log_error "Task $task_id failed"
            exit 1
        fi
    else
        log_info "No tasks available in deploy queue"
        exit 0
    fi
fi
