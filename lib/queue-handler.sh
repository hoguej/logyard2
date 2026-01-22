#!/bin/bash
# Shared Queue Handling Library
# Provides common functions for all queue agent processes
# Source this file in agent scripts: source "$(dirname "$0")/../lib/queue-handler.sh"

set -euo pipefail

# Get project root and database path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# LIB-002: Atomic task claiming
# Claims a task from the specified queue atomically
# Usage: claim_task QUEUE_NAME AGENT_NAME [PRIORITY_FILTER]
# Returns: task_id on success, empty on failure
claim_task() {
    local queue_name="$1"
    local agent_name="$2"
    local priority_filter="${3:-}"
    
    if [ -z "$queue_name" ] || [ -z "$agent_name" ]; then
        log_error "claim_task: queue_name and agent_name required"
        return 1
    fi
    
    # Get queue ID
    local queue_id
    queue_id=$(sqlite3 "$DB_FILE" "SELECT id FROM queues WHERE name = '$queue_name';" 2>/dev/null || echo "")
    
    if [ -z "$queue_id" ]; then
        log_error "Queue '$queue_name' not found"
        return 1
    fi
    
    # Build priority filter SQL
    local priority_sql=""
    if [ -n "$priority_filter" ]; then
        priority_sql="AND qt.priority <= $priority_filter"
    fi
    
    # Atomic claim using transaction
    local task_id
    task_id=$(sqlite3 "$DB_FILE" <<EOF
BEGIN TRANSACTION;

-- Find available task
SELECT qt.task_id 
FROM queue_tasks qt
JOIN tasks t ON qt.task_id = t.id
WHERE qt.queue_id = $queue_id
  AND qt.status = 'queued'
  AND t.status = 'queued'
  $priority_sql
ORDER BY qt.priority DESC, qt.created_at ASC
LIMIT 1;

-- If task found, claim it
UPDATE queue_tasks 
SET status = 'in_progress', updated_at = CURRENT_TIMESTAMP
WHERE queue_id = $queue_id AND task_id = (SELECT task_id FROM (
    SELECT qt.task_id 
    FROM queue_tasks qt
    JOIN tasks t ON qt.task_id = t.id
    WHERE qt.queue_id = $queue_id
      AND qt.status = 'queued'
      AND t.status = 'queued'
      $priority_sql
    ORDER BY qt.priority DESC, qt.created_at ASC
    LIMIT 1
));

UPDATE tasks
SET status = 'in_progress',
    claimed_at = CURRENT_TIMESTAMP,
    claimed_by = '$agent_name'
WHERE id = (SELECT task_id FROM (
    SELECT qt.task_id 
    FROM queue_tasks qt
    JOIN tasks t ON qt.task_id = t.id
    WHERE qt.queue_id = $queue_id
      AND qt.status = 'queued'
      AND t.status = 'queued'
      $priority_sql
    ORDER BY qt.priority DESC, qt.created_at ASC
    LIMIT 1
));

COMMIT;
EOF
)
    
    if [ -n "$task_id" ] && [ "$task_id" != "" ]; then
        echo "$task_id"
        return 0
    else
        return 1
    fi
}

# LIB-003: Status management
# Update task status with validation
# Usage: update_task_status TASK_ID STATUS [RESULT] [ERROR]
update_task_status() {
    local task_id="$1"
    local new_status="$2"
    local result="${3:-}"
    local error="${4:-}"
    
    if [ -z "$task_id" ] || [ -z "$new_status" ]; then
        log_error "update_task_status: task_id and status required"
        return 1
    fi
    
    # Validate status
    case "$new_status" in
        queued|in_progress|completed|failed|cancelled)
            ;;
        *)
            log_error "Invalid status: $new_status"
            return 1
            ;;
    esac
    
    # Get current status
    local current_status
    current_status=$(sqlite3 "$DB_FILE" "SELECT status FROM tasks WHERE id = $task_id;" 2>/dev/null || echo "")
    
    if [ -z "$current_status" ]; then
        log_error "Task $task_id not found"
        return 1
    fi
    
    # Validate state transition
    case "$current_status" in
        queued)
            if [ "$new_status" != "in_progress" ] && [ "$new_status" != "cancelled" ]; then
                log_error "Invalid transition: $current_status -> $new_status"
                return 1
            fi
            ;;
        in_progress)
            if [ "$new_status" != "completed" ] && [ "$new_status" != "failed" ] && [ "$new_status" != "cancelled" ]; then
                log_error "Invalid transition: $current_status -> $new_status"
                return 1
            fi
            ;;
        completed|failed|cancelled)
            log_error "Cannot transition from terminal state: $current_status"
            return 1
            ;;
    esac
    
    # Update task status
    local completed_at_sql=""
    if [ "$new_status" = "completed" ] || [ "$new_status" = "failed" ]; then
        completed_at_sql=", completed_at = CURRENT_TIMESTAMP"
    fi
    
    # Build result and error SQL
    local result_sql="result = NULL"
    local error_sql="error = NULL"
    if [ -n "$result" ]; then
        result=$(echo "$result" | sed "s/'/''/g")
        result_sql="result = '$result'"
    fi
    if [ -n "$error" ]; then
        error=$(echo "$error" | sed "s/'/''/g")
        error_sql="error = '$error'"
    fi
    
    sqlite3 "$DB_FILE" <<EOF
