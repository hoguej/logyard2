# /queue-status

Display a visual dashboard of the queue system status, including task progress, active agents, and queue statistics.

## Usage

Type `/queue-status` in Cursor chat. No arguments required.

## What it shows

1. **Priority Progress** - Progress bars for each priority level (P1-P5)
   - Critical (P5), High (P4), Medium (P3), Normal (P2), Low (P1)
   - Shows completed, in progress, and total counts

2. **Active Agents** - List of all active agents
   - Shows agent status (working/idle)
   - Current task being worked on
   - Last heartbeat time
   - Detects stuck agents (no heartbeat in 10+ minutes)

3. **Task Queue** - Current queue state
   - Tasks in progress with assigned agents
   - Next up tasks (by priority)
   - Failed tasks (if any)
   - Counts: Working, Queued, Done, Failed

## Example Output

The command displays a formatted dashboard with:
- Progress bars for each priority level
- Agent status with emoji indicators (🟢 working, 🟡 idle)
- Task queue summary
- Real-time statistics

## Execution

When this command is invoked, execute the following script:

```bash
bash scripts/queue-status.sh
```

The script is located at `${workspaceFolder}/scripts/queue-status.sh` and must be executed from the workspace root.

## Watch Mode

You can also watch the status in real-time:
```bash
watch -n 5 -c ./scripts/queue-status.sh
```
