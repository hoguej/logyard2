#!/bin/bash
# Queue Status - Visual progress view for logyard2
# Usage: ./scripts/queue-status.sh
# Watch: watch -n 5 -c ./scripts/queue-status.sh

# Colors
WHITE='\033[1;37m'
GREEN='\033[1;32m'
GRAY='\033[0;90m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

# Function to draw a progress bar (queued vs working only)
draw_queue_bar() {
    local queued=${1:-0}
    local working=${2:-0}
    local width=${3:-25}
    
    # Ensure integers
    queued=$((queued + 0))
    working=$((working + 0))
    local total=$((queued + working))
    
    if [ "$total" -eq 0 ]; then
        printf "${GRAY}"; for ((i=0; i<width; i++)); do printf "░"; done; printf "${RESET}"
        return
    fi
    
    # Calculate widths more accurately
    if [ "$total" -gt 0 ]; then
        working_width=$((working * width / total))
        queued_width=$((queued * width / total))
    else
        working_width=0
        queued_width=0
    fi
    
    # Ensure at least 1 char for working if there are any
    if [ "$working" -gt 0 ] && [ "$working_width" -eq 0 ]; then
        working_width=1
        if [ "$queued_width" -gt 0 ]; then queued_width=$((queued_width - 1)); fi
    fi
    
    # Ensure at least 1 char for queued if there are any
    if [ "$queued" -gt 0 ] && [ "$queued_width" -eq 0 ]; then
        queued_width=1
        if [ "$working_width" -gt 0 ]; then working_width=$((working_width - 1)); fi
    fi
    
    remaining_width=$((width - working_width - queued_width))
    if [ "$remaining_width" -lt 0 ]; then remaining_width=0; fi
    
    # Draw bar using consistent block characters
    printf "${GREEN}"; for ((i=0; i<working_width; i++)); do printf "▓"; done
    printf "${YELLOW}"; for ((i=0; i<queued_width; i++)); do printf "█"; done
    printf "${GRAY}"; for ((i=0; i<remaining_width; i++)); do printf "░"; done
    printf "${RESET}"
}

# Function to get status emoji
get_status() {
    local done=${1:-0}
    local total=${2:-0}
    local in_progress=${3:-0}
    
    if [ "$done" -eq "$total" ] && [ "$total" -gt 0 ]; then
        printf "✅"
    elif [ "$in_progress" -gt 0 ] || [ "$done" -gt 0 ]; then
        printf "🔄"
    else
        printf "⏳"
    fi
}

# Calculate percentage
calc_pct() {
    local done=${1:-0}
    local total=${2:-0}
    if [ "$total" -eq 0 ]; then echo 0; else echo $((done * 100 / total)); fi
}

# Print header
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}              ${WHITE}📊 logyard2 - Queue Status${RESET}                      ${CYAN}║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

if [ ! -f "$DB_FILE" ]; then
    echo -e "${RED}Error: Queue database not found at $DB_FILE${RESET}"
    echo "Run: ./scripts/init-queue.sh"
    exit 1
fi

# Check if multi-queue system exists
queues_exist=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='queues';" 2>/dev/null) || queues_exist=0

