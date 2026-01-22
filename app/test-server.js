#!/usr/bin/env node
// Test to ensure the server always starts successfully

const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

const SERVER_SCRIPT = path.join(__dirname, 'server.js');
const TEST_PORT = 3001; // Use different port to avoid conflicts
const TEST_URL = `http://localhost:${TEST_PORT}`;
const TIMEOUT = 5000; // 5 second timeout

let serverProcess;
let testPassed = false;
let testFailed = false;

function cleanup() {
  if (serverProcess) {
    serverProcess.kill();
    serverProcess = null;
  }
}

// Cleanup on exit
process.on('exit', cleanup);
process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);

function testServerStart() {
  return new Promise((resolve, reject) => {
    console.log('Starting server test...');
    console.log(`Testing: ${SERVER_SCRIPT}`);
    
    // Start the server
    serverProcess = spawn('node', [SERVER_SCRIPT], {
      cwd: path.dirname(SERVER_SCRIPT),
      env: { ...process.env, PORT: TEST_PORT },
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let serverOutput = '';
    let errorOutput = '';

    serverProcess.stdout.on('data', (data) => {
      serverOutput += data.toString();
      console.log(`[SERVER] ${data.toString().trim()}`);
    });

    serverProcess.stderr.on('data', (data) => {
      errorOutput += data.toString();
      console.error(`[SERVER ERROR] ${data.toString().trim()}`);
    });

    serverProcess.on('error', (error) => {
      console.error(`Failed to start server: ${error.message}`);
      reject(new Error(`Server failed to start: ${error.message}`));
    });

    serverProcess.on('exit', (code, signal) => {
      if (code !== null && code !== 0) {
        reject(new Error(`Server exited with code ${code}. Output: ${serverOutput}\nErrors: ${errorOutput}`));
      } else if (signal) {
        reject(new Error(`Server killed by signal ${signal}`));
      }
    });

    // Wait for server to be ready
    const startTime = Date.now();
    const checkInterval = setInterval(() => {
      const elapsed = Date.now() - startTime;
      
      if (elapsed > TIMEOUT) {
        clearInterval(checkInterval);
        reject(new Error(`Server did not start within ${TIMEOUT}ms. Output: ${serverOutput}\nErrors: ${errorOutput}`));
        return;
      }

      // Try to connect to the server
      const req = http.get(`${TEST_URL}/api/status`, (res) => {
        clearInterval(checkInterval);
        if (res.statusCode === 200 || res.statusCode === 500) {
          // 200 = success, 500 = server error but server is running
          console.log('✓ Server started successfully');
          resolve(true);
        } else {
          reject(new Error(`Server responded with status ${res.statusCode}`));
        }
      });

      req.on('error', (err) => {
        // Connection refused - server not ready yet, keep trying
        if (err.code === 'ECONNREFUSED') {
          return; // Continue checking
        }
        // Other errors - might be a problem
        if (elapsed > 2000) {
          clearInterval(checkInterval);
          reject(new Error(`Connection error after 2s: ${err.message}`));
        }
      });

      req.setTimeout(1000, () => {
        req.destroy();
      });
    }, 200); // Check every 200ms
  });
}

// Run the test
async function runTest() {
  try {
    await testServerStart();
    console.log('\n✅ TEST PASSED: Server starts successfully');
    testPassed = true;
    process.exit(0);
  } catch (error) {
    console.error(`\n❌ TEST FAILED: ${error.message}`);
    testFailed = true;
    process.exit(1);
  } finally {
    cleanup();
  }
}

runTest();
