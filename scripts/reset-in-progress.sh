#!/bin/bash
# Reset all tasks marked as "in_progress" back to "queued"
# Usage: ./scripts/reset-in-progress.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

if [ ! -f "$DB_FILE" ]; then
    echo -e "${RED}Error: Queue database not found at $DB_FILE${RESET}"
    exit 1
fi

# Count tasks in progress
IN_PROGRESS_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM tasks WHERE status = 'in_progress';" 2>/dev/null || echo "0")

if [ "$IN_PROGRESS_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No tasks are currently in progress${RESET}"
    exit 0
fi

echo "Found $IN_PROGRESS_COUNT task(s) marked as in_progress"
echo ""
echo "Tasks to be reset:"
sqlite3 "$DB_FILE" "SELECT id, title, claimed_by FROM tasks WHERE status = 'in_progress';" 2>/dev/null | while IFS='|' read -r id title claimed_by; do
    echo "  [$id] $title (claimed by: ${claimed_by:-none})"
done

echo ""
read -p "Reset all in_progress tasks back to queued? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Reset all in_progress tasks to queued
sqlite3 "$DB_FILE" "
UPDATE tasks SET 
    status = 'queued',
    claimed_by = NULL,
    claimed_at = NULL
WHERE status = 'in_progress';

UPDATE agents SET
    current_task_id = NULL,
    status = 'idle',
    last_activity = 'Task reset to queued'
WHERE status = 'working';
"

echo -e "${GREEN}✓ Reset $IN_PROGRESS_COUNT task(s) back to queued${RESET}"
echo -e "${GREEN}✓ Updated agent statuses to idle${RESET}"
