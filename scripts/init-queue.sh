#!/bin/bash
# Initialize SQLite queue database for logyard2
# Usage: ./scripts/init-queue.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DB_FILE="$PROJECT_ROOT/.agent-queue.db"

echo "Initializing multi-queue database: $DB_FILE"

# DB-001: Create queues table
sqlite3 "$DB_FILE" "
CREATE TABLE IF NOT EXISTS queues (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    priority_default INTEGER DEFAULT 2 CHECK(priority_default IN (1, 2, 3, 4, 5)),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_queues_name ON queues(name);
"

# DB-002: Create queue_tasks table
sqlite3 "$DB_FILE" "
CREATE TABLE IF NOT EXISTS queue_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    queue_id INTEGER NOT NULL REFERENCES queues(id),
    task_id INTEGER NOT NULL REFERENCES tasks(id),
    status TEXT DEFAULT 'queued' CHECK(status IN ('queued', 'in_progress', 'completed', 'failed', 'cancelled')),
    priority INTEGER DEFAULT 2 CHECK(priority IN (1, 2, 3, 4, 5)),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(queue_id, task_id)
);

CREATE INDEX IF NOT EXISTS idx_queue_tasks_queue_id ON queue_tasks(queue_id);
CREATE INDEX IF NOT EXISTS idx_queue_tasks_task_id ON queue_tasks(task_id);
CREATE INDEX IF NOT EXISTS idx_queue_tasks_status ON queue_tasks(status);
"

# DB-003: Create queue_agents table
sqlite3 "$DB_FILE" "
CREATE TABLE IF NOT EXISTS queue_agents (
    agent_name TEXT NOT NULL REFERENCES agents(name),
    queue_id INTEGER NOT NULL REFERENCES queues(id),
    priority INTEGER DEFAULT 2 CHECK(priority IN (1, 2, 3, 4, 5)),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (agent_name, queue_id)
);

CREATE INDEX IF NOT EXISTS idx_queue_agents_agent_name ON queue_agents(agent_name);
CREATE INDEX IF NOT EXISTS idx_queue_agents_queue_id ON queue_agents(queue_id);
"

# DB-004: Create announcements table
sqlite3 "$DB_FILE" "
CREATE TABLE IF NOT EXISTS announcements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL CHECK(type IN ('work-taken', 'work-completed', 'error', 'question', 'status')),
    agent_name TEXT REFERENCES agents(name),
    task_id INTEGER REFERENCES tasks(id),
    message TEXT NOT NULL,
    context TEXT,
    priority INTEGER DEFAULT 2 CHECK(priority IN (1, 2, 3, 4, 5)),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_announcements_type ON announcements(type);
CREATE INDEX IF NOT EXISTS idx_announcements_agent_name ON announcements(agent_name);
CREATE INDEX IF NOT EXISTS idx_announcements_task_id ON announcements(task_id);
CREATE INDEX IF NOT EXISTS idx_announcements_created_at ON announcements(created_at);
"

# Create tasks table (existing, but will be modified)
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

# DB-005: Add queue_type field to tasks table
sqlite3 "$DB_FILE" "
ALTER TABLE tasks ADD COLUMN queue_type TEXT;
CREATE INDEX IF NOT EXISTS idx_tasks_queue_type ON tasks(queue_type);
UPDATE tasks SET queue_type = 'general' WHERE queue_type IS NULL;
"

# DB-006: Add queue_preferences field to agents table
sqlite3 "$DB_FILE" "
CREATE TABLE IF NOT EXISTS agents (
    name TEXT NOT NULL,
    instance_id TEXT NOT NULL,
    workspace_path TEXT,
    status TEXT DEFAULT 'idle' CHECK(status IN ('idle', 'working', 'offline')),
    current_task_id INTEGER REFERENCES tasks(id),
    last_heartbeat DATETIME,
    last_activity TEXT,
    pid INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (name, instance_id)
);

CREATE INDEX IF NOT EXISTS idx_agents_status ON agents(status);
CREATE INDEX IF NOT EXISTS idx_agents_name_instance ON agents(name, instance_id);
"

# Add queue_preferences column if it doesn't exist
sqlite3 "$DB_FILE" "
ALTER TABLE agents ADD COLUMN queue_preferences TEXT;
" 2>/dev/null || true

