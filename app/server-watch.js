#!/usr/bin/env node
// File watcher that restarts the server when files change
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const SERVER_SCRIPT = path.join(__dirname, 'server.js');
const WATCH_DIRS = [
  path.join(__dirname),
  path.join(__dirname, '..', 'lib'),
];

let serverProcess = null;
let restartTimeout = null;

function startServer() {
  console.log('Starting server...');
  serverProcess = spawn('node', [SERVER_SCRIPT], {
    cwd: path.dirname(SERVER_SCRIPT),
    stdio: 'inherit',
    env: { ...process.env }
  });

  serverProcess.on('exit', (code, signal) => {
    if (code !== null && code !== 0) {
      console.error(`Server exited with code ${code}`);
    } else if (signal) {
      console.log(`Server killed by signal ${signal}`);
    }
    serverProcess = null;
  });

  serverProcess.on('error', (error) => {
    console.error('Failed to start server:', error);
    serverProcess = null;
  });
}

function stopServer() {
  if (serverProcess) {
    console.log('Stopping server...');
    serverProcess.kill('SIGTERM');
    serverProcess = null;
  }
}

function restartServer() {
  if (restartTimeout) {
    clearTimeout(restartTimeout);
  }
  
  restartTimeout = setTimeout(() => {
    console.log('\n🔄 File change detected, restarting server...\n');
    stopServer();
    setTimeout(() => {
      startServer();
    }, 500);
  }, 300); // Debounce: wait 300ms for multiple file changes
}

function watchDirectory(dir) {
  if (!fs.existsSync(dir)) {
    return;
  }

  fs.watch(dir, { recursive: true }, (eventType, filename) => {
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
      console.log(`File changed: ${filename}`);
      restartServer();
    }
  });
}

// Start initial server
startServer();

// Watch directories
WATCH_DIRS.forEach(dir => {
  if (fs.existsSync(dir)) {
    watchDirectory(dir);
    console.log(`Watching: ${dir}`);
  }
});

// Handle cleanup
process.on('SIGINT', () => {
  console.log('\nShutting down...');
  stopServer();
  process.exit(0);
});

process.on('SIGTERM', () => {
  stopServer();
  process.exit(0);
});

console.log('File watcher started. Press Ctrl+C to stop.');
