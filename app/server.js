#!/usr/bin/env node
// Simple HTTP server to serve the dashboard and provide JSON API
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PORT = process.env.PORT || 3000;
const PROJECT_ROOT = path.resolve(__dirname, '..');
const DB_FILE = path.join(PROJECT_ROOT, '.agent-queue.db');

// MIME types
const mimeTypes = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
};

const server = http.createServer((req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // API endpoint for queue status
  if (req.url === '/api/status') {
    try {
      const status = getQueueStatus();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(status, null, 2));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    }
    return;
  }

  // Serve static files
  let filePath = path.join(__dirname, req.url === '/' ? 'index.html' : req.url);
  
  // Security: prevent directory traversal
  if (!filePath.startsWith(__dirname)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }

    const ext = path.extname(filePath);
    const contentType = mimeTypes[ext] || 'text/plain';
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
});

function getQueueStatus() {
  // Check if database exists
  if (!fs.existsSync(DB_FILE)) {
    return { error: 'Database not found' };
  }

  const queues = [];
  const rootWorkItems = [];
  const agents = [];
  const announcements = [];

  try {
    // Get queue status
    const queueData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT q.name, q.description, COALESCE(SUM(CASE WHEN qt.status = 'queued' THEN 1 ELSE 0 END), 0) as queued, COALESCE(SUM(CASE WHEN qt.status = 'in_progress' THEN 1 ELSE 0 END), 0) as in_progress, COALESCE(SUM(CASE WHEN qt.status = 'completed' AND datetime(qt.updated_at) >= datetime('now', '-1 hour') THEN 1 ELSE 0 END), 0) as done_last_hour FROM queues q LEFT JOIN queue_tasks qt ON q.id = qt.queue_id GROUP BY q.id, q.name ORDER BY CASE q.name WHEN 'requirements-research' THEN 1 WHEN 'planning' THEN 2 WHEN 'execution' THEN 3 WHEN 'pre-commit-check' THEN 4 WHEN 'commit-build' THEN 5 WHEN 'deploy' THEN 6 WHEN 'e2e-test' THEN 7 WHEN 'announce' THEN 8 ELSE 9 END;"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );
    
    if (queueData.trim()) {
      const parsed = JSON.parse(queueData);
      queues.push(...(Array.isArray(parsed) ? parsed : [parsed]));
    }

    // Get root work items
    const rootWorkItemsData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT id, title, status, completed_at, failed_at FROM root_work_items WHERE status NOT IN ('completed', 'failed', 'cancelled') OR (status = 'completed' AND datetime(completed_at) >= datetime('now', '-1 hour')) OR (status = 'failed' AND datetime(failed_at) >= datetime('now', '-1 hour')) ORDER BY CASE status WHEN 'executing' THEN 1 WHEN 'checking' THEN 2 WHEN 'building' THEN 3 WHEN 'deploying' THEN 4 WHEN 'testing' THEN 5 WHEN 'planning' THEN 6 WHEN 'researching' THEN 7 WHEN 'pending' THEN 8 WHEN 'completed' THEN 9 WHEN 'failed' THEN 10 ELSE 11 END, created_at DESC;"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );
    
    if (rootWorkItemsData.trim()) {
      const parsed = JSON.parse(rootWorkItemsData);
      rootWorkItems.push(...(Array.isArray(parsed) ? parsed : [parsed]));
    }

    // Get running agents
    const agentScripts = [
      { queue: 'requirements-research', script: 'agent-requirements-research.sh' },
      { queue: 'planning', script: 'agent-planning.sh' },
      { queue: 'execution', script: 'agent-execution.sh' },
      { queue: 'pre-commit-check', script: 'agent-pre-commit-check.sh' },
      { queue: 'commit-build', script: 'agent-commit-build.sh' },
      { queue: 'deploy', script: 'agent-deploy.sh' },
      { queue: 'e2e-test', script: 'agent-e2e-test.sh' },
    ];

    for (const agent of agentScripts) {
      try {
        const agentData = execSync(
          `sqlite3 -json "${DB_FILE}" "SELECT COUNT(*) as total, SUM(CASE WHEN status = 'working' AND last_heartbeat >= datetime('now', '-30 minutes') THEN 1 ELSE 0 END) as working, SUM(CASE WHEN status = 'idle' AND last_heartbeat >= datetime('now', '-30 minutes') THEN 1 ELSE 0 END) as idle FROM agents WHERE name = '${agent.queue}';"`,
          { encoding: 'utf8', cwd: PROJECT_ROOT }
        );
        
        const parsed = agentData.trim() ? JSON.parse(agentData) : [];
        const result = Array.isArray(parsed) && parsed.length > 0 ? parsed[0] : { total: 0, working: 0, idle: 0 };
        agents.push({
          script: agent.script,
          total: parseInt(result.total) || 0,
          working: parseInt(result.working) || 0,
          idle: parseInt(result.idle) || 0,
        });
      } catch (err) {
        // If query fails, just add zero counts
        agents.push({
          script: agent.script,
          total: 0,
          working: 0,
          idle: 0,
        });
      }
    }

    // Get recent announcements
    const announcementsData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT type, agent_name, message, created_at FROM announcements ORDER BY created_at DESC LIMIT 5;"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );
    
    if (announcementsData.trim()) {
      const parsed = JSON.parse(announcementsData);
      announcements.push(...(Array.isArray(parsed) ? parsed : [parsed]));
    }

  } catch (error) {
    console.error('Error fetching status:', error);
    return { error: error.message };
  }

  return {
    queues,
    rootWorkItems,
    agents,
    announcements,
    timestamp: new Date().toISOString(),
  };
}

// Function to find an available port
function findAvailablePort(startPort, maxAttempts = 10) {
  return new Promise((resolve, reject) => {
    let attempts = 0;
    const tryPort = (port) => {
      if (attempts >= maxAttempts) {
        reject(new Error(`Could not find available port after ${maxAttempts} attempts`));
        return;
      }

      const testServer = http.createServer();
      testServer.listen(port, () => {
        testServer.close(() => {
          resolve(port);
        });
      });
      
      testServer.on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
          attempts++;
          tryPort(port + 1);
        } else {
          reject(err);
        }
      });
    };
    
    tryPort(startPort);
  });
}

// Start server on available port
async function startServer() {
  try {
    const actualPort = await findAvailablePort(PORT);
    
    server.listen(actualPort, () => {
      console.log(`Dashboard server running at http://localhost:${actualPort}`);
      console.log('Press Ctrl+C to stop');
    });

    // Handle server errors gracefully
    server.on('error', (error) => {
      console.error('Server error:', error);
      process.exit(1);
    });
  } catch (error) {
    console.error('Failed to start server:', error.message);
    process.exit(1);
  }
}

startServer();
