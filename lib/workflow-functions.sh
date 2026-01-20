#!/bin/bash
# Workflow Functions
# Additional functions for workflow management and traceability

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

# Source queue handler
source "$PROJECT_ROOT/lib/queue-handler.sh"

# WF-004: Create task with traceability linking
# Enhanced version that properly handles traceability
create_task_with_traceability() {
    local queue_name="$1"
    local title="$2"
    local description="$3"
    local context="${4:-}"
    local root_work_item_id="${5:-}"
    local parent_task_id="${6:-}"
    local priority="${7:-2}"
    
    local queue_id
    queue_id=$(get_queue_id "$queue_name")
    
    if [ -z "$queue_id" ]; then
        log_error "Queue '$queue_name' not found"
        return 1
    fi
    
    # Build work_item_chain from parent if provided
    local work_item_chain="[]"
    if [ -n "$parent_task_id" ]; then
        local parent_chain
        parent_chain=$(sqlite3 "$DB_FILE" "SELECT COALESCE(work_item_chain, '[]') FROM tasks WHERE id = $parent_task_id;" 2>/dev/null || echo "[]")
        # For simplicity, store as JSON array string (would need jq for proper JSON manipulation)
        work_item_chain="$parent_chain"
    fi
    
    # Ensure root_work_item_id is set from parent if not provided
    if [ -z "$root_work_item_id" ] && [ -n "$parent_task_id" ]; then
        root_work_item_id=$(sqlite3 "$DB_FILE" "SELECT root_work_item_id FROM tasks WHERE id = $parent_task_id;" 2>/dev/null || echo "")
    fi
    
    # Create task
    local task_id
    task_id=$(sqlite3 "$DB_FILE" <<EOF
INSERT INTO tasks (title, description, context, priority, status, queue_type, root_work_item_id, parent_task_id, work_item_chain)
VALUES ('$title', '$description', ${context:+'$context'}, $priority, 'queued', '$queue_name', ${root_work_item_id:+$root_work_item_id}, ${parent_task_id:+$parent_task_id}, '$work_item_chain')
RETURNING id;
EOF
)
    
    # Create queue_tasks entry
    sqlite3 "$DB_FILE" <<EOF
INSERT INTO queue_tasks (queue_id, task_id, status, priority)
VALUES ($queue_id, $task_id, 'queued', $priority);
EOF
    
    echo "$task_id"
}

# WF-007: Update root work item status
update_root_work_item_status() {
    local root_work_item_id="$1"
    local new_status="$2"
    
    if [ -z "$root_work_item_id" ] || [ -z "$new_status" ]; then
        log_error "update_root_work_item_status: root_work_item_id and status required"
        return 1
    fi
    
    local started_at_sql=""
    local completed_at_sql=""
    local failed_at_sql=""
    
    if [ "$new_status" = "researching" ] || [ "$new_status" = "planning" ] || [ "$new_status" = "executing" ]; then
        started_at_sql=", started_at = COALESCE(started_at, CURRENT_TIMESTAMP)"
    fi
    
    if [ "$new_status" = "completed" ]; then
        completed_at_sql=", completed_at = CURRENT_TIMESTAMP"
    fi
    
    if [ "$new_status" = "failed" ]; then
        failed_at_sql=", failed_at = CURRENT_TIMESTAMP"
    fi
    
    sqlite3 "$DB_FILE" <<EOF
UPDATE root_work_items
SET status = '$new_status'
    $started_at_sql
    $completed_at_sql
    $failed_at_sql
WHERE id = $root_work_item_id;
EOF
    
    log_info "Root work item $root_work_item_id status updated to: $new_status"
}

# WF-008: Get root work item status
get_root_work_item_status() {
    local root_work_item_id="$1"
    
    sqlite3 -separator '|' "$DB_FILE" "
        SELECT id, title, status, created_at, started_at, completed_at
        FROM root_work_items
        WHERE id = $root_work_item_id;
    " 2>/dev/null || echo ""
}

# WF-006: Get all tasks for a root work item
get_tasks_for_root_work_item() {
    local root_work_item_id="$1"
    
    sqlite3 -separator '|' "$DB_FILE" "
        SELECT id, title, status, queue_type, parent_task_id
        FROM tasks
        WHERE root_work_item_id = $root_work_item_id
        ORDER BY created_at ASC;
    " 2>/dev/null || echo ""
}

# WF-006: Get task chain
get_task_chain() {
    local task_id="$1"
    
    # Get all ancestors
    sqlite3 -separator '|' "$DB_FILE" "
        WITH RECURSIVE task_chain AS (
            SELECT id, title, parent_task_id, 0 as depth
            FROM tasks
            WHERE id = $task_id
            
            UNION ALL
            
            SELECT t.id, t.title, t.parent_task_id, tc.depth + 1
            FROM tasks t
            JOIN task_chain tc ON t.id = tc.parent_task_id
        )
        SELECT id, title, depth
        FROM task_chain
        ORDER BY depth DESC;
    " 2>/dev/null || echo ""
}

# WF-008: List all root work items with status
list_root_work_items() {
    local status_filter="${1:-}"
    
    local filter_sql=""
    if [ -n "$status_filter" ]; then
        filter_sql="WHERE status = '$status_filter'"
    fi
    
    sqlite3 -separator '|' "$DB_FILE" "
        SELECT id, title, status, created_at, started_at, completed_at
        FROM root_work_items
        $filter_sql
        ORDER BY created_at DESC;
    " 2>/dev/null || echo ""
}
