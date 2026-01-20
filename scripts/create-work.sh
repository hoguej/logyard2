#!/bin/bash
# Create Work - Entry point for new feature work
# Usage: ./scripts/create-work.sh "Feature Title" "Feature Description"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

# Source the queue handler library
source "$PROJECT_ROOT/lib/queue-handler.sh"

if [ $# -lt 2 ]; then
    echo "Usage: $0 \"Feature Title\" \"Feature Description\""
    exit 1
fi

TITLE="$1"
DESCRIPTION="$2"

# Escape for SQL
TITLE_ESCAPED=$(echo "$TITLE" | sed "s/'/''/g")
DESCRIPTION_ESCAPED=$(echo "$DESCRIPTION" | sed "s/'/''/g")

echo "Creating new work item..."
echo "  Title: $TITLE"
echo "  Description: $DESCRIPTION"

# WF-005: Create root work item
ROOT_WORK_ITEM_ID=$(sqlite3 "$DB_FILE" <<EOF
INSERT INTO root_work_items (user_input, title, description, status)
VALUES ('$DESCRIPTION_ESCAPED', '$TITLE_ESCAPED', '$DESCRIPTION_ESCAPED', 'pending')
RETURNING id;
EOF
)

if [ -z "$ROOT_WORK_ITEM_ID" ]; then
    log_error "Failed to create root work item"
    exit 1
fi

echo "✓ Root work item created: ID $ROOT_WORK_ITEM_ID"

# WF-003: Create requirements-research task
CONTEXT_JSON="{\"root_work_item_id\": $ROOT_WORK_ITEM_ID, \"original_request\": \"$DESCRIPTION_ESCAPED\"}"
RESEARCH_TASK_ID=$(create_task \
    "requirements-research" \
    "RESEARCH: $TITLE_ESCAPED" \
    "$DESCRIPTION_ESCAPED" \
    "$CONTEXT_JSON" \
    "$ROOT_WORK_ITEM_ID" \
    "" \
    2
)

if [ -z "$RESEARCH_TASK_ID" ]; then
    log_error "Failed to create research task"
    exit 1
fi

echo "✓ Requirements research task created: ID $RESEARCH_TASK_ID"

# Create announcement
create_announcement \
    "work-taken" \
    "system" \
    "$RESEARCH_TASK_ID" \
    "New work item created: $TITLE (Root ID: $ROOT_WORK_ITEM_ID, Task ID: $RESEARCH_TASK_ID)" \
    "{\"root_work_item_id\": $ROOT_WORK_ITEM_ID}" \
    2

echo ""
echo "✓ Work item created successfully!"
echo ""
echo "  Root Work Item ID: $ROOT_WORK_ITEM_ID"
echo "  Research Task ID: $RESEARCH_TASK_ID"
echo "  Status: pending"
echo ""
echo "Next steps:"
echo "  - Start a requirements-research agent to process this work"
echo "  - Check status: sqlite3 $DB_FILE \"SELECT * FROM root_work_items WHERE id = $ROOT_WORK_ITEM_ID;\""
echo "  - View announcements: ./scripts/announce-processor.sh"
