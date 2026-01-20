#!/bin/bash
# Create a new agent workspace and register it
# Usage: ./scripts/new-agent.sh <agent-name> [context-description]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <agent-name> [context-description]"
    echo "Example: $0 alpha 'Working on authentication features'"
    exit 1
fi

AGENT_NAME="$1"
CONTEXT_DESC="${2:-Agent workspace for $AGENT_NAME}"
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

# Create .context.json file
echo "Creating .context.json..."
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

echo ""
echo "✓ Agent workspace created successfully!"
echo "  Location: $WORKSPACE_PATH"
echo "  Agent: $AGENT_NAME"
echo ""
echo "To work in this workspace:"
echo "  cd $WORKSPACE_PATH"
echo "  export AGENT_NAME='$AGENT_NAME'"
echo ""
echo "To claim a task:"
echo "  cd $PROJECT_ROOT"
echo "  ./scripts/agent-queue.sh claim $AGENT_NAME"