UPDATE tasks
SET status = '$new_status',
    $result_sql,
    $error_sql
    $completed_at_sql
WHERE id = $task_id;

UPDATE queue_tasks
SET status = '$new_status',
    updated_at = CURRENT_TIMESTAMP
WHERE task_id = $task_id;
EOF
    
    log_success "Task $task_id status updated: $current_status -> $new_status"
}

# LIB-004: Heartbeat management
# Update agent heartbeat
# Usage: update_heartbeat AGENT_NAME [ACTIVITY_MESSAGE] [INSTANCE_ID] [STATUS]
update_heartbeat() {
    local agent_name="$1"
    local activity="${2:-Working}"
    local instance_id="${3:-}"
    local status="${4:-working}"
    
    if [ -z "$agent_name" ]; then
        log_error "update_heartbeat: agent_name required"
        return 1
    fi
    
    # If instance_id provided, update specific instance
    if [ -n "$instance_id" ]; then
        sqlite3 "$DB_FILE" <<EOF
UPDATE agents 
SET status = '$status',
    last_heartbeat = CURRENT_TIMESTAMP,
    last_activity = '$activity'
WHERE name = '$agent_name' AND instance_id = '$instance_id';
EOF
    else
        # Legacy: update all instances with this name (for backward compatibility)
        sqlite3 "$DB_FILE" <<EOF
UPDATE agents 
SET status = '$status',
    last_heartbeat = CURRENT_TIMESTAMP,
    last_activity = '$activity'
WHERE name = '$agent_name';
EOF
    fi
}

# Check for stale agents and return their tasks to queue
# Usage: check_stale_agents INTERVAL_SECONDS
check_stale_agents() {
    local interval_seconds="${1:-30}"
    local stale_threshold=$((interval_seconds * 2))
    
    sqlite3 "$DB_FILE" <<EOF
-- Find stale agents (no heartbeat for 2x interval)
UPDATE tasks
SET status = 'queued',
    claimed_at = NULL,
    claimed_by = NULL
WHERE status = 'in_progress'
  AND claimed_by IN (
    SELECT name FROM agents
    WHERE last_heartbeat IS NULL
       OR (julianday('now') - julianday(last_heartbeat)) * 86400 > $stale_threshold
  );

UPDATE queue_tasks
SET status = 'queued',
    updated_at = CURRENT_TIMESTAMP
WHERE status = 'in_progress'
  AND task_id IN (
    SELECT id FROM tasks
    WHERE status = 'queued'
      AND claimed_by IS NULL
  );

UPDATE agents
SET status = 'offline'
WHERE last_heartbeat IS NULL
   OR (julianday('now') - julianday(last_heartbeat)) * 86400 > $stale_threshold;
EOF
}

# LIB-005: Announcement creation
# Create an announcement
# Usage: create_announcement TYPE AGENT_NAME TASK_ID MESSAGE [CONTEXT_JSON] [PRIORITY]
create_announcement() {
    local type="$1"
    local agent_name="$2"
    local task_id="$3"
    local message="$4"
    local context="${5:-}"
    local priority="${6:-2}"
    
    if [ -z "$type" ] || [ -z "$message" ]; then
        log_error "create_announcement: type and message required"
        return 1
    fi
    
    # Validate type
    case "$type" in
        work-taken|work-completed|error|question|status)
            ;;
        *)
            log_error "Invalid announcement type: $type"
            return 1
            ;;
    esac
    
    sqlite3 "$DB_FILE" <<EOF
INSERT INTO announcements (type, agent_name, task_id, message, context, priority)
VALUES ('$type', ${agent_name:+'$agent_name'}, ${task_id:+$task_id}, '$message', ${context:+'$context'}, $priority);
EOF
    
    log_info "Announcement created: $type - $message"
}

