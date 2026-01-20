#!/bin/bash

# Script to archive a workspace by moving it to workspaces/archive
# Usage: ./archive-workspace.sh <workspace-name>

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <workspace-name>"
    echo "Example: $0 workspace_20240101_120000"
    exit 1
fi

WORKSPACE_NAME="$1"
WORKSPACE_PATH="workspaces/${WORKSPACE_NAME}"
ARCHIVE_PATH="workspaces/archive/${WORKSPACE_NAME}"

# Check if workspace exists
if [ ! -d "$WORKSPACE_PATH" ]; then
    echo "Error: Workspace $WORKSPACE_PATH does not exist"
    exit 1
fi

# Check if already archived
if [ -d "$ARCHIVE_PATH" ]; then
    echo "Error: Workspace is already archived at $ARCHIVE_PATH"
    exit 1
fi

# Create archive directory if it doesn't exist
mkdir -p workspaces/archive

# Update .context.json with archived timestamp
if [ -f "$WORKSPACE_PATH/.context.json" ]; then
    cd "$WORKSPACE_PATH"
    ARCHIVED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Update context.json with archived timestamp
    if command -v jq &> /dev/null; then
        jq ". + {\"archived_at\": \"$ARCHIVED_AT\"}" .context.json > .context.json.tmp && mv .context.json.tmp .context.json
    else
        # Fallback if jq is not available
        python3 -c "
import json
import sys
with open('.context.json', 'r') as f:
    data = json.load(f)
data['archived_at'] = '$ARCHIVED_AT'
with open('.context.json', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
    cd - > /dev/null
fi

# Move workspace to archive
echo "Archiving workspace: $WORKSPACE_NAME"
mv "$WORKSPACE_PATH" "$ARCHIVE_PATH"

echo "✓ Workspace archived successfully!"
echo "  Archived to: $ARCHIVE_PATH"
