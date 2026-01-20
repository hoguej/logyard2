#!/bin/bash

# Script to create a new workspace by cloning logyard2 repo
# Usage: ./create-workspace.sh <branch-name> <context-description>

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <branch-name> <context-description>"
    echo "Example: $0 feature/my-feature 'Working on new authentication system'"
    exit 1
fi

BRANCH_NAME="$1"
CONTEXT_DESC="$2"
REPO_URL="https://github.com/hoguej/logyard2.git"

# Generate unique workspace name with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WORKSPACE_NAME="workspace_${TIMESTAMP}"
WORKSPACE_PATH="workspaces/${WORKSPACE_NAME}"

# Create workspaces directory if it doesn't exist
mkdir -p workspaces

# Check if workspace already exists
if [ -d "$WORKSPACE_PATH" ]; then
    echo "Error: Workspace $WORKSPACE_PATH already exists"
    exit 1
fi

echo "Creating workspace: $WORKSPACE_NAME"
echo "Branch: $BRANCH_NAME"
echo "Context: $CONTEXT_DESC"
echo ""

# Clone the repository
echo "Cloning repository..."
git clone "$REPO_URL" "$WORKSPACE_PATH"

# Navigate to workspace and checkout branch
cd "$WORKSPACE_PATH"
echo "Checking out branch: $BRANCH_NAME"

# Check if branch exists remotely
if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
    echo "Branch exists remotely, checking out..."
    git checkout "$BRANCH_NAME"
    git pull origin "$BRANCH_NAME"
else
    echo "Creating new branch: $BRANCH_NAME"
    git checkout -b "$BRANCH_NAME"
fi

# Create .context.json file
echo "Creating .context.json..."
cat > .context.json <<EOF
{
  "workspace_name": "$WORKSPACE_NAME",
  "branch_name": "$BRANCH_NAME",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "context": "$CONTEXT_DESC",
  "created_by": "$(whoami)"
}
EOF

echo ""
echo "✓ Workspace created successfully!"
echo "  Location: $WORKSPACE_PATH"
echo "  Branch: $BRANCH_NAME"
echo ""
echo "To work in this workspace:"
echo "  cd $WORKSPACE_PATH"