# Migration: Convert existing agents to new schema if needed
# Check if agents table exists with old schema (name as PRIMARY KEY without instance_id)
sqlite3 "$DB_FILE" "
-- Check if instance_id column exists
SELECT COUNT(*) FROM pragma_table_info('agents') WHERE name='instance_id';
" > /tmp/check_instance_id.txt 2>/dev/null || echo "0" > /tmp/check_instance_id.txt

if [ "$(cat /tmp/check_instance_id.txt)" = "0" ]; then
    echo "Migrating agents table to multi-instance schema..."
    
    # Create backup table
    sqlite3 "$DB_FILE" "
    CREATE TABLE IF NOT EXISTS agents_backup AS SELECT * FROM agents;
    "
    
    # Drop old table and recreate with new schema
    sqlite3 "$DB_FILE" "
    DROP TABLE IF EXISTS agents;
    CREATE TABLE agents (
        name TEXT NOT NULL,
        instance_id TEXT NOT NULL,
        workspace_path TEXT,
        status TEXT DEFAULT 'idle' CHECK(status IN ('idle', 'working', 'offline')),
        current_task_id INTEGER REFERENCES tasks(id),
        last_heartbeat DATETIME,
        last_activity TEXT,
        pid INTEGER,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (name, instance_id)
    );
    
    CREATE INDEX IF NOT EXISTS idx_agents_status ON agents(status);
    CREATE INDEX IF NOT EXISTS idx_agents_name_instance ON agents(name, instance_id);
    
    -- Migrate existing data: assign default instance_id to existing agents
    INSERT INTO agents (name, instance_id, workspace_path, status, current_task_id, last_heartbeat, last_activity, created_at)
    SELECT 
        name,
        name || '_' || datetime('now', 'localtime') || '_legacy' as instance_id,
        workspace_path,
        status,
        current_task_id,
        last_heartbeat,
        last_activity,
        datetime('now', 'localtime') as created_at
    FROM agents_backup;
    
    DROP TABLE IF EXISTS agents_backup;
    "
    
    echo "✓ Agents table migrated to multi-instance schema"
fi

rm -f /tmp/check_instance_id.txt

# DB-007: Add traceability fields to tasks table
sqlite3 "$DB_FILE" "
ALTER TABLE tasks ADD COLUMN root_work_item_id INTEGER;
ALTER TABLE tasks ADD COLUMN parent_task_id INTEGER REFERENCES tasks(id);
ALTER TABLE tasks ADD COLUMN work_item_chain TEXT;
CREATE INDEX IF NOT EXISTS idx_tasks_root_work_item_id ON tasks(root_work_item_id);
CREATE INDEX IF NOT EXISTS idx_tasks_parent_task_id ON tasks(parent_task_id);
"

# WF-005: Create root_work_items table
sqlite3 "$DB_FILE" "
CREATE TABLE IF NOT EXISTS root_work_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_input TEXT NOT NULL,
    title TEXT,
    description TEXT,
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'researching', 'planning', 'executing', 'checking', 'building', 'deploying', 'testing', 'completed', 'failed', 'cancelled')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    completed_at DATETIME,
    failed_at DATETIME,
    cancelled_at DATETIME
);

CREATE INDEX IF NOT EXISTS idx_root_work_items_status ON root_work_items(status);
CREATE INDEX IF NOT EXISTS idx_root_work_items_created_at ON root_work_items(created_at);
"

# Initialize default queues
sqlite3 "$DB_FILE" "
INSERT OR IGNORE INTO queues (name, description, priority_default) VALUES
    ('requirements-research', 'Transforms high-level requirements into detailed requirement documents', 2),
    ('planning', 'Breaks down requirements into fully-detailed, executable tasks', 2),
    ('execution', 'Executes planned tasks (actual coding work)', 2),
    ('pre-commit-check', 'Validates code quality before committing', 2),
    ('commit-build', 'Commits code, creates PR, monitors build', 2),
    ('deploy', 'Merges PRs, monitors deployment', 2),
    ('e2e-test', 'Runs end-to-end tests, handles failures', 2),
    ('announce', 'Communication channel for agents to announce activities', 1);
"

echo "✓ Multi-queue database initialized successfully"
echo "  Database: $DB_FILE"
echo "  Tables: queues, queue_tasks, queue_agents, announcements, tasks, agents, root_work_items"
echo "  Default queues: requirements-research, planning, execution, pre-commit-check, commit-build, deploy, e2e-test, announce"
