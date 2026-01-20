#!/bin/bash
# Announcement Processor
# Processes announcements from the announce queue and displays them
# Usage: ./scripts/announce-processor.sh [--watch] [--filter TYPE]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

WATCH_MODE=false
FILTER_TYPE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --filter)
            FILTER_TYPE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

display_announcement() {
    local id="$1"
    local type="$2"
    local agent="$3"
    local task_id="$4"
    local message="$5"
    local priority="$6"
    local created_at="$7"
    
    # Color based on type
    local color="$BLUE"
    case "$type" in
        error)
            color="$RED"
            ;;
        work-completed)
            color="$GREEN"
            ;;
        question)
            color="$YELLOW"
            ;;
        work-taken)
            color="$CYAN"
            ;;
    esac
    
    # Priority indicator
    local priority_indicator=""
    case "$priority" in
        5) priority_indicator="[CRITICAL] " ;;
        4) priority_indicator="[HIGH] " ;;
        3) priority_indicator="[MED] " ;;
        2) priority_indicator="" ;;
        1) priority_indicator="[LOW] " ;;
    esac
    
    echo -e "${color}${priority_indicator}[$type]${NC} $message"
    if [ -n "$agent" ] && [ "$agent" != "NULL" ]; then
        echo -e "  ${CYAN}Agent:${NC} $agent"
    fi
    if [ -n "$task_id" ] && [ "$task_id" != "NULL" ]; then
        echo -e "  ${CYAN}Task:${NC} $task_id"
    fi
    echo -e "  ${CYAN}Time:${NC} $created_at"
    echo ""
}

process_announcements() {
    local filter_sql=""
    if [ -n "$FILTER_TYPE" ]; then
        filter_sql="WHERE type = '$FILTER_TYPE'"
    fi
    
    sqlite3 -separator '|' "$DB_FILE" "
        SELECT id, type, COALESCE(agent_name, ''), COALESCE(task_id, ''), message, priority, created_at
        FROM announcements
        $filter_sql
        ORDER BY priority DESC, created_at DESC
        LIMIT 50;
    " | while IFS='|' read -r id type agent task_id message priority created_at; do
        display_announcement "$id" "$type" "$agent" "$task_id" "$message" "$priority" "$created_at"
    done
}

if [ "$WATCH_MODE" = true ]; then
    echo "Watching for new announcements (Ctrl+C to stop)..."
    while true; do
        clear
        echo "=== Recent Announcements ==="
        echo ""
        process_announcements
        sleep 2
    done
else
    process_announcements
fi
