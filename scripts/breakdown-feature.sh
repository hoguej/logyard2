#!/bin/bash
# Break down a high-level feature into workflow tasks and enqueue them
# Usage: ./scripts/breakdown-feature.sh <feature-title> <feature-description>

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <feature-title> <feature-description>"
    echo "Example: $0 'User Authentication' 'Add JWT-based authentication system with login/logout'"
    exit 1
fi

FEATURE_TITLE="$1"
FEATURE_DESC="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

# Ensure database exists
if [ ! -f "$DB_FILE" ]; then
    echo "Queue database not found. Initializing..."
    bash "$SCRIPT_DIR/init-queue.sh"
fi

# Escape single quotes for SQL
FEATURE_TITLE_ESC=$(echo "$FEATURE_TITLE" | sed "s/'/''/g")
FEATURE_DESC_ESC=$(echo "$FEATURE_DESC" | sed "s/'/''/g")

# Create context JSON for the feature
CONTEXT_JSON="{\"feature_title\": \"$FEATURE_TITLE\", \"feature_description\": \"$FEATURE_DESC\", \"workflow_type\": \"feature_breakdown\"}"

echo "Breaking down feature: $FEATURE_TITLE"
echo "Description: $FEATURE_DESC"
echo ""
echo "Creating workflow tasks..."

# Task 1: Research the task (Priority 4 - High, needs to be done first)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('RESEARCH: $FEATURE_TITLE_ESC', 'Research the requirements, existing codebase, and best practices for: $FEATURE_DESC_ESC', '$CONTEXT_JSON', 4);
"

# Task 2: Ask clarifying questions (Priority 4 - High, needs user input early)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('CLARIFY: $FEATURE_TITLE_ESC', 'Ask the user clarifying questions about: $FEATURE_DESC_ESC. Review research findings and identify gaps or ambiguities.', '$CONTEXT_JSON', 4);
"

# Task 3: Break task down into smaller pieces (Priority 3 - Medium, after research/clarify)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('BREAKDOWN: $FEATURE_TITLE_ESC', 'Break down the feature into smaller, manageable subtasks. Create a detailed task list.', '$CONTEXT_JSON', 3);
"

# Task 4: Design the coding work (Priority 3 - Medium, after breakdown)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('DESIGN: $FEATURE_TITLE_ESC', 'Design the coding work: identify what files will change or be created, high-level architecture, data structures, APIs, etc.', '$CONTEXT_JSON', 3);
"

# Task 4.1: Plan the work (Priority 3 - Medium, after design)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('PLAN: $FEATURE_TITLE_ESC', 'Create a detailed implementation plan based on the design. Sequence the work, identify dependencies.', '$CONTEXT_JSON', 3);
"

# Task 5: Execute the coding work (Priority 2 - Normal, after planning)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('CODE: $FEATURE_TITLE_ESC', 'Execute the coding work according to the plan. Make all changes in your workspace.', '$CONTEXT_JSON', 2);
"

# Task 6: Write tests (Priority 2 - Normal, after coding)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('TESTS: Write tests for $FEATURE_TITLE_ESC', 'Write comprehensive tests for the feature: unit tests, integration tests, edge cases.', '$CONTEXT_JSON', 2);
"

# Task 7: Execute tests (Priority 2 - Normal, after writing tests)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('TEST: Run tests for $FEATURE_TITLE_ESC', 'Execute the test suite and verify all tests pass.', '$CONTEXT_JSON', 2);
"

# Task 8: Fix failing tests (Priority 3 - Medium, only if tests fail)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('FIX: Fix failing tests for $FEATURE_TITLE_ESC', 'Fix any failing tests. Investigate failures and update code or tests as needed.', '$CONTEXT_JSON', 3);
"

# Task 9: Make new tasks when something is wrong (Priority 4 - High, for bugs)
# This is a meta-task that agents should do during execution
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('META: Create tasks for bugs/issues found during $FEATURE_TITLE_ESC', 'If you notice bugs in existing code or issues during implementation, create new tasks for them. Do not fix them as part of this feature unless critical.', '$CONTEXT_JSON', 4);
"

# Task 10: Commit code and create PR (Priority 2 - Normal, after tests pass)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('PR: Commit and create PR for $FEATURE_TITLE_ESC', 'Commit the code with a good commit message, push the feature branch, and create a pull request. Use /commit-and-pr command.', '$CONTEXT_JSON', 2);
"

# Task 11: Provide feedback to user (Priority 2 - Normal, final step)
sqlite3 "$DB_FILE" "
INSERT INTO tasks (title, description, context, priority) VALUES 
('FEEDBACK: Provide summary for $FEATURE_TITLE_ESC', 'Provide feedback to the user: what was done, how to test it, any other tasks that were created in the process, link to PR.', '$CONTEXT_JSON', 2);
"

echo "✓ Created 11 workflow tasks for: $FEATURE_TITLE"
echo ""
echo "Task breakdown:"
echo "  1. RESEARCH - Research the task (P4)"
echo "  2. CLARIFY - Ask clarifying questions (P4)"
echo "  3. BREAKDOWN - Break task into smaller pieces (P3)"
echo "  4. DESIGN - Design the coding work (P3)"
echo "  5. PLAN - Plan the work (P3)"
echo "  6. CODE - Execute the coding work (P2)"
echo "  7. TESTS - Write tests (P2)"
echo "  8. TEST - Execute tests (P2)"
echo "  9. FIX - Fix failing tests (P3)"
echo "  10. META - Create tasks for bugs/issues (P4)"
echo "  11. PR - Commit and create PR (P2)"
echo "  12. FEEDBACK - Provide summary (P2)"
echo ""
echo "View queue: ./scripts/queue-status.sh"
echo "Claim a task: ./scripts/agent-queue.sh claim <agent-name>"
