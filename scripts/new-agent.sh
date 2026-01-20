#!/bin/bash
# Create a new agent workspace, register it, claim a task, and invoke Cursor agent to do the work
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
TASK_DESC=""
BRANCH_NAME=""

if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "" ]; then
    TASK_TITLE=$(sqlite3 "$DB_FILE" "SELECT title FROM tasks WHERE id = $TASK_ID;" 2>/dev/null || echo "")
    TASK_DESC=$(sqlite3 "$DB_FILE" "SELECT description FROM tasks WHERE id = $TASK_ID;" 2>/dev/null || echo "")
    
    # Create feature branch name from task title
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
    
    # Create task context file in workspace for the agent to read
    TASK_CONTEXT_FILE=".task-context.md"
    cat > "$TASK_CONTEXT_FILE" <<EOF
# Task Context

**Agent:** $AGENT_NAME  
**Task ID:** $TASK_ID  
**Task Title:** $TASK_TITLE  
**Branch:** $BRANCH_NAME  
**Workspace:** $WORKSPACE_NAME  
**Created:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Task Description

$TASK_DESC

## Context

$CONTEXT_DESC

## Task Details

This task is part of the agent queue system. The task has been claimed and assigned to agent \`$AGENT_NAME\`.

## Instructions

1. **Read agent-instructions** - Review the \`/agent-instructions\` command to understand the workflow
2. **Review relevant commands** - Check \`.cursor/commands/\` directory for any commands related to this task type (e.g., if this is a RESEARCH task, look for research-related commands)
3. **Work in this workspace** - All changes must be made in this workspace: \`$WORKSPACE_PATH\`
   - **CRITICAL**: Do not modify files outside this workspace
4. **Complete the task** - Work on: $TASK_TITLE
5. **When done:**
   - Clean up junk files: Run \`/cleanup-junk\` from this workspace
   - Commit changes: Use format \`[$AGENT_NAME] <descriptive message>\`
   - Push and create PR: Run \`cd $PROJECT_ROOT && ./scripts/commit-and-pr.sh $WORKSPACE_NAME\`
   - The commit-and-pr script will handle: commit, push, PR creation, task completion, and cleanup

## Important Notes

- Stay within workspace boundaries - do not modify files outside \`$WORKSPACE_PATH\`
- Use the commit-and-pr script when work is complete
- The script will automatically mark the task as done and switch back to main
- If you need more information, ask the user for clarification

EOF

    # Create a simple instruction file that points to the context file
    WORK_INSTRUCTION_FILE=".agent-work-instruction.md"
    cat > "$WORK_INSTRUCTION_FILE" <<EOF
# Agent Work Instruction

**Agent:** $AGENT_NAME

## Start Here

Read the task context file: **\`.task-context.md\`**

This file contains all the details about your current task, including:
- Task description and context
- Instructions on what to do
- How to complete and submit your work

## Quick Start

1. Read \`.task-context.md\` for full task details
2. Review \`/agent-instructions\` command for workflow
3. Check \`.cursor/commands/\` for relevant commands
4. Work on the task in this workspace
5. When done, run: \`cd $PROJECT_ROOT && ./scripts/commit-and-pr.sh $WORKSPACE_NAME\`

EOF

    echo ""
    echo "✓ Agent workspace created and task claimed!"
    echo "  Location: $WORKSPACE_PATH"
    echo "  Agent: $AGENT_NAME"
    echo "  Task: $TASK_TITLE"
    echo "  Branch: $BRANCH_NAME"
    echo ""
    echo "Invoking Cursor agent to work on task..."
    
    # Create a direct agent instruction file that will trigger work
    AGENT_START_FILE="$WORKSPACE_PATH/START-WORK.md"
    cat > "$AGENT_START_FILE" <<EOF
# START WORK NOW - Agent Task Execution

**Agent:** $AGENT_NAME  
**Task ID:** $TASK_ID  
**Task:** $TASK_TITLE

## IMMEDIATE INSTRUCTIONS

You are agent **$AGENT_NAME**. You MUST complete this task NOW.

1. **Read .task-context.md** - Contains full task details
2. **Read /agent-instructions** - Understand the workflow  
3. **DO THE WORK** - Complete: $TASK_TITLE
4. **When done** - Run: \`cd $PROJECT_ROOT && ./scripts/commit-and-pr.sh $WORKSPACE_NAME\`

## Task Details
- **Title:** $TASK_TITLE
- **Description:** $TASK_DESC
- **Workspace:** $WORKSPACE_PATH
- **Branch:** $BRANCH_NAME

**BEGIN WORKING IMMEDIATELY. Read .task-context.md and start.**

EOF

    # Open workspace in Cursor - agent will see START-WORK.md and begin
    if command -v cursor &> /dev/null; then
        echo "Opening workspace in Cursor and starting agent..."
        cursor "$WORKSPACE_PATH" "$AGENT_START_FILE" 2>/dev/null || true
        echo "✓ Workspace opened - Agent should now be working"
    else
        echo "Error: Cursor CLI not found. Cannot invoke agent."
        echo "Install Cursor CLI or open manually: cursor $WORKSPACE_PATH"
        exit 1
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
    
    echo ""
    echo "✓ Agent workspace created (no task claimed)"
    echo "  Location: $WORKSPACE_PATH"
    echo "  Agent: $AGENT_NAME"
    echo "  Branch: $BRANCH_NAME"
    echo ""
    echo "To claim a task:"
    echo "  cd $PROJECT_ROOT"
    echo "  ./scripts/agent-queue.sh claim $AGENT_NAME"
fi
