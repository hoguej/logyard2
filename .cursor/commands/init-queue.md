# /init-queue

Initialize the SQLite queue database with tasks and agents tables.

## Usage

Type `/init-queue` in Cursor chat. No arguments required.

## What it does

1. Creates `.agent-queue.db` SQLite database in the project root
2. Creates `tasks` table with schema:
   - id, title, description, context
   - priority (1-5), status (queued, in_progress, completed, failed, cancelled)
   - timestamps (created_at, claimed_at, completed_at)
   - claimed_by, result, error
   - retry_count, max_retries

3. Creates `agents` table with schema:
   - name (primary key), workspace_path
   - status (idle, working, offline)
   - current_task_id, last_heartbeat, last_activity

4. Creates indexes for performance

## When to use

- First time setting up the queue system
- If the database file is missing or corrupted
- After cloning the repository (database is gitignored)

## Execution

When this command is invoked, execute the following script:

```bash
bash scripts/init-queue.sh
```

The script is located at `${workspaceFolder}/scripts/init-queue.sh` and must be executed from the workspace root.

## Note

The database file `.agent-queue.db` is automatically ignored by git (via `*.db` pattern in `.gitignore`).
