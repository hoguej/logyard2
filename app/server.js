#!/usr/bin/env node
// Simple HTTP server to serve the dashboard and provide JSON API
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PORT = process.env.PORT || 3000;
const PROJECT_ROOT = path.resolve(__dirname, '..');
const DB_FILE = path.join(PROJECT_ROOT, '.agent-queue.db');

// Simple markdown to HTML converter
function markdownToHtml(markdown) {
  let html = markdown;
  
  // Headers
  html = html.replace(/^### (.*$)/gim, '<h3>$1</h3>');
  html = html.replace(/^## (.*$)/gim, '<h2>$1</h2>');
  html = html.replace(/^# (.*$)/gim, '<h1>$1</h1>');
  
  // Bold
  html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/__(.*?)__/g, '<strong>$1</strong>');
  
  // Italic
  html = html.replace(/\*(.*?)\*/g, '<em>$1</em>');
  html = html.replace(/_(.*?)_/g, '<em>$1</em>');
  
  // Code blocks
  html = html.replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>');
  html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
  
  // Links
  html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank">$1</a>');
  
  // Lists
  html = html.replace(/^\* (.*$)/gim, '<li>$1</li>');
  html = html.replace(/^- (.*$)/gim, '<li>$1</li>');
  html = html.replace(/^(\d+)\. (.*$)/gim, '<li>$2</li>');
  
  // Wrap consecutive list items in ul
  html = html.replace(/(<li>.*<\/li>\n?)+/g, '<ul>$&</ul>');
  
  // Paragraphs (lines that aren't already wrapped)
  html = html.split('\n').map(line => {
    if (line.trim() && !line.match(/^<[h|u|o|p|d]/) && !line.match(/^<\/[h|u|o|p|d]/) && !line.match(/^<li>/) && !line.match(/^<\/li>/) && !line.match(/^<pre>/) && !line.match(/^<\/pre>/)) {
      return `<p>${line}</p>`;
    }
    return line;
  }).join('\n');
  
  // Line breaks
  html = html.replace(/\n/g, '<br>');
  
  return html;
}

// MIME types
const mimeTypes = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
};

const server = http.createServer((req, res) => {
  // Wrap everything in try-catch to ensure we always return JSON on errors
  try {
    // Set default error handler to always return JSON
    const sendError = (statusCode, message) => {
      if (!res.headersSent) {
        res.writeHead(statusCode, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: message }));
      }
    };

    // Handle uncaught errors
    req.on('error', (err) => {
      console.error('Request error:', err);
      sendError(500, err.message);
    });

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

  // API endpoint for queue tasks
  const queueMatch = req.url.match(/^\/api\/queue\/([^\/]+)$/);
  if (queueMatch) {
    try {
      const queueName = decodeURIComponent(queueMatch[1]);
      const result = getQueueTasks(queueName);
      
      // Check if result has an error
      if (result && result.error) {
        if (!res.headersSent) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(result));
        }
      } else if (result) {
        if (!res.headersSent) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(result, null, 2));
        }
      } else {
        if (!res.headersSent) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Unexpected response from getQueueTasks' }));
        }
      }
    } catch (error) {
      console.error('Error in queue endpoint:', error);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: error.message || 'Internal server error' }));
      }
    }
    return;
  }

  // API endpoint for task details
  const taskMatch = req.url.match(/^\/api\/task\/(\d+)$/);
  if (taskMatch) {
    try {
      const taskId = parseInt(taskMatch[1]);
      const task = getTaskDetails(taskId);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(task, null, 2));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    }
    return;
  }

  // API endpoint for root work item details
  const rootWorkItemMatch = req.url.match(/^\/api\/root-work-item\/(\d+)$/);
  if (rootWorkItemMatch) {
    try {
      const rootWorkItemId = parseInt(rootWorkItemMatch[1]);
      const item = getRootWorkItemDetails(rootWorkItemId);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(item, null, 2));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    }
    return;
  }

  // API endpoint for agent details
  const agentMatch = req.url.match(/^\/api\/agent\/([^\/]+)$/);
  if (agentMatch) {
    try {
      const agentName = decodeURIComponent(agentMatch[1]);
      const agent = getAgentDetails(agentName);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(agent, null, 2));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    }
    return;
  }

  // API endpoint for announcement details
  const announcementMatch = req.url.match(/^\/api\/announcement\/(\d+)$/);
  if (announcementMatch) {
    try {
      const announcementId = parseInt(announcementMatch[1]);
      const announcement = getAnnouncementDetails(announcementId);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(announcement, null, 2));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    }
    return;
  }

  // Server-Sent Events endpoint for file change notifications
  if (req.url === '/api/reload') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });

    // Send initial connection message
    res.write('data: connected\n\n');

    // Watch for file changes
    const watchDirs = [
      __dirname,
      path.join(PROJECT_ROOT, 'lib'),
    ];

    const watchers = [];
    watchDirs.forEach(dir => {
      if (fs.existsSync(dir)) {
        const watcher = fs.watch(dir, { recursive: true }, (eventType, filename) => {
          if (!filename) return;
          
          // Ignore certain files
          if (filename.includes('node_modules') || 
              filename.includes('.git') ||
              filename.endsWith('.db') ||
              filename.endsWith('.log')) {
            return;
          }

          // Only watch relevant file types
          const ext = path.extname(filename);
          if (['.js', '.html', '.css', '.md'].includes(ext) || !ext) {
            res.write(`data: reload\n\n`);
          }
        });
        watchers.push(watcher);
      }
    });

    // Clean up on client disconnect
    req.on('close', () => {
      watchers.forEach(watcher => watcher.close());
    });

    return;
  }

  // Server-Sent Events endpoint for file change notifications
  if (req.url === '/api/reload') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });

    // Send initial connection message
    res.write('data: connected\n\n');

    // Watch for file changes
    const watchDirs = [
      __dirname,
      path.join(PROJECT_ROOT, 'lib'),
    ];

    const watchers = [];
    watchDirs.forEach(dir => {
      if (fs.existsSync(dir)) {
        const watcher = fs.watch(dir, { recursive: true }, (eventType, filename) => {
          if (!filename) return;
          
          // Ignore certain files
          if (filename.includes('node_modules') || 
              filename.includes('.git') ||
              filename.endsWith('.db') ||
              filename.endsWith('.log')) {
            return;
          }

          // Only watch relevant file types
          const ext = path.extname(filename);
          if (['.js', '.html', '.css', '.md'].includes(ext) || !ext) {
            res.write(`data: reload\n\n`);
          }
        });
        watchers.push(watcher);
      }
    });

    // Clean up on client disconnect
    req.on('close', () => {
      watchers.forEach(watcher => watcher.close());
    });

    return;
  }

  // API endpoint for markdown files
  const fileMatch = req.url.match(/^\/api\/file\?path=(.+)$/);
  if (fileMatch) {
    try {
      const filePath = decodeURIComponent(fileMatch[1]);
      const fullPath = path.join(PROJECT_ROOT, filePath);
      
      // Security: ensure path is within project root
      if (!fullPath.startsWith(PROJECT_ROOT)) {
        res.writeHead(403, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Access denied' }));
        return;
      }
      
      // Check if file exists and is markdown
      if (!fs.existsSync(fullPath)) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'File not found' }));
        return;
      }
      
      const ext = path.extname(fullPath).toLowerCase();
      if (ext !== '.md' && ext !== '.markdown') {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'File is not markdown' }));
        return;
      }
      
      const content = fs.readFileSync(fullPath, 'utf8');
      const html = markdownToHtml(content);
      
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ 
        path: filePath,
        content: content,
        html: html
      }));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    }
    return;
  }

    // Serve static files (only if not an API route)
    if (req.url.startsWith('/api/')) {
      // This shouldn't happen if all API routes are handled above
      if (!res.headersSent) {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'API endpoint not found' }));
      }
      return;
    }

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
  } catch (error) {
    console.error('Unhandled error in request handler:', error);
    if (!res.headersSent) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message || 'Internal server error' }));
    }
  }
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
      `sqlite3 -json "${DB_FILE}" "SELECT id, type, agent_name, message, created_at FROM announcements ORDER BY created_at DESC LIMIT 5;"`,
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

