#!/bin/bash
# Agent Queue Management for logyard2
# Usage: ./scripts/agent-queue.sh <command> [args]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# Ensure database exists
if [ ! -f "$DB_FILE" ]; then
    echo -e "${YELLOW}Queue database not found. Initializing...${RESET}"
    bash "$SCRIPT_DIR/init-queue.sh"
fi

cmd_register() {
    local name="$1"
    local workspace="${2:-$PROJECT_ROOT}"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Agent name required${RESET}"
        echo "Usage: $0 register <agent-name> [workspace-path]"
        exit 1
    fi
    
    # Insert or update agent
    sqlite3 "$DB_FILE" "
        INSERT INTO agents (name, workspace_path, status, last_heartbeat)
        VALUES ('$name', '$workspace', 'idle', datetime('now'))
        ON CONFLICT(name) DO UPDATE SET
            workspace_path = '$workspace',
            status = 'idle',
            last_heartbeat = datetime('now');
    "
    
    echo -e "${GREEN}✓ Agent '$name' registered${RESET}"
    echo -e "  Workspace: $workspace"
}

cmd_claim() {
    local name="$1"
    local task_title="$2"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Agent name required${RESET}"
        echo "Usage: $0 claim <agent-name> [task-title]"
        exit 1
    fi
    
    # Ensure agent is registered
    local agent_exists
    agent_exists=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM agents WHERE name = '$name';")
    if [ "$agent_exists" -eq 0 ]; then
        echo -e "${YELLOW}Agent '$name' not registered, registering now...${RESET}"
        cmd_register "$name"
    fi
    
    local task_id
    local claimed_title
    
    if [ -n "$task_title" ]; then
        # Claim specific task
        task_id=$(sqlite3 "$DB_FILE" "
            SELECT id FROM tasks 
            WHERE title LIKE '%$task_title%' AND status = 'queued'
            ORDER BY priority DESC LIMIT 1;
        ")
    else
        # Claim next available task
        task_id=$(sqlite3 "$DB_FILE" "
            SELECT id FROM tasks 
            WHERE status = 'queued'
            ORDER BY priority DESC, created_at ASC LIMIT 1;
        ")
    fi
    
    if [ -z "$task_id" ]; then
        echo -e "${YELLOW}No tasks available to claim${RESET}"
        return 1
    fi
    
    # Claim the task
    sqlite3 "$DB_FILE" "
        UPDATE tasks SET 
            status = 'in_progress',
            claimed_by = '$name',
            claimed_at = datetime('now')
        WHERE id = $task_id;
        
        UPDATE agents SET
            current_task_id = $task_id,
            status = 'working',
            last_heartbeat = datetime('now'),
            last_activity = 'Claimed task'
        WHERE name = '$name';
    "
    
    claimed_title=$(sqlite3 "$DB_FILE" "SELECT title FROM tasks WHERE id = $task_id;")
    
    echo -e "${GREEN}✓ Agent '$name' claimed task:${RESET}"
    echo -e "  ${WHITE}$claimed_title${RESET}"
    echo ""
    echo -e "${CYAN}Remember to identify yourself in commits and messages!${RESET}"
    echo -e "  Commit prefix: [$name] Description"
}

cmd_release() {
    local name="$1"
    local reason="${2:-Released by agent}"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Agent name required${RESET}"
        exit 1
    fi
    
    local task_id
    task_id=$(sqlite3 "$DB_FILE" "SELECT current_task_id FROM agents WHERE name = '$name';")
    
    if [ -z "$task_id" ] || [ "$task_id" = "" ]; then
        echo -e "${YELLOW}Agent '$name' has no claimed task${RESET}"
        return 0
    fi
    
    sqlite3 "$DB_FILE" "
        UPDATE tasks SET 
            status = 'queued',
            claimed_by = NULL,
            claimed_at = NULL,
            error = '$reason'
        WHERE id = $task_id;
        
        UPDATE agents SET
            current_task_id = NULL,
            status = 'idle',
            last_heartbeat = datetime('now'),
            last_activity = 'Released task'
        WHERE name = '$name';
    "
    
    echo -e "${YELLOW}✓ Agent '$name' released task back to queue${RESET}"
}

cmd_complete() {
    local name="$1"
    local result="${2:-Completed}"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Agent name required${RESET}"
        exit 1
    fi
    
    local task_id
    task_id=$(sqlite3 "$DB_FILE" "SELECT current_task_id FROM agents WHERE name = '$name';")
    
    if [ -z "$task_id" ] || [ "$task_id" = "" ]; then
        echo -e "${YELLOW}Agent '$name' has no claimed task${RESET}"
        return 0
    fi
    
    sqlite3 "$DB_FILE" "
        UPDATE tasks SET 
            status = 'completed',
            completed_at = datetime('now'),
            result = '$result'
        WHERE id = $task_id;
        
        UPDATE agents SET
            current_task_id = NULL,
            status = 'idle',
            last_heartbeat = datetime('now'),
            last_activity = 'Completed task'
        WHERE name = '$name';
    "
    
    local title
    title=$(sqlite3 "$DB_FILE" "SELECT title FROM tasks WHERE id = $task_id;")
    echo -e "${GREEN}✓ Agent '$name' completed: $title${RESET}"
}

cmd_heartbeat() {
    local name="$1"
    local activity="${2:-Working}"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Agent name required${RESET}"
        exit 1
    fi
    
    sqlite3 "$DB_FILE" "
        UPDATE agents SET
            last_heartbeat = datetime('now'),
            last_activity = '$activity'
        WHERE name = '$name';
    "
}

cmd_status() {
    local name="$1"
    
    if [ -n "$name" ]; then
        # Show specific agent
        echo -e "${WHITE}Agent: $name${RESET}"
        sqlite3 -header -column "$DB_FILE" "
            SELECT 
                a.status,
                a.workspace_path as workspace,
                t.title as current_task,
                a.last_activity,
                a.last_heartbeat
            FROM agents a
            LEFT JOIN tasks t ON a.current_task_id = t.id
            WHERE a.name = '$name';
        "
    else
        # Show all agents
        echo -e "${WHITE}All Registered Agents${RESET}"
        echo -e "${CYAN}──────────────────────────────────────────────────────────────${RESET}"
        sqlite3 -header -column "$DB_FILE" "
            SELECT 
                a.name,
                a.status,
                COALESCE(t.title, '-') as current_task,
                a.last_activity,
                strftime('%H:%M:%S', a.last_heartbeat) as heartbeat
            FROM agents a
            LEFT JOIN tasks t ON a.current_task_id = t.id
            ORDER BY a.status DESC, a.name;
        "
    fi
}

cmd_list() {
    echo -e "${WHITE}Registered Agents${RESET}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${RESET}"
    sqlite3 "$DB_FILE" "
        SELECT 
            CASE status 
                WHEN 'working' THEN '🟢'
                WHEN 'idle' THEN '🟡'
                ELSE '⚫'
            END || ' ' || name || 
            CASE WHEN current_task_id IS NOT NULL 
                THEN ' → ' || (SELECT title FROM tasks WHERE id = current_task_id)
                ELSE ''
            END
        FROM agents
        ORDER BY status DESC, name;
    "
    echo ""
}

cmd_whoami() {
    if [ -n "$AGENT_NAME" ]; then
        echo -e "${GREEN}You are: $AGENT_NAME${RESET}"
        cmd_status "$AGENT_NAME"
    else
        echo -e "${YELLOW}AGENT_NAME environment variable not set${RESET}"
        echo "Set it with: export AGENT_NAME='your-agent-name'"
    fi
}

cmd_add() {
    local title="$1"
    local description="$2"
    local priority="${3:-2}"
    
    if [ -z "$title" ]; then
        echo -e "${RED}Error: Task title required${RESET}"
        echo "Usage: $0 add <title> [description] [priority]"
        exit 1
    fi
    
    # Escape single quotes for SQL
    title=$(echo "$title" | sed "s/'/''/g")
    description=$(echo "$description" | sed "s/'/''/g")
    
    local task_id
    task_id=$(sqlite3 "$DB_FILE" "
        INSERT INTO tasks (title, description, priority) 
        VALUES ('$title', '$description', $priority);
        SELECT last_insert_rowid();
    ")
    
    echo -e "${GREEN}✓ Task added:${RESET}"
    echo -e "  ${WHITE}ID: $task_id${RESET}"
    echo -e "  ${WHITE}Title: $title${RESET}"
    echo -e "  ${WHITE}Priority: $priority${RESET}"
}

# Help
show_help() {
    echo -e "${WHITE}Agent Queue Management${RESET}"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  register <name> [workspace]  Register an agent with optional workspace path"
    echo "  claim <name> [task]          Claim next task or specific task by title"
    echo "  release <name>               Release current task back to queue"
    echo "  complete <name> [result]     Mark current task as complete"
    echo "  heartbeat <name> [activity]  Update agent heartbeat"
    echo "  add <title> [desc] [priority] Add a new task to the queue"
    echo "  status [name]                Show agent status (all if no name)"
    echo "  list                         List all agents with current tasks"
    echo "  whoami                       Show current agent (from AGENT_NAME env)"
    echo ""
    echo "Environment:"
    echo "  AGENT_NAME                   Set your agent name for whoami command"
    echo ""
    echo "Examples:"
    echo "  $0 register alpha /Users/me/workspace1"
    echo "  $0 claim alpha"
    echo "  $0 complete alpha 'Merged PR #42'"
    echo "  $0 add 'Fix bug' 'Description here' 3"
    echo ""
}

# Main
case "${1:-}" in
    register)   cmd_register "$2" "$3" ;;
    claim)      cmd_claim "$2" "$3" ;;
    release)    cmd_release "$2" "$3" ;;
    complete)   cmd_complete "$2" "$3" ;;
    heartbeat)  cmd_heartbeat "$2" "$3" ;;
    add)        cmd_add "$2" "$3" "$4" ;;
    status)     cmd_status "$2" ;;
    list)       cmd_list ;;
    whoami)     cmd_whoami ;;
    help|--help|-h) show_help ;;
    *)
        if [ -n "$1" ]; then
            echo -e "${RED}Unknown command: $1${RESET}"
        fi
        show_help
        exit 1
        ;;
esac
