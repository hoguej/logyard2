#!/bin/bash

# Script to remove old archived workspaces after a specified time period
# Usage: ./cleanup-archives.sh [days-old]
# Default: 30 days

set -e

DAYS_OLD="${1:-30}"
ARCHIVE_DIR="workspaces/archive"

if [ ! -d "$ARCHIVE_DIR" ]; then
    echo "Archive directory does not exist: $ARCHIVE_DIR"
    exit 0
fi

echo "Cleaning up archives older than $DAYS_OLD days..."
echo ""

# Find directories in archive that are older than specified days
FOUND_ANY=false

for workspace_dir in "$ARCHIVE_DIR"/workspace_*; do
    if [ ! -d "$workspace_dir" ]; then
        continue
    fi
    
    WORKSPACE_NAME=$(basename "$workspace_dir")
    
    # Check archived_at from .context.json if available
    if [ -f "$workspace_dir/.context.json" ]; then
        if command -v jq &> /dev/null; then
            ARCHIVED_AT=$(jq -r '.archived_at' "$workspace_dir/.context.json" 2>/dev/null || echo "")
        else
            ARCHIVED_AT=$(python3 -c "import json; f=open('$workspace_dir/.context.json'); d=json.load(f); print(d.get('archived_at', ''))" 2>/dev/null || echo "")
        fi
        
        if [ -n "$ARCHIVED_AT" ] && [ "$ARCHIVED_AT" != "null" ]; then
            # Parse archived_at timestamp
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS date command
                ARCHIVE_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ARCHIVED_AT" +%s 2>/dev/null || echo "")
            else
                # Linux date command
                ARCHIVE_EPOCH=$(date -d "$ARCHIVED_AT" +%s 2>/dev/null || echo "")
            fi
            
            if [ -n "$ARCHIVE_EPOCH" ]; then
                CURRENT_EPOCH=$(date +%s)
                DAYS_SINCE_ARCHIVE=$(( (CURRENT_EPOCH - ARCHIVE_EPOCH) / 86400 ))
                
                if [ $DAYS_SINCE_ARCHIVE -ge $DAYS_OLD ]; then
                    echo "Removing $WORKSPACE_NAME (archived $DAYS_SINCE_ARCHIVE days ago)"
                    rm -rf "$workspace_dir"
                    FOUND_ANY=true
                    continue
                fi
            fi
        fi
    fi
    
    # Fallback: use directory modification time if .context.json doesn't have archived_at
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS stat command
        MOD_TIME=$(stat -f "%m" "$workspace_dir" 2>/dev/null || echo "")
    else
        # Linux stat command
        MOD_TIME=$(stat -c "%Y" "$workspace_dir" 2>/dev/null || echo "")
    fi
    
    if [ -n "$MOD_TIME" ]; then
        CURRENT_EPOCH=$(date +%s)
        DAYS_SINCE_MOD=$(( (CURRENT_EPOCH - MOD_TIME) / 86400 ))
        
        if [ $DAYS_SINCE_MOD -ge $DAYS_OLD ]; then
            echo "Removing $WORKSPACE_NAME (last modified $DAYS_SINCE_MOD days ago)"
            rm -rf "$workspace_dir"
            FOUND_ANY=true
        fi
    fi
done

if [ "$FOUND_ANY" = false ]; then
    echo "No archives found older than $DAYS_OLD days"
else
    echo ""
    echo "✓ Cleanup complete!"
fi
