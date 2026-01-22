# Queue Status Dashboard

Simple web dashboard for viewing logyard2 queue status.

## Running the Dashboard

```bash
# From the project root
node app/server.js
```

The server will automatically find an available port (starting from 3000) and display the URL.

Then open the displayed URL (e.g., http://localhost:3000) in your browser.

The dashboard will auto-refresh every 5 seconds.

## Testing

Always run the test after making changes to `server.js`:

```bash
node app/test-server.js
```

This ensures the server can start successfully.

## What it shows

- **Queue Status**: All queues with queued/working counts and progress bars
- **Root Work Items**: Active and recently finished work items
- **Running Agents**: All agent scripts with their running counts
- **Recent Announcements**: Last 5 announcements from agents

## Requirements

- Node.js (for the server)
- sqlite3 command-line tool (for database queries)
- The `.agent-queue.db` file in the project root
