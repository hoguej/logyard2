#!/bin/bash
# Create a new agent workspace, register it, claim a task, and invoke Cursor agent to do the work
# Usage: ./scripts/new-agent.sh <agent-name> [context-description] [task-title-pattern] [--loop] [-n interval]

set -e

LOOP_MODE=false
LOOP_INTERVAL=15  # Default 15 seconds

# Parse arguments
ARGS=()
i=1
while [ $i -le $# ]; do
    eval "arg=\${$i}"
    case "$arg" in
        --loop)
            LOOP_MODE=true
            ;;
        -n)
            i=$((i+1))
            eval "LOOP_INTERVAL=\${$i}"
            if ! [[ "$LOOP_INTERVAL" =~ ^[0-9]+$ ]]; then
                echo "Error: -n requires a numeric value"
                exit 1
            fi
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
    i=$((i+1))
done

if [ ${#ARGS[@]} -lt 1 ]; then
    echo "Usage: $0 <agent-name> [context-description] [task-title-pattern] [--loop] [-n interval]"
    echo "Example: $0 alpha 'Working on authentication features' 'RESEARCH'"
    echo "         $0 alpha 'Working on features' --loop  (watch for new work and claim it)"
    echo "         $0 alpha 'Working on features' --loop -n 30  (loop with 30 second interval)"
    exit 1
fi

AGENT_NAME="${ARGS[0]}"
CONTEXT_DESC="${ARGS[1]:-Agent workspace for $AGENT_NAME}"
TASK_PATTERN="${ARGS[2]}"
REPO_URL="https://github.com/hoguej/logyard2.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

# Initialize queue database if it doesn't exist
if [ ! -f "$DB_FILE" ]; then
    echo "Initializing queue database..."
    bash "$SCRIPT_DIR/init-queue.sh"
fi

# Create workspaces directory if it doesn't exist
mkdir -p workspaces

# Check if workspace already exists for this agent
EXISTING_WORKSPACE=$(sqlite3 "$DB_FILE" "SELECT workspace_path FROM agents WHERE name = '$AGENT_NAME';" 2>/dev/null || echo "")

if [ -n "$EXISTING_WORKSPACE" ] && [ -d "$EXISTING_WORKSPACE" ]; then
    echo "Reusing existing workspace for agent '$AGENT_NAME':"
    echo "  $EXISTING_WORKSPACE"
    WORKSPACE_PATH="$EXISTING_WORKSPACE"
    WORKSPACE_NAME=$(basename "$WORKSPACE_PATH")
    cd "$WORKSPACE_PATH"
    REUSE_WORKSPACE=true
    
    # Make sure we're on main and pull latest
    echo "Updating workspace..."
    git checkout main 2>/dev/null || git checkout -b main 2>/dev/null || true
    git pull origin main 2>/dev/null || true
else
    # Generate unique workspace name with timestamp
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    WORKSPACE_NAME="agent_${AGENT_NAME}_${TIMESTAMP}"
    WORKSPACE_PATH="workspaces/${WORKSPACE_NAME}"
    REUSE_WORKSPACE=false
    
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
fi

# Register the agent (or update if exists)
echo "Registering agent in queue..."
bash "$SCRIPT_DIR/agent-queue.sh" register "$AGENT_NAME" "$(realpath "$WORKSPACE_PATH")"

# Function to claim and work on a task
work_on_task() {
    local pattern="$1"
    
    echo ""
    echo "Claiming a task from queue..."
    if [ -n "$pattern" ]; then
        bash "$SCRIPT_DIR/agent-queue.sh" claim "$AGENT_NAME" "$pattern" || {
            echo "Warning: Could not claim task matching '$pattern', trying next available..."
            bash "$SCRIPT_DIR/agent-queue.sh" claim "$AGENT_NAME" || {
                return 1
            }
        }
    else
        bash "$SCRIPT_DIR/agent-queue.sh" claim "$AGENT_NAME" || {
            return 1
        }
    fi
    
    # Get claimed task info
    TASK_ID=$(sqlite3 "$DB_FILE" "SELECT current_task_id FROM agents WHERE name = '$AGENT_NAME';" 2>/dev/null || echo "")
    
    if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "" ]; then
        return 1
    fi
    
    TASK_TITLE=$(sqlite3 "$DB_FILE" "SELECT title FROM tasks WHERE id = $TASK_ID;" 2>/dev/null || echo "")
    TASK_DESC=$(sqlite3 "$DB_FILE" "SELECT description FROM tasks WHERE id = $TASK_ID;" 2>/dev/null || echo "")
    
    # Make sure we're on main and pull latest before creating branch
    cd "$WORKSPACE_PATH"
    git checkout main 2>/dev/null || true
    git pull origin main 2>/dev/null || true
    
    # Create feature branch name from task title
    BRANCH_NAME=$(echo "$TASK_TITLE" | sed 's/^[^:]*: //' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g' | cut -c1-50)
    BRANCH_NAME="feature/${AGENT_NAME}-${BRANCH_NAME}"
    
    echo "Creating feature branch: $BRANCH_NAME"
    git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME" 2>/dev/null || true
    
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
2. **Review relevant commands** - Check \`.cursor/commands/\` directory for any commands related to this task type
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

    # Create a direct agent instruction file that will trigger work
    AGENT_START_FILE="START-WORK.md"
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

    echo ""
    echo "✓ Task claimed and workspace ready!"
    echo "  Agent: $AGENT_NAME"
    echo "  Task: $TASK_TITLE"
    echo "  Branch: $BRANCH_NAME"
    echo ""
    echo "Invoking Cursor agent to work on task..."
    
    # Create tmp directory for agent prompts
    mkdir -p "$PROJECT_ROOT/tmp"
    
    # Create prompt file in tmp directory
    local prompt_file="$PROJECT_ROOT/tmp/new-agent-${TASK_ID}.md"
    cat > "$prompt_file" <<EOF
$(cat "$AGENT_START_FILE")
EOF
    
    echo "Prompt file: $prompt_file"
    
    # Open workspace in Cursor - agent will reference the prompt file
    ABS_WORKSPACE_PATH="$(pwd)"
    if command -v cursor &> /dev/null; then
        echo "Opening workspace in Cursor and starting agent..."
        cursor "$ABS_WORKSPACE_PATH" "$prompt_file" 2>/dev/null || true
        echo "✓ Workspace opened - Agent should now be working"
    else
        echo "Error: Cursor CLI not found. Cannot invoke agent."
        echo "Install Cursor CLI or open manually: cursor $ABS_WORKSPACE_PATH"
        return 1
    fi
    
    return 0
}

# Main execution
if [ "$LOOP_MODE" = true ]; then
    echo "Starting agent in loop mode - watching for new tasks..."
    echo "Agent: $AGENT_NAME"
    echo "Check interval: ${LOOP_INTERVAL} seconds"
    echo "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        # Check if agent has a current task
        CURRENT_TASK=$(sqlite3 "$DB_FILE" "SELECT current_task_id FROM agents WHERE name = '$AGENT_NAME';" 2>/dev/null || echo "")
        
        if [ -z "$CURRENT_TASK" ] || [ "$CURRENT_TASK" = "" ]; then
            # No current task, try to claim one
            echo "[$(date '+%H:%M:%S')] Checking for available tasks..."
            
            if work_on_task "$TASK_PATTERN"; then
                echo "[$(date '+%H:%M:%S')] Task claimed, agent working..."
                # Wait for task to complete (check at loop interval)
                while true; do
                    sleep "$LOOP_INTERVAL"
                    TASK_STATUS=$(sqlite3 "$DB_FILE" "
                        SELECT t.status FROM tasks t
                        JOIN agents a ON t.id = a.current_task_id
                        WHERE a.name = '$AGENT_NAME';
                    " 2>/dev/null || echo "")
                    
                    if [ "$TASK_STATUS" = "completed" ] || [ "$TASK_STATUS" = "failed" ] || [ "$TASK_STATUS" = "cancelled" ]; then
                        echo "[$(date '+%H:%M:%S')] Task $TASK_STATUS, looking for next task..."
                        break
                    fi
                    
                    # Update heartbeat
                    bash "$SCRIPT_DIR/agent-queue.sh" heartbeat "$AGENT_NAME" "Working on task" 2>/dev/null || true
                done
            else
                echo "[$(date '+%H:%M:%S')] No tasks available, waiting ${LOOP_INTERVAL} seconds..."
                sleep "$LOOP_INTERVAL"
            fi
        else
            # Has a task, just update heartbeat and wait
            bash "$SCRIPT_DIR/agent-queue.sh" heartbeat "$AGENT_NAME" "Waiting for task completion" 2>/dev/null || true
            sleep "$LOOP_INTERVAL"
        fi
    done
else
    # Single task mode
    if work_on_task "$TASK_PATTERN"; then
        echo ""
        echo "✓ Agent is working on task"
    else
        echo ""
        echo "No tasks available in queue"
        echo "To claim a task later:"
        echo "  cd $PROJECT_ROOT"
        echo "  ./scripts/agent-queue.sh claim $AGENT_NAME"
    fi
fi
