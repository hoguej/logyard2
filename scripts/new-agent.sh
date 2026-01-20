#!/bin/bash
# Create a new agent workspace, register it, claim a task, and set up for work
# Usage: ./scripts/new-agent.sh <agent-name> [context-description] [task-title-pattern]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <agent-name> [context-description] [task-title-pattern]"
    echo "Example: $0 alpha 'Working on authentication features' 'RESEARCH'"
    exit 1
fi

AGENT_NAME="$1"
CONTEXT_DESC="${2:-Agent workspace for $AGENT_NAME}"
TASK_PATTERN="$3"
REPO_URL="https://github.com/hoguej/logyard2.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Generate unique workspace name with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WORKSPACE_NAME="agent_${AGENT_NAME}_${TIMESTAMP}"
WORKSPACE_PATH="workspaces/${WORKSPACE_NAME}"

# Create workspaces directory if it doesn't exist
mkdir -p workspaces

# Check if workspace already exists
if [ -d "$WORKSPACE_PATH" ]; then
    echo "Error: Workspace $WORKSPACE_PATH already exists"
    exit 1
fi

echo "Creating agent workspace: $WORKSPACE_NAME"
echo "Agent: $AGENT_NAME"
echo "Context: $CONTEXT_DESC"
echo ""

# Clone the repository
echo "Cloning repository..."
git clone "$REPO_URL" "$WORKSPACE_PATH"

# Navigate to workspace
cd "$WORKSPACE_PATH"

# Create initial .context.json file
cat > .context.json <<EOF
{
  "workspace_name": "$WORKSPACE_NAME",
  "agent_name": "$AGENT_NAME",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "context": "$CONTEXT_DESC",
  "created_by": "$(whoami)"
}
EOF

# Initialize queue database if it doesn't exist
DB_FILE="$PROJECT_ROOT/.agent-queue.db"
if [ ! -f "$DB_FILE" ]; then
    echo "Initializing queue database..."
    bash "$SCRIPT_DIR/init-queue.sh"
fi

# Register the agent
echo "Registering agent in queue..."
bash "$SCRIPT_DIR/agent-queue.sh" register "$AGENT_NAME" "$(realpath "$WORKSPACE_PATH")"

# Claim a task
echo ""
echo "Claiming a task from queue..."
if [ -n "$TASK_PATTERN" ]; then
    bash "$SCRIPT_DIR/agent-queue.sh" claim "$AGENT_NAME" "$TASK_PATTERN" || {
        echo "Warning: Could not claim task matching '$TASK_PATTERN', trying next available..."
        bash "$SCRIPT_DIR/agent-queue.sh" claim "$AGENT_NAME" || {
            echo "No tasks available in queue"
            TASK_CLAIMED=false
        }
    }
else
    bash "$SCRIPT_DIR/agent-queue.sh" claim "$AGENT_NAME" || {
        echo "No tasks available in queue"
        TASK_CLAIMED=false
    }
fi

# Get claimed task info
TASK_ID=$(sqlite3 "$DB_FILE" "SELECT current_task_id FROM agents WHERE name = '$AGENT_NAME';" 2>/dev/null || echo "")
TASK_TITLE=""
BRANCH_NAME=""

if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "" ]; then
    TASK_TITLE=$(sqlite3 "$DB_FILE" "SELECT title FROM tasks WHERE id = $TASK_ID;" 2>/dev/null || echo "")
    
    # Create feature branch name from task title
    # Clean up task title for branch name (remove prefixes, lowercase, replace spaces with hyphens)
    BRANCH_NAME=$(echo "$TASK_TITLE" | sed 's/^[^:]*: //' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g' | cut -c1-50)
    BRANCH_NAME="feature/${AGENT_NAME}-${BRANCH_NAME}"
    
    echo "Creating feature branch: $BRANCH_NAME"
    git checkout -b "$BRANCH_NAME"
    
    # Update .context.json with task and branch info
    if command -v jq &> /dev/null; then
        jq ". + {
            \"task_id\": $TASK_ID,
            \"task_title\": \"$TASK_TITLE\",
            \"branch_name\": \"$BRANCH_NAME\"
        }" .context.json > .context.json.tmp && mv .context.json.tmp .context.json
    else
        # Fallback to python3
        python3 <<PYTHON
import json
with open('.context.json', 'r') as f:
    data = json.load(f)
data['task_id'] = $TASK_ID
data['task_title'] = "$TASK_TITLE"
data['branch_name'] = "$BRANCH_NAME"
with open('.context.json', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON
    fi
else
    # No task claimed, create default branch
    BRANCH_NAME="feature/${AGENT_NAME}-work"
    echo "Creating default feature branch: $BRANCH_NAME"
    git checkout -b "$BRANCH_NAME"
    
    # Update .context.json with branch info
    if command -v jq &> /dev/null; then
        jq ". + {
            \"branch_name\": \"$BRANCH_NAME\"
        }" .context.json > .context.json.tmp && mv .context.json.tmp .context.json
    else
        python3 <<PYTHON
import json
with open('.context.json', 'r') as f:
    data = json.load(f)
data['branch_name'] = "$BRANCH_NAME"
with open('.context.json', 'w') as f:
    json.dump(data, f, indent=2)
PYTHON
    fi
fi

echo ""
echo "✓ Agent workspace created and ready!"
echo "  Location: $WORKSPACE_PATH"
echo "  Agent: $AGENT_NAME"
if [ -n "$TASK_TITLE" ]; then
    echo "  Task: $TASK_TITLE"
fi
echo "  Branch: $BRANCH_NAME"
echo ""
echo "Next steps:"
echo "  1. cd $WORKSPACE_PATH"
echo "  2. export AGENT_NAME='$AGENT_NAME'"
if [ -n "$TASK_TITLE" ]; then
    echo "  3. Review task: $TASK_TITLE"
    echo "  4. Start working on the task"
    echo "  5. When done: cd $PROJECT_ROOT && ./scripts/commit-and-pr.sh $WORKSPACE_NAME"
else
    echo "  3. Claim a task: cd $PROJECT_ROOT && ./scripts/agent-queue.sh claim $AGENT_NAME"
fi
