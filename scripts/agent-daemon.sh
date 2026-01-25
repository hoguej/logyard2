#!/bin/bash
# Agent Daemon Manager
# Manages starting and stopping agent daemon instances
# Usage: ./scripts/agent-daemon.sh <command> [args]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"
PID_DIR="/tmp"

# Agent type to script mapping function
get_agent_script() {
    local agent_type="$1"
    case "$agent_type" in
        requirements-research) echo "agent-requirements-research.sh" ;;
        planning) echo "agent-planning.sh" ;;
        execution) echo "agent-execution.sh" ;;
        pre-commit-check) echo "agent-pre-commit-check.sh" ;;
        commit-build) echo "agent-commit-build.sh" ;;
        deploy) echo "agent-deploy.sh" ;;
        e2e-test) echo "agent-e2e-test.sh" ;;
        *) echo "" ;;
    esac
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# Generate unique instance ID
generate_instance_id() {
    date +%Y%m%d_%H%M%S_%N | cut -c1-23
}

# Get PID file path
get_pid_file() {
    local agent_type="$1"
    local instance_id="$2"
    echo "$PID_DIR/agent-${agent_type}-${instance_id}.pid"
}

# Get supervisor PID file path
get_supervisor_pid_file() {
    local agent_type="$1"
    local instance_id="$2"
    echo "$PID_DIR/agent-${agent_type}-${instance_id}.supervisor.pid"
}

# Get stop file path
get_stop_file() {
    local agent_type="$1"
    local instance_id="$2"
    echo "$PID_DIR/agent-${agent_type}-${instance_id}.stop"
}

# Start a daemon instance
cmd_start() {
    local agent_type="$1"
    
    if [ -z "$agent_type" ]; then
        echo -e "${RED}Error: Agent type required${RESET}"
        echo "Usage: $0 start <agent-type>"
        exit 1
    fi
    
    local script_name
    script_name=$(get_agent_script "$agent_type")
    if [ -z "$script_name" ]; then
        echo -e "${RED}Error: Unknown agent type: $agent_type${RESET}"
        exit 1
    fi
    
    local script_path="$SCRIPT_DIR/$script_name"
    if [ ! -f "$script_path" ]; then
        echo -e "${RED}Error: Script not found: $script_path${RESET}"
        exit 1
    fi
    
    # Generate instance ID
    local instance_id
    instance_id=$(generate_instance_id)
    local pid_file
    pid_file=$(get_pid_file "$agent_type" "$instance_id")
    local supervisor_pid_file
    supervisor_pid_file=$(get_supervisor_pid_file "$agent_type" "$instance_id")
    local stop_file
    stop_file=$(get_stop_file "$agent_type" "$instance_id")
    local log_file
    log_file="/tmp/agent-${agent_type}-${instance_id}.log"

    # Reset last-modified tracking so a fresh start doesn't immediately self-terminate
    rm -f "/tmp/agent-${agent_type}-last-modified"
    rm -f "$stop_file" "$supervisor_pid_file"
    
    # Start daemon in background
    echo -e "${CYAN}Starting ${agent_type} agent (instance: ${instance_id})...${RESET}"
    
    # Run supervisor in background, redirect output and stdin, and capture PID
    AGENT_TYPE="$agent_type" INSTANCE_ID="$instance_id" SCRIPT_PATH="$script_path" STOP_FILE="$stop_file" AGENT_MAX_RESTARTS="${AGENT_MAX_RESTARTS:-5}" AGENT_OPEN_CURSOR="${AGENT_OPEN_CURSOR:-0}" \
        nohup bash -c '
        set +e
        restart_count=0
        restart_delay=1
        max_restarts="${AGENT_MAX_RESTARTS:-5}"
        echo "[SUPERVISOR] starting ${AGENT_TYPE} instance ${INSTANCE_ID} (max_restarts=${max_restarts})"
        while true; do
            if [ -f "$STOP_FILE" ]; then
                echo "[SUPERVISOR] stop requested, exiting"
                exit 0
            fi

            start_ts=$(date +%s)
            echo "[SUPERVISOR] launching agent (attempt $((restart_count + 1)))"
            AGENT_DISABLE_SELF_RELOAD=1 AGENT_OPEN_CURSOR="${AGENT_OPEN_CURSOR:-0}" bash "$SCRIPT_PATH" --loop --instance-id "$INSTANCE_ID"
            exit_code=$?
            end_ts=$(date +%s)
            run_seconds=$((end_ts - start_ts))

            if [ -f "$STOP_FILE" ]; then
                echo "[SUPERVISOR] stop requested after agent exit, exiting"
                exit 0
            fi

            # Reset restart counter after a stable run (5 minutes)
            if [ "$run_seconds" -ge 300 ]; then
                restart_count=0
                restart_delay=1
            fi

            restart_count=$((restart_count + 1))
            if [ "$restart_count" -ge "$max_restarts" ]; then
                echo "[SUPERVISOR] max restarts reached (${max_restarts}), exiting"
                exit 1
            fi

            echo "[SUPERVISOR] agent exited with code ${exit_code}; restarting in ${restart_delay}s"
            sleep "$restart_delay"
            restart_delay=$((restart_delay * 2))
            if [ "$restart_delay" -gt 30 ]; then
                restart_delay=30
            fi
        done
        ' < /dev/null >> "$log_file" 2>&1 &
    local supervisor_pid=$!
    
    # Wait a moment to check if process started successfully
    sleep 1
    if ! kill -0 "$supervisor_pid" 2>/dev/null; then
        echo -e "${RED}Error: Supervisor failed to start${RESET}"
        # Check log for errors
        if [ -f "$log_file" ]; then
            echo -e "${YELLOW}Last log entries:${RESET}"
            tail -5 "$log_file" | sed 's/^/  /'
        fi
        exit 1
    fi
    
    # Save supervisor PID to file
    echo "$supervisor_pid" > "$supervisor_pid_file"

    # Attempt to read agent PID if available
    local agent_pid=""
    if [ -f "$pid_file" ]; then
        agent_pid=$(cat "$pid_file" 2>/dev/null || echo "")
    fi
    local pid_sql="NULL"
    if [ -n "$agent_pid" ]; then
        pid_sql="$agent_pid"
    fi
    
    # Register in database
    sqlite3 "$DB_FILE" "
        INSERT INTO agents (name, instance_id, pid, status, last_heartbeat, last_activity)
        VALUES ('$agent_type', '$instance_id', $pid_sql, 'idle', datetime('now'), 'Starting up');
    " 2>/dev/null || {
        echo -e "${YELLOW}Warning: Could not register in database${RESET}"
    }
    
    echo -e "${GREEN}✓ Agent started${RESET}"
    echo -e "  Type: ${agent_type}"
    echo -e "  Instance ID: ${instance_id}"
    echo -e "  Supervisor PID: ${supervisor_pid}"
    if [ -n "$agent_pid" ]; then
        echo -e "  Agent PID: ${agent_pid}"
    fi
    echo -e "  PID file: ${pid_file}"
    echo -e "  Supervisor PID file: ${supervisor_pid_file}"
    echo -e "  Log: ${log_file}"
}

