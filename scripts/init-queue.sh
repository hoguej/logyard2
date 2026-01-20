#!/bin/bash
# Initialize SQLite queue database for logyard2
# Usage: ./scripts/init-queue.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

echo "Initializing queue database: $DB_FILE"

# Create tasks table
sqlite3 "$DB_FILE" "
CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    context TEXT,
    priority INTEGER DEFAULT 2 CHECK(priority IN (1, 2, 3, 4, 5)),
    status TEXT DEFAULT 'queued' CHECK(status IN ('queued', 'in_progress', 'completed', 'failed', 'cancelled')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    claimed_at DATETIME,
    claimed_by TEXT,
    completed_at DATETIME,
    result TEXT,
    error TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority);
CREATE INDEX IF NOT EXISTS idx_tasks_claimed_by ON tasks(claimed_by);
"

# Create agents table
sqlite3 "$DB_FILE" "
CREATE TABLE IF NOT EXISTS agents (
    name TEXT PRIMARY KEY,
    workspace_path TEXT,
    status TEXT DEFAULT 'idle' CHECK(status IN ('idle', 'working', 'offline')),
    current_task_id INTEGER REFERENCES tasks(id),
    last_heartbeat DATETIME,
    last_activity TEXT
);

CREATE INDEX IF NOT EXISTS idx_agents_status ON agents(status);
"

echo "✓ Queue database initialized successfully"
echo "  Database: $DB_FILE"
echo "  Tables: tasks, agents"