if [ "$queues_exist" -gt 0 ]; then
    # Multi-queue system - show queue status
    echo -e "${WHITE}QUEUE STATUS  ${RESET}"
    echo -e "${GRAY}──────────────────────────────────────────────────────────────${RESET}"
    
    # Get status for each queue (queued, in_progress, and completed in last hour)
    sqlite3 "$DB_FILE" "
        SELECT 
            q.name,
            COALESCE(SUM(CASE WHEN qt.status = 'queued' THEN 1 ELSE 0 END), 0) as queued,
            COALESCE(SUM(CASE WHEN qt.status = 'in_progress' THEN 1 ELSE 0 END), 0) as in_progress,
            COALESCE(SUM(CASE WHEN qt.status = 'completed' AND datetime(qt.updated_at) >= datetime('now', '-1 hour') THEN 1 ELSE 0 END), 0) as done_last_hour
        FROM queues q
        LEFT JOIN queue_tasks qt ON q.id = qt.queue_id
        GROUP BY q.id, q.name
        ORDER BY 
            CASE q.name
                WHEN 'requirements-research' THEN 1
                WHEN 'planning' THEN 2
                WHEN 'execution' THEN 3
                WHEN 'pre-commit-check' THEN 4
                WHEN 'commit-build' THEN 5
                WHEN 'deploy' THEN 6
                WHEN 'e2e-test' THEN 7
                WHEN 'announce' THEN 8
                ELSE 9
            END;
    " 2>/dev/null | while IFS='|' read -r queue_name queued in_progress done_last_hour; do
        queued=${queued:-0}
        in_progress=${in_progress:-0}
        done_last_hour=${done_last_hour:-0}
        
        # Format queue name with specific spacing
        # Note: Emojis take 2 terminal columns, so we manually pad to match terminal width
        # Target terminal width: 21 columns (matching Pre-Commit which is correct)
        display_name=""
        case "$queue_name" in
            requirements-research) display_name="📋 Research         " ;;  # 12 -> 21 (9 spaces)
            planning) display_name="📝 Planning         " ;;  # 12 -> 21 (9 spaces)
            execution) display_name="⚙️  Execution        " ;;  # 21 -> 23 (8 spaces, 2 more than original 6)
            pre-commit-check) display_name="✅ Pre-Commit       " ;;  # 14 -> 21 (7 spaces) - CORRECT
            commit-build) display_name="🔨 Commit/Build     " ;;  # 15 -> 21 (6 spaces) - reduced padding
            deploy) display_name="🚀 Deploy           " ;;  # 10 -> 21 (11 spaces)
            e2e-test) display_name="🧪 E2E Test         " ;;  # 12 -> 21 (9 spaces)
            announce) display_name="📢 Announce         " ;;  # 12 -> 21 (9 spaces)
            *) display_name="$queue_name" ;;
        esac
        
        # Print without additional padding since we manually padded above
        printf "%s" "$display_name"
        draw_queue_bar "$queued" "$in_progress" 22
        printf " Q:%d W:%d" "$queued" "$in_progress"
        if [ "$done_last_hour" -gt 0 ]; then
            printf " ${GRAY}✓:%d${RESET}" "$done_last_hour"
        fi
        printf "\n"
    done
    
    echo ""
    
    # Show root work items (in progress or recently finished)
    root_work_items_exist=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='root_work_items';" 2>/dev/null) || root_work_items_exist=0
    
    if [ "$root_work_items_exist" -gt 0 ]; then
        # Count items in progress or completed in last hour
        relevant_work=$(sqlite3 "$DB_FILE" "
            SELECT COUNT(*) FROM root_work_items 
            WHERE status NOT IN ('completed', 'failed', 'cancelled')
            OR (status = 'completed' AND completed_at >= datetime('now', '-1 hour'))
            OR (status = 'failed' AND failed_at >= datetime('now', '-1 hour'));
        " 2>/dev/null) || relevant_work=0
        
        if [ "$relevant_work" -gt 0 ]; then
            echo -e "${WHITE}ROOT WORK ITEMS${RESET}"
            echo -e "${GRAY}──────────────────────────────────────────────────────────────${RESET}"
            
            sqlite3 "$DB_FILE" "
                SELECT 
                    CASE status
                        WHEN 'pending' THEN '⏳'
                        WHEN 'researching' THEN '🔍'
                        WHEN 'planning' THEN '📝'
                        WHEN 'executing' THEN '⚙️ '
                        WHEN 'checking' THEN '✅'
                        WHEN 'building' THEN '🔨'
                        WHEN 'deploying' THEN '🚀'
                        WHEN 'testing' THEN '🧪'
                        WHEN 'completed' THEN '✅'
                        WHEN 'failed' THEN '❌'
                        ELSE '❓'
                    END || ' ' ||
                    '[' || id || '] ' ||
                    printf('%-40s', substr(title, 1, 40)) ||
                    ' [' || status || ']' ||
                    CASE 
                        WHEN status = 'completed' AND completed_at IS NOT NULL AND datetime(completed_at) >= datetime('now', '-1 hour') THEN 
                            ' (' || strftime('%H:%M', completed_at) || ')'
                        WHEN status = 'failed' AND failed_at IS NOT NULL AND datetime(failed_at) >= datetime('now', '-1 hour') THEN 
                            ' (' || strftime('%H:%M', failed_at) || ')'
                        ELSE ''
                    END
                FROM root_work_items
                WHERE status NOT IN ('completed', 'failed', 'cancelled')
                OR (status = 'completed' AND datetime(completed_at) >= datetime('now', '-1 hour'))
                OR (status = 'failed' AND datetime(failed_at) >= datetime('now', '-1 hour'))
                ORDER BY 
                    CASE status
                        WHEN 'executing' THEN 1
                        WHEN 'checking' THEN 2
                        WHEN 'building' THEN 3
                        WHEN 'deploying' THEN 4
                        WHEN 'testing' THEN 5
                        WHEN 'planning' THEN 6
                        WHEN 'researching' THEN 7
                        WHEN 'pending' THEN 8
                        WHEN 'completed' THEN 9
                        WHEN 'failed' THEN 10
                        ELSE 11
                    END,
                    created_at DESC;
            " 2>/dev/null | while read -r line; do
                echo "  $line"
            done
            echo ""
        fi
    fi
fi

# Legacy priority-based progress (only show if multi-queue system not active)
if [ "$queues_exist" -eq 0 ]; then
    # Priority-based progress (Critical=5, High=4, Medium=3, Normal=2, Low=1)
    p5_done=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 5 AND status = 'completed';" 2>/dev/null | tr -d '[:space:]') || p5_done=0
    p5_in_prog=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 5 AND status = 'in_progress';" 2>/dev/null | tr -d '[:space:]') || p5_in_prog=0
    p5_total=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 5;" 2>/dev/null | tr -d '[:space:]') || p5_total=0

    p4_done=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 4 AND status = 'completed';" 2>/dev/null | tr -d '[:space:]') || p4_done=0
    p4_in_prog=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 4 AND status = 'in_progress';" 2>/dev/null | tr -d '[:space:]') || p4_in_prog=0
    p4_total=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 4;" 2>/dev/null | tr -d '[:space:]') || p4_total=0

    p3_done=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 3 AND status = 'completed';" 2>/dev/null | tr -d '[:space:]') || p3_done=0
    p3_in_prog=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 3 AND status = 'in_progress';" 2>/dev/null | tr -d '[:space:]') || p3_in_prog=0
    p3_total=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 3;" 2>/dev/null | tr -d '[:space:]') || p3_total=0

    p2_done=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 2 AND status = 'completed';" 2>/dev/null | tr -d '[:space:]') || p2_done=0
    p2_in_prog=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 2 AND status = 'in_progress';" 2>/dev/null | tr -d '[:space:]') || p2_in_prog=0
    p2_total=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 2;" 2>/dev/null | tr -d '[:space:]') || p2_total=0

    p1_done=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 1 AND status = 'completed';" 2>/dev/null | tr -d '[:space:]') || p1_done=0
    p1_in_prog=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 1 AND status = 'in_progress';" 2>/dev/null | tr -d '[:space:]') || p1_in_prog=0
    p1_total=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE priority = 1;" 2>/dev/null | tr -d '[:space:]') || p1_total=0

    # Ensure all are integers
    p5_done=${p5_done:-0}; p5_in_prog=${p5_in_prog:-0}; p5_total=${p5_total:-0}
    p4_done=${p4_done:-0}; p4_in_prog=${p4_in_prog:-0}; p4_total=${p4_total:-0}
    p3_done=${p3_done:-0}; p3_in_prog=${p3_in_prog:-0}; p3_total=${p3_total:-0}
    p2_done=${p2_done:-0}; p2_in_prog=${p2_in_prog:-0}; p2_total=${p2_total:-0}
    p1_done=${p1_done:-0}; p1_in_prog=${p1_in_prog:-0}; p1_total=${p1_total:-0}

    # Calculate overall
    total_done=$((p5_done + p4_done + p3_done + p2_done + p1_done))
    total_in_prog=$((p5_in_prog + p4_in_prog + p3_in_prog + p2_in_prog + p1_in_prog))
    total_tasks=$((p5_total + p4_total + p3_total + p2_total + p1_total))

    # Print priority progress
    echo -e "${WHITE}PRIORITY PROGRESS${RESET}"
    echo -e "${GRAY}──────────────────────────────────────────────────────────────${RESET}"

    printf "🔴 Critical (P5)      "
    draw_bar "$p5_done" "$p5_in_prog" "$p5_total"
    printf " %3d%% " "$(calc_pct "$p5_done" "$p5_total")"
    get_status "$p5_done" "$p5_total" "$p5_in_prog"
    printf " (%d/%d)\n" "$p5_done" "$p5_total"

    printf "🟠 High (P4)          "
    draw_bar "$p4_done" "$p4_in_prog" "$p4_total"
    printf " %3d%% " "$(calc_pct "$p4_done" "$p4_total")"
    get_status "$p4_done" "$p4_total" "$p4_in_prog"
    printf " (%d/%d)\n" "$p4_done" "$p4_total"

    printf "🟡 Medium (P3)        "
    draw_bar "$p3_done" "$p3_in_prog" "$p3_total"
    printf " %3d%% " "$(calc_pct "$p3_done" "$p3_total")"
    get_status "$p3_done" "$p3_total" "$p3_in_prog"
    printf " (%d/%d)\n" "$p3_done" "$p3_total"

    printf "🔵 Normal (P2)        "
    draw_bar "$p2_done" "$p2_in_prog" "$p2_total"
    printf " %3d%% " "$(calc_pct "$p2_done" "$p2_total")"
    get_status "$p2_done" "$p2_total" "$p2_in_prog"
    printf " (%d/%d)\n" "$p2_done" "$p2_total"

    printf "🟢 Low (P1)           "
    draw_bar "$p1_done" "$p1_in_prog" "$p1_total"
    printf " %3d%% " "$(calc_pct "$p1_done" "$p1_total")"
    get_status "$p1_done" "$p1_total" "$p1_in_prog"
    printf " (%d/%d)\n" "$p1_done" "$p1_total"

    echo ""
    printf "${CYAN}Overall                ${RESET}"
    draw_bar "$total_done" "$total_in_prog" "$total_tasks"
    printf " %3d%%\n" "$(calc_pct "$total_done" "$total_tasks")"
    echo ""
fi

# Agent Status by Script Type
agents_exist=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='agents';" 2>/dev/null) || agents_exist=0

if [ "$agents_exist" -gt 0 ] && [ "$queues_exist" -gt 0 ]; then
    echo -e "${WHITE}RUNNING AGENTS${RESET}"
    echo -e "${GRAY}──────────────────────────────────────────────────────────────${RESET}"
    
    # List all agents in workflow order, showing count for each
    declare -a agent_scripts=(
        "requirements-research:agent-requirements-research.sh"
        "planning:agent-planning.sh"
        "execution:agent-execution.sh"
        "pre-commit-check:agent-pre-commit-check.sh"
        "commit-build:agent-commit-build.sh"
        "deploy:agent-deploy.sh"
        "e2e-test:agent-e2e-test.sh"
    )
    
    for agent_info in "${agent_scripts[@]}"; do
        queue_name="${agent_info%%:*}"
        script_name="${agent_info##*:}"
        
        # Count agents for this queue type
        working=$(sqlite3 "$DB_FILE" "
            SELECT COUNT(*) FROM agents 
            WHERE name = '$queue_name' 
            AND status = 'working' 
            AND last_heartbeat >= datetime('now', '-30 minutes');
        " 2>/dev/null || echo "0")
        
        idle=$(sqlite3 "$DB_FILE" "
            SELECT COUNT(*) FROM agents 
            WHERE name = '$queue_name' 
            AND status = 'idle' 
            AND last_heartbeat >= datetime('now', '-30 minutes');
        " 2>/dev/null || echo "0")
        
        working=${working:-0}
        idle=${idle:-0}
        total=$((working + idle))
        
        printf "  %-35s " "$script_name"
        printf "($total)"
        if [ "$working" -gt 0 ]; then
            printf " ${GREEN}🟢 %d working${RESET}" "$working"
        fi
        if [ "$idle" -gt 0 ]; then
            if [ "$working" -gt 0 ]; then
                printf ", "
            fi
            printf "${YELLOW}🟡 %d idle${RESET}" "$idle"
        fi
        printf "\n"
    done
    echo ""
fi

# Show task details (works for both old and new systems)
if [ "$queues_exist" -eq 0 ]; then
    echo -e "${WHITE}TASK QUEUE${RESET}"
    echo -e "${GRAY}──────────────────────────────────────────────────────────────${RESET}"

    in_progress=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE status = 'in_progress';" 2>/dev/null | tr -d '[:space:]') || in_progress=0
    queued=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE status = 'queued';" 2>/dev/null | tr -d '[:space:]') || queued=0
    failed=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE status = 'failed';" 2>/dev/null | tr -d '[:space:]') || failed=0
    completed=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE status = 'completed';" 2>/dev/null | tr -d '[:space:]') || completed=0

    in_progress=${in_progress:-0}
    queued=${queued:-0}
    failed=${failed:-0}
    completed=${completed:-0}

    echo -e "${GREEN}▓${RESET} Working: $in_progress  ${YELLOW}◆${RESET} Queued: $queued  ${WHITE}✓${RESET} Done: $completed  ${RED}✗${RESET} Failed: $failed"
    echo ""

    if [ "$in_progress" -gt 0 ]; then
        echo -e "${GREEN}Currently Working On:${RESET}"
        sqlite3 "$DB_FILE" "
            SELECT 
                '  ' || 
                CASE 
                    WHEN claimed_by IS NOT NULL THEN '🤖 '
                    ELSE '❓ '
                END ||
                printf('%-14s', COALESCE(claimed_by, 'UNASSIGNED')) || 
                ' │ [P' || priority || '] ' || title
            FROM tasks 
            WHERE status = 'in_progress' 
            ORDER BY claimed_by, priority DESC 
            LIMIT 10;
        " 2>/dev/null
        echo ""
    fi

    if [ "$queued" -gt 0 ]; then
        echo -e "${YELLOW}Next Up (by priority):${RESET}"
        sqlite3 "$DB_FILE" "SELECT '  [P' || priority || '] ' || title FROM tasks WHERE status = 'queued' ORDER BY priority DESC, created_at LIMIT 5;" 2>/dev/null
        echo ""
    fi

    if [ "$failed" -gt 0 ]; then
        echo -e "${RED}Failed Tasks:${RESET}"
        sqlite3 "$DB_FILE" "SELECT '  ✗ ' || title || ' - ' || COALESCE(error, 'Unknown error') FROM tasks WHERE status = 'failed' LIMIT 5;" 2>/dev/null
        echo ""
    fi
fi

# Show last 5 announcements
announcements_exist=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='announcements';" 2>/dev/null) || announcements_exist=0

if [ "$announcements_exist" -gt 0 ]; then
    announcement_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM announcements;" 2>/dev/null) || announcement_count=0
    
    if [ "$announcement_count" -gt 0 ]; then
        echo -e "${WHITE}RECENT ANNOUNCEMENTS${RESET}"
        echo -e "${GRAY}──────────────────────────────────────────────────────────────${RESET}"
        
        sqlite3 "$DB_FILE" "
            SELECT 
                CASE type
                    WHEN 'error' THEN '🔴'
                    WHEN 'work-completed' THEN '✅'
                    WHEN 'work-taken' THEN '🟢'
                    WHEN 'question' THEN '❓'
                    WHEN 'status' THEN 'ℹ️ '
                    ELSE '📢'
                END || ' ' ||
                COALESCE(agent_name, 'system') || ': ' ||
                substr(message, 1, 60) ||
                CASE WHEN length(message) > 60 THEN '...' ELSE '' END ||
                ' (' || strftime('%H:%M', created_at) || ')'
            FROM announcements
            ORDER BY created_at DESC
            LIMIT 5;
        " 2>/dev/null | while read -r line; do
            echo "  $line"
        done
        echo ""
    fi
fi

# Legend
echo -e "${GRAY}──────────────────────────────────────────────────────────────${RESET}"
echo -e "Legend: ${GREEN}▓${RESET} Working  ${YELLOW}█${RESET} Queued  ${GRAY}░${RESET} Empty"
echo -e "${GRAY}Updated: $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""