# LIB-006: Modification date monitoring
# Check if script has been modified since last check
# Usage: check_script_modified SCRIPT_PATH LAST_MODIFIED_FILE
# Returns: 0 if modified, 1 if not modified
check_script_modified() {
    local script_path="$1"
    local last_modified_file="${2:-}"
    
    if [ ! -f "$script_path" ]; then
        log_error "Script not found: $script_path"
        return 1
    fi
    
    local current_mtime
    current_mtime=$(stat -f %m "$script_path" 2>/dev/null || stat -c %Y "$script_path" 2>/dev/null || echo "0")
    
    if [ -z "$last_modified_file" ] || [ ! -f "$last_modified_file" ]; then
        # First check, save mtime
        echo "$current_mtime" > "$last_modified_file"
        return 1
    fi
    
    local last_mtime
    last_mtime=$(cat "$last_modified_file" 2>/dev/null || echo "0")
    
    if [ "$current_mtime" != "$last_mtime" ]; then
        log_warn "Script modified: $script_path (mtime changed from $last_mtime to $current_mtime)"
        return 0
    fi
    
    return 1
}

# LIB-007: Graceful shutdown handler
# Setup signal handlers for graceful shutdown
# Usage: setup_graceful_shutdown CLEANUP_FUNCTION
setup_graceful_shutdown() {
    local cleanup_func="${1:-}"
    
    _shutdown_cleanup() {
        log_info "Shutting down gracefully..."
        if [ -n "$cleanup_func" ] && type "$cleanup_func" >/dev/null 2>&1; then
            $cleanup_func
        fi
        exit 0
    }
    
    trap _shutdown_cleanup SIGINT SIGTERM
}

# Helper: Get queue ID by name
# Usage: get_queue_id QUEUE_NAME
get_queue_id() {
    local queue_name="$1"
    sqlite3 "$DB_FILE" "SELECT id FROM queues WHERE name = '$queue_name';" 2>/dev/null || echo ""
}

# Helper: Get task info
# Usage: get_task_info TASK_ID
get_task_info() {
    local task_id="$1"
    sqlite3 "$DB_FILE" "SELECT id, title, description, status, queue_type, root_work_item_id, parent_task_id FROM tasks WHERE id = $task_id;" 2>/dev/null || echo ""
}

# Helper: Create task with traceability
# Usage: create_task QUEUE_NAME TITLE DESCRIPTION [CONTEXT] [ROOT_WORK_ITEM_ID] [PARENT_TASK_ID] [PRIORITY]
create_task() {
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
    
    # Build work_item_chain
    local work_item_chain="[]"
    if [ -n "$parent_task_id" ]; then
        local parent_chain
        parent_chain=$(sqlite3 "$DB_FILE" "SELECT COALESCE(work_item_chain, '[]') FROM tasks WHERE id = $parent_task_id;" 2>/dev/null || echo "[]")
        work_item_chain="$parent_chain"
    fi
    
    # Escape single quotes in strings
    title=$(echo "$title" | sed "s/'/''/g")
    description=$(echo "$description" | sed "s/'/''/g")
    context=$(echo "$context" | sed "s/'/''/g")
    
    # Build SQL with proper NULL handling
    local root_sql="NULL"
    local parent_sql="NULL"
    local context_sql="NULL"
    
    if [ -n "$root_work_item_id" ]; then
        root_sql="$root_work_item_id"
    fi
    
    if [ -n "$parent_task_id" ]; then
        parent_sql="$parent_task_id"
    fi
    
    if [ -n "$context" ]; then
        context_sql="'$context'"
    fi
    
    # Create task
    local task_id
    task_id=$(sqlite3 "$DB_FILE" <<EOF
INSERT INTO tasks (title, description, context, priority, status, queue_type, root_work_item_id, parent_task_id, work_item_chain)
VALUES ('$title', '$description', $context_sql, $priority, 'queued', '$queue_name', $root_sql, $parent_sql, '$work_item_chain')
RETURNING id;
EOF
)
    
    if [ -z "$task_id" ]; then
        log_error "Failed to create task"
        return 1
    fi
    
    # Create queue_tasks entry
    sqlite3 "$DB_FILE" <<EOF
INSERT INTO queue_tasks (queue_id, task_id, status, priority)
VALUES ($queue_id, $task_id, 'queued', $priority);
EOF
    
    echo "$task_id"
}
