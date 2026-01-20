# /agent-queue

Manage the agent queue system - register agents, claim tasks, complete work, and more.

## Usage

Type `/agent-queue` in Cursor chat, then provide:
- Command (register, claim, complete, release, heartbeat, add, status, list, whoami)
- Required arguments for that command

## Commands

### Register Agent
```
/agent-queue register <agent-name> [workspace-path]
```
Register an agent in the queue system. If workspace-path is not provided, uses project root.

### Claim Task
```
/agent-queue claim <agent-name> [task-title]
```
Claim the next available task, or a specific task by title pattern.

### Complete Task
```
/agent-queue complete <agent-name> [result]
```
Mark the current task as complete with optional result message.

### Release Task
```
/agent-queue release <agent-name> [reason]
```
Release the current task back to the queue (marks as failed/released).

### Heartbeat
```
/agent-queue heartbeat <agent-name> [activity]
```
Update agent heartbeat to show you're still active.

### Add Task
```
/agent-queue add <title> [description] [priority]
```
Add a new task to the queue. Priority: 1=Low, 2=Normal, 3=Medium, 4=High, 5=Critical.

### Status
```
/agent-queue status [agent-name]
```
Show status for a specific agent, or all agents if no name provided.

### List
```
/agent-queue list
```
List all registered agents with their current tasks.

### Whoami
```
/agent-queue whoami
```
Show current agent (from AGENT_NAME environment variable).

## Examples

```
/agent-queue register alpha workspaces/agent_alpha_20240101_120000
/agent-queue claim alpha
/agent-queue complete alpha "Merged PR #42"
/agent-queue add "Fix bug in auth" "Description here" 3
/agent-queue status alpha
```

## Execution

When this command is invoked, execute the following script with the provided arguments:

```bash
bash scripts/agent-queue.sh <command> [args]
```

The script is located at `${workspaceFolder}/scripts/agent-queue.sh` and must be executed from the workspace root.