function getQueueTasks(queueName) {
  if (!fs.existsSync(DB_FILE)) {
    return { error: 'Database not found' };
  }

  try {
    // Escape queue name for SQL to prevent injection
    const escapedQueueName = queueName.replace(/'/g, "''");
    
    let queueData;
    try {
      queueData = execSync(
        `sqlite3 -json "${DB_FILE}" "SELECT q.id as id, q.name, q.description FROM queues q WHERE q.name = '${escapedQueueName}';"`,
        { encoding: 'utf8', cwd: PROJECT_ROOT, maxBuffer: 10 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'] }
      );
    } catch (execError) {
      console.error('Error executing sqlite3 query for queue:', execError);
      return { error: 'Database query failed: ' + (execError.message || 'Unknown error') };
    }

    if (!queueData || !queueData.trim()) {
      return { error: 'Queue not found' };
    }

    let queue;
    try {
      const parsed = JSON.parse(queueData);
      queue = Array.isArray(parsed) ? parsed[0] : parsed;
    } catch (parseError) {
      console.error('Error parsing queue data:', parseError, 'Raw data:', queueData.substring(0, 200));
      return { error: 'Failed to parse queue data' };
    }

    if (!queue || !queue.id) {
      return { error: 'Queue not found' };
    }

    const queueId = queue.id;

    let tasksData;
    try {
      tasksData = execSync(
        `sqlite3 -json "${DB_FILE}" "SELECT t.id, t.title, t.description, t.status, t.priority, t.created_at, t.claimed_at, t.claimed_by, t.completed_at, t.result, t.error, qt.status as queue_status FROM tasks t JOIN queue_tasks qt ON t.id = qt.task_id WHERE qt.queue_id = ${queueId} ORDER BY t.priority DESC, t.created_at ASC;"`,
        { encoding: 'utf8', cwd: PROJECT_ROOT, maxBuffer: 10 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'] }
      );
    } catch (execError) {
      console.error('Error executing sqlite3 query for tasks:', execError);
      // Return queue info with empty tasks if tasks query fails
      return {
        queue: queue,
        tasks: [],
      };
    }

    let tasks = [];
    if (tasksData && tasksData.trim()) {
      try {
        const parsed = JSON.parse(tasksData);
        tasks = Array.isArray(parsed) ? parsed : [parsed];
      } catch (parseError) {
        console.error('Error parsing tasks data:', parseError);
        // Return empty tasks array if parsing fails
        tasks = [];
      }
    }

    return {
      queue: queue,
      tasks: tasks,
    };
  } catch (error) {
    console.error('Error fetching queue tasks:', error);
    return { error: error.message || 'Unknown error occurred' };
  }
}

function getTaskDetails(taskId) {
  if (!fs.existsSync(DB_FILE)) {
    return { error: 'Database not found' };
  }

  try {
    const taskData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT t.*, qt.queue_id, q.name as queue_name FROM tasks t LEFT JOIN queue_tasks qt ON t.id = qt.task_id LEFT JOIN queues q ON qt.queue_id = q.id WHERE t.id = ${taskId};"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );

    if (!taskData.trim()) {
      return { error: 'Task not found' };
    }

    const task = JSON.parse(taskData);
    const taskObj = Array.isArray(task) ? task[0] : task;

    // Get child tasks if any
    const childTasksData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT id, title, status, queue_type FROM tasks WHERE parent_task_id = ${taskId} ORDER BY created_at ASC;"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );

    const childTasks = childTasksData.trim() ? JSON.parse(childTasksData) : [];

    // Get parent task if any
    let parentTask = null;
    if (taskObj.parent_task_id) {
      const parentData = execSync(
        `sqlite3 -json "${DB_FILE}" "SELECT id, title, status FROM tasks WHERE id = ${taskObj.parent_task_id};"`,
        { encoding: 'utf8', cwd: PROJECT_ROOT }
      );
      if (parentData.trim()) {
        const parsed = JSON.parse(parentData);
        parentTask = Array.isArray(parsed) ? parsed[0] : parsed;
      }
    }

    // Get root work item if any
    let rootWorkItem = null;
    if (taskObj.root_work_item_id) {
      const rootData = execSync(
        `sqlite3 -json "${DB_FILE}" "SELECT id, title, status FROM root_work_items WHERE id = ${taskObj.root_work_item_id};"`,
        { encoding: 'utf8', cwd: PROJECT_ROOT }
      );
      if (rootData.trim()) {
        const parsed = JSON.parse(rootData);
        rootWorkItem = Array.isArray(parsed) ? parsed[0] : parsed;
      }
    }

    return {
      task: taskObj,
      parentTask,
      rootWorkItem,
      childTasks: Array.isArray(childTasks) ? childTasks : (childTasks ? [childTasks] : []),
    };
  } catch (error) {
    console.error('Error fetching task details:', error);
    return { error: error.message };
  }
}

function getRootWorkItemDetails(rootWorkItemId) {
  if (!fs.existsSync(DB_FILE)) {
    return { error: 'Database not found' };
  }

  try {
    const rootData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT * FROM root_work_items WHERE id = ${rootWorkItemId};"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );

    if (!rootData.trim()) {
      return { error: 'Root work item not found' };
    }

    const rootItem = JSON.parse(rootData);
    const rootObj = Array.isArray(rootItem) ? rootItem[0] : rootItem;

    // Get all tasks for this root work item
    const tasksData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT t.id, t.title, t.status, t.queue_type, t.priority, t.created_at, t.completed_at, qt.queue_id, q.name as queue_name FROM tasks t LEFT JOIN queue_tasks qt ON t.id = qt.task_id LEFT JOIN queues q ON qt.queue_id = q.id WHERE t.root_work_item_id = ${rootWorkItemId} ORDER BY t.created_at ASC;"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );

    const tasks = tasksData.trim() ? JSON.parse(tasksData) : [];

    return {
      rootWorkItem: rootObj,
      tasks: Array.isArray(tasks) ? tasks : (tasks ? [tasks] : []),
    };
  } catch (error) {
    console.error('Error fetching root work item details:', error);
    return { error: error.message };
  }
}

function getAgentDetails(agentName) {
  if (!fs.existsSync(DB_FILE)) {
    return { error: 'Database not found' };
  }

  try {
    const agentData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT * FROM agents WHERE name = '${agentName}' ORDER BY last_heartbeat DESC;"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );

    const agents = agentData.trim() ? JSON.parse(agentData) : [];

    // Get tasks claimed by this agent
    const tasksData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT t.id, t.title, t.status, t.queue_type, qt.queue_id, q.name as queue_name FROM tasks t LEFT JOIN queue_tasks qt ON t.id = qt.task_id LEFT JOIN queues q ON qt.queue_id = q.id WHERE t.claimed_by = '${agentName}' AND t.status IN ('in_progress', 'queued') ORDER BY t.claimed_at DESC;"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );

    const tasks = tasksData.trim() ? JSON.parse(tasksData) : [];

    return {
      agents: Array.isArray(agents) ? agents : (agents ? [agents] : []),
      activeTasks: Array.isArray(tasks) ? tasks : (tasks ? [tasks] : []),
    };
  } catch (error) {
    console.error('Error fetching agent details:', error);
    return { error: error.message };
  }
}

function getAnnouncementDetails(announcementId) {
  if (!fs.existsSync(DB_FILE)) {
    return { error: 'Database not found' };
  }

  try {
    const announcementData = execSync(
      `sqlite3 -json "${DB_FILE}" "SELECT * FROM announcements WHERE id = ${announcementId};"`,
      { encoding: 'utf8', cwd: PROJECT_ROOT }
    );

    if (!announcementData.trim()) {
      return { error: 'Announcement not found' };
    }

    const announcement = JSON.parse(announcementData);
    const annObj = Array.isArray(announcement) ? announcement[0] : announcement;

    // Get related task if any
    let task = null;
    if (annObj.task_id) {
      const taskData = execSync(
        `sqlite3 -json "${DB_FILE}" "SELECT id, title, status FROM tasks WHERE id = ${annObj.task_id};"`,
        { encoding: 'utf8', cwd: PROJECT_ROOT }
      );
      if (taskData.trim()) {
        const parsed = JSON.parse(taskData);
        task = Array.isArray(parsed) ? parsed[0] : parsed;
      }
    }

    return {
      announcement: annObj,
      relatedTask: task,
    };
  } catch (error) {
    console.error('Error fetching announcement details:', error);
    return { error: error.message };
  }
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

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  // Don't exit, just log
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  // Don't exit, just log
});

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
