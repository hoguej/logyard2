#!/bin/bash

# Script to commit changes, push to branch, and create a PR
# Usage: ./commit-and-pr.sh <workspace-name> [commit-message]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <workspace-name> [commit-message]"
    echo "Example: $0 workspace_20240101_120000 'Add new feature'"
    exit 1
fi

WORKSPACE_NAME="$1"
COMMIT_MSG="${2:-Update from workspace}"
WORKSPACE_PATH="workspaces/${WORKSPACE_NAME}"

# Check if workspace exists
if [ ! -d "$WORKSPACE_PATH" ]; then
    echo "Error: Workspace $WORKSPACE_PATH does not exist"
    exit 1
fi

# Check if .context.json exists
if [ ! -f "$WORKSPACE_PATH/.context.json" ]; then
    echo "Error: .context.json not found in workspace"
    exit 1
fi

cd "$WORKSPACE_PATH"

# Get branch name from .context.json
if command -v jq &> /dev/null; then
    BRANCH_NAME=$(jq -r '.branch_name' .context.json)
    CONTEXT=$(jq -r '.context' .context.json)
    CREATED_AT=$(jq -r '.created_at' .context.json)
else
    # Fallback to python3 if jq is not available
    BRANCH_NAME=$(python3 -c "import json; f=open('.context.json'); d=json.load(f); print(d.get('branch_name', ''))")
    CONTEXT=$(python3 -c "import json; f=open('.context.json'); d=json.load(f); print(d.get('context', ''))")
    CREATED_AT=$(python3 -c "import json; f=open('.context.json'); d=json.load(f); print(d.get('created_at', ''))")
fi

if [ -z "$BRANCH_NAME" ] || [ "$BRANCH_NAME" = "null" ]; then
    echo "Error: Could not read branch_name from .context.json"
    exit 1
fi

# Check if there are any changes to commit
if git diff --quiet && git diff --cached --quiet; then
    echo "No changes to commit"
else
    echo "Staging all changes..."
    git add -A
    
    echo "Committing changes..."
    git commit -m "$COMMIT_MSG"
    
    echo "Pushing to branch: $BRANCH_NAME"
    git push origin "$BRANCH_NAME" || git push -u origin "$BRANCH_NAME"
fi

# Create PR using GitHub CLI
echo ""
echo "Creating pull request..."

PR_TITLE="${COMMIT_MSG}"
PR_BODY="## Context
${CONTEXT}

## Workspace Details
- Workspace: ${WORKSPACE_NAME}
- Created: ${CREATED_AT}
- Branch: ${BRANCH_NAME}

## Changes
This PR contains changes from workspace ${WORKSPACE_NAME}."

# Check if PR already exists
EXISTING_PR=$(gh pr list --head "$BRANCH_NAME" --json number --jq '.[0].number' 2>/dev/null || echo "")

if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
    echo "Pull request #${EXISTING_PR} already exists for this branch"
    echo "View it at: https://github.com/hoguej/logyard2/pull/${EXISTING_PR}"
else
    PR_NUMBER=$(gh pr create --title "$PR_TITLE" --body "$PR_BODY" --head "$BRANCH_NAME" --base main --json number --jq '.number')
    echo "✓ Pull request created: #${PR_NUMBER}"
    echo "  View at: https://github.com/hoguej/logyard2/pull/${PR_NUMBER}"
fi