# Stop a daemon instance
cmd_stop() {
    local agent_type="$1"
    local instance_id="$2"
    
    if [ -z "$agent_type" ]; then
        echo -e "${RED}Error: Agent type required${RESET}"
        echo "Usage: $0 stop <agent-type> [instance-id]"
        exit 1
    fi
    
    # If instance_id not provided, find most recent idle instance, or any instance if no idle ones
    if [ -z "$instance_id" ]; then
        instance_id=$(sqlite3 "$DB_FILE" "
            SELECT instance_id 
            FROM agents 
            WHERE name = '$agent_type' 
              AND status = 'idle'
            ORDER BY last_heartbeat DESC 
            LIMIT 1;
        " 2>/dev/null || echo "")
        
        # If no idle instances, try to find any instance (working or idle)
        if [ -z "$instance_id" ]; then
            instance_id=$(sqlite3 "$DB_FILE" "
                SELECT instance_id 
                FROM agents 
                WHERE name = '$agent_type'
                ORDER BY last_heartbeat DESC 
                LIMIT 1;
            " 2>/dev/null || echo "")
        fi
        
        if [ -z "$instance_id" ]; then
            echo -e "${YELLOW}No instances found for $agent_type${RESET}"
            exit 1
        fi
        echo -e "${CYAN}Stopping instance: ${instance_id}${RESET}"
    fi
    
    # Get PID from database
    local pid
    pid=$(sqlite3 "$DB_FILE" "
        SELECT pid FROM agents 
        WHERE name = '$agent_type' AND instance_id = '$instance_id';
    " 2>/dev/null || echo "")
    
    if [ -z "$pid" ] || [ "$pid" = "" ]; then
        echo -e "${YELLOW}Instance not found in database: ${instance_id}${RESET}"
        # Try to find PID file anyway
        local pid_file
        pid_file=$(get_pid_file "$agent_type" "$instance_id")
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file" 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$pid" ] || [ "$pid" = "" ]; then
        echo -e "${RED}Error: Could not find PID for instance ${instance_id}${RESET}"
        exit 1
    fi

    # Signal supervisor to stop restarting
    local stop_file
    stop_file=$(get_stop_file "$agent_type" "$instance_id")
    echo "stop" > "$stop_file"

    # Stop supervisor if present
    local supervisor_pid_file
    supervisor_pid_file=$(get_supervisor_pid_file "$agent_type" "$instance_id")
    local supervisor_pid=""
    if [ -f "$supervisor_pid_file" ]; then
        supervisor_pid=$(cat "$supervisor_pid_file" 2>/dev/null || echo "")
    fi
    if [ -n "$supervisor_pid" ] && kill -0 "$supervisor_pid" 2>/dev/null; then
        echo -e "${CYAN}Stopping supervisor process $supervisor_pid...${RESET}"
        kill -TERM "$supervisor_pid" 2>/dev/null || true
        local s_count=0
        while kill -0 "$supervisor_pid" 2>/dev/null && [ $s_count -lt 10 ]; do
            sleep 0.5
            s_count=$((s_count + 1))
        done
        if kill -0 "$supervisor_pid" 2>/dev/null; then
            echo -e "${YELLOW}Supervisor did not exit gracefully, forcing kill...${RESET}"
            kill -KILL "$supervisor_pid" 2>/dev/null || true
        fi
    fi
    
    # Check if process is running
    if ! kill -0 "$pid" 2>/dev/null; then
        echo -e "${YELLOW}Process $pid is not running, cleaning up...${RESET}"
        # Clean up database and PID file
        sqlite3 "$DB_FILE" "
            DELETE FROM agents 
            WHERE name = '$agent_type' AND instance_id = '$instance_id';
        " 2>/dev/null || true
        local pid_file
        pid_file=$(get_pid_file "$agent_type" "$instance_id")
        rm -f "$pid_file" "$supervisor_pid_file" "$stop_file"
        exit 0
    fi
    
    # Send SIGTERM for graceful shutdown
    echo -e "${CYAN}Stopping agent process $pid...${RESET}"
    kill -TERM "$pid" 2>/dev/null || true
    
    # Wait for process to exit (up to 10 seconds)
    local count=0
    while kill -0 "$pid" 2>/dev/null && [ $count -lt 20 ]; do
        sleep 0.5
        count=$((count + 1))
    done
    
    # If still running, force kill
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${YELLOW}Process did not exit gracefully, forcing kill...${RESET}"
        kill -KILL "$pid" 2>/dev/null || true
        sleep 0.5
    fi
    
    # Clean up
    local pid_file
    pid_file=$(get_pid_file "$agent_type" "$instance_id")
    rm -f "$pid_file" "$supervisor_pid_file" "$stop_file"
    
    sqlite3 "$DB_FILE" "
        DELETE FROM agents 
        WHERE name = '$agent_type' AND instance_id = '$instance_id';
    " 2>/dev/null || true
    
    echo -e "${GREEN}✓ Agent stopped${RESET}"
    echo -e "  Type: ${agent_type}"
    echo -e "  Instance ID: ${instance_id}"
}

# Show status of agent instances
cmd_status() {
    local agent_type="$1"
    
    if [ -z "$agent_type" ]; then
        echo -e "${WHITE}All Agent Instances${RESET}"
        echo -e "${CYAN}──────────────────────────────────────────────────────────────${RESET}"
        sqlite3 -header -column "$DB_FILE" "
            SELECT 
                name as type,
                instance_id,
                pid,
                status,
                last_activity,
                datetime(last_heartbeat) as heartbeat
            FROM agents
            ORDER BY name, created_at DESC;
        "
    else
        echo -e "${WHITE}Agent Instances: ${agent_type}${RESET}"
        echo -e "${CYAN}──────────────────────────────────────────────────────────────${RESET}"
        sqlite3 -header -column "$DB_FILE" "
            SELECT 
                instance_id,
                pid,
                status,
                last_activity,
                datetime(last_heartbeat) as heartbeat
            FROM agents
            WHERE name = '$agent_type'
            ORDER BY created_at DESC;
        "
    fi
}

# Help
show_help() {
    echo -e "${WHITE}Agent Daemon Manager${RESET}"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  start <agent-type>              Start a new daemon instance"
    echo "  stop <agent-type> [instance-id] Stop an instance (or most recent idle)"
    echo "  status [agent-type]             Show running instances"
    echo ""
    echo "Agent Types:"
    echo "  - requirements-research"
    echo "  - planning"
    echo "  - execution"
    echo "  - pre-commit-check"
    echo "  - commit-build"
    echo "  - deploy"
    echo "  - e2e-test"
    echo ""
    echo "Examples:"
    echo "  $0 start requirements-research"
    echo "  $0 stop execution"
    echo "  $0 stop execution 20250119_143022_123456789"
    echo "  $0 status"
    echo ""
}

# Main
case "${1:-}" in
    start)   cmd_start "$2" ;;
    stop)    cmd_stop "$2" "$3" ;;
    status)  cmd_status "$2" ;;
    help|--help|-h) show_help ;;
    *)
        if [ -n "$1" ]; then
            echo -e "${RED}Unknown command: $1${RESET}"
        fi
        show_help
        exit 1
        ;;
esac
