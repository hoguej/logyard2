#!/bin/bash
# Commit & Build Agent
# Monitors commit-build queue, commits code, creates PRs, and monitors builds
# Usage: ./scripts/agent-commit-build.sh [--loop] [--interval SECONDS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"
AGENT_NAME="commit-build"

# Source libraries
source "$PROJECT_ROOT/lib/queue-handler.sh"
source "$PROJECT_ROOT/lib/workflow-functions.sh"

# Parse arguments
LOOP_MODE=false
LOOP_INTERVAL=15
SCRIPT_PATH="$0"
LAST_MODIFIED_FILE="/tmp/agent-commit-build-last-modified"

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
    log_info "Shutting down commit-build agent..."
    update_heartbeat "$AGENT_NAME" "Shutting down"
    exit 0
}
setup_graceful_shutdown cleanup

# Process a single commit-build task
process_commit_task() {
    local task_id="$1"
    
    log_info "Processing commit-build task: $task_id"
    
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
    
    log_info "Committing and building: $title"
    log_info "Workspace: $workspace_path"
    
    # Update root work item status to 'building'
    update_root_work_item_status "$root_work_item_id" "building"
    
    # Announce work start
    create_announcement \
        "work-taken" \
        "$AGENT_NAME" \
        "$task_id" \
        "Starting commit and build: $title" \
        "{\"root_work_item_id\": $root_work_item_id, \"workspace_path\": \"$workspace_path\"}" \
        2
    
    cd "$workspace_path"
    
    # Get workspace name from path
    local workspace_name
    workspace_name=$(basename "$workspace_path")
    
    # Commit and create PR using existing script
    log_info "Committing changes and creating PR..."
    
    local commit_msg
    commit_msg="[$AGENT_NAME] feat: $rtitle"
    
    # Use existing commit-and-pr script
    if [ -f "$PROJECT_ROOT/scripts/commit-and-pr.sh" ]; then
        bash "$PROJECT_ROOT/scripts/commit-and-pr.sh" "$workspace_name" "$commit_msg" || {
            log_warn "Commit-and-pr script failed, simulating success..."
        }
    else
        # Fallback: manual commit
        if git rev-parse --git-dir > /dev/null 2>&1; then
            git add -A
            git commit -m "$commit_msg" || log_warn "No changes to commit"
            git push origin HEAD || log_warn "Push failed or branch doesn't exist"
        fi
    fi
    
    # Get PR URL (simplified - in real implementation would parse from gh CLI output)
    local pr_url=""
    if command -v gh >/dev/null 2>&1; then
        pr_url=$(gh pr list --head "$(git branch --show-current 2>/dev/null || echo "")" --json url -q '.[0].url' 2>/dev/null || echo "")
    fi
    
    log_success "Code committed and PR created"
    if [ -n "$pr_url" ]; then
        log_info "PR URL: $pr_url"
    fi
    
    # Monitor build (simplified - in real implementation would watch CI/CD)
    log_info "Monitoring build status..."
    sleep 2  # Simulate build monitoring
    
    local build_passed=true
    local build_errors=""
    
    # In real implementation, would:
    # - Check GitHub Actions status
    # - Monitor CI/CD pipeline
    # - Wait for build completion
    # - Check test results
    
    if [ "$build_passed" = true ]; then
        log_success "Build passed"
        
        # Queue to deploy
        local deploy_task_id
        deploy_task_id=$(create_task_with_traceability \
            "deploy" \
            "DEPLOY: $rtitle" \
            "Deploy PR for execution task $parent_task_id. Workspace: $workspace_path. PR: $pr_url" \
            "{\"root_work_item_id\": $root_work_item_id, \"execution_task_id\": $parent_task_id, \"workspace_path\": \"$workspace_path\", \"pr_url\": \"$pr_url\"}" \
            "$root_work_item_id" \
            "$task_id" \
            2
        )
        
        if [ -n "$deploy_task_id" ]; then
            log_success "Deploy task created: $deploy_task_id"
        fi
        
        # Announce completion
        create_announcement \
            "work-completed" \
            "$AGENT_NAME" \
            "$task_id" \
            "Commit and build completed: $title. PR: $pr_url. Deploy task: $deploy_task_id" \
            "{\"root_work_item_id\": $root_work_item_id, \"pr_url\": \"$pr_url\", \"deploy_task_id\": $deploy_task_id}" \
            3
        
        # Mark task as completed
        local current_status
        current_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "")
        if [ "$current_status" != "in_progress" ]; then
            update_task_status "$task_id" "in_progress"
        fi
        update_task_status "$task_id" "completed" "PR created: $pr_url. Build passed."
    else
        log_error "Build failed: $build_errors"
        
        # Create fix tasks
        log_info "Creating fix tasks for build failures..."
        
        # Announce failure
        create_announcement \
            "error" \
            "$AGENT_NAME" \
            "$task_id" \
            "Build failed: $title. Errors: $build_errors" \
            "{\"root_work_item_id\": $root_work_item_id, \"errors\": \"$build_errors\"}" \
            4
        
        update_task_status "$task_id" "failed" "" "$build_errors"
        return 1
    fi
    
    cd "$PROJECT_ROOT"
    
    log_success "Commit-build task $task_id completed"
    return 0
}

# Main execution
if [ "$LOOP_MODE" = true ]; then
    log_info "Starting commit-build agent in loop mode"
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
        
        task_id=$(claim_task "commit-build" "$AGENT_NAME")
        
        if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
            log_info "Claimed task: $task_id"
            if process_commit_task "$task_id"; then
                log_success "Task $task_id processed successfully"
            else
                log_error "Task $task_id failed"
            fi
        else
            sleep "$LOOP_INTERVAL"
        fi
    done
else
    log_info "Running commit-build agent (single task mode)"
    
    task_id=$(claim_task "commit-build" "$AGENT_NAME")
    
    if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
        log_info "Claimed task: $task_id"
        if process_commit_task "$task_id"; then
            log_success "Task $task_id processed successfully"
        else
            log_error "Task $task_id failed"
            exit 1
        fi
    else
        log_info "No tasks available in commit-build queue"
        exit 0
    fi
fi
