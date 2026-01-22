#!/usr/bin/env node
// Test to ensure the server always starts successfully

const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

const SERVER_SCRIPT = path.join(__dirname, 'server.js');
const TEST_PORT = 3001; // Use different port to avoid conflicts
const TIMEOUT = 5000; // 5 second timeout

let serverProcess;
let testPassed = false;
let testFailed = false;
let actualServerPort = null;

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
      
      // Extract port from server output
      const portMatch = data.toString().match(/http:\/\/localhost:(\d+)/);
      if (portMatch) {
        actualServerPort = parseInt(portMatch[1]);
      }
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

      // Try to connect to the server (use actual port if detected, otherwise use TEST_PORT)
      const testUrl = actualServerPort ? `http://localhost:${actualServerPort}` : `http://localhost:${TEST_PORT}`;
      const req = http.get(`${testUrl}/api/status`, (res) => {
        clearInterval(checkInterval);
        if (res.statusCode === 200 || res.statusCode === 500) {
          // 200 = success, 500 = server error but server is running
          console.log('✓ Server started successfully');
          if (!actualServerPort) {
            actualServerPort = TEST_PORT;
          }
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

function httpGetJson(url) {
  return new Promise((resolve, reject) => {
    const req = http.get(url, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk.toString();
      });

      res.on('end', () => {
        const contentType = res.headers['content-type'];
        if (!contentType || !contentType.includes('application/json')) {
          reject(new Error(`Invalid Content-Type: ${contentType}. Expected application/json`));
          return;
        }

        try {
          const json = JSON.parse(data);
          resolve({ statusCode: res.statusCode, json, headers: res.headers });
        } catch (parseError) {
          reject(new Error(`Response is not valid JSON. Status: ${res.statusCode}, Content-Type: ${contentType}, Body: ${data.substring(0, 100)}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(new Error(`Request failed: ${error.message}`));
    });

    req.setTimeout(5000, () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });
  });
}

async function testQueueEndpoint() {
  console.log('Testing queue API endpoint...');

  if (!actualServerPort) {
    throw new Error('Server port not detected');
  }

  const testUrl = `http://localhost:${actualServerPort}`;

  const statusResponse = await httpGetJson(`${testUrl}/api/status`);
  if (statusResponse.statusCode !== 200) {
    throw new Error(`Status endpoint returned ${statusResponse.statusCode}`);
  }

  if (statusResponse.json.error) {
    throw new Error(`Status endpoint error: ${statusResponse.json.error}`);
  }

  const queues = statusResponse.json.queues || [];
  if (!Array.isArray(queues) || queues.length === 0) {
    throw new Error('No queues returned from /api/status');
  }

  const queueName = queues[0].name;
  if (!queueName) {
    throw new Error('Queue name missing from /api/status');
  }

  const queueResponse = await httpGetJson(`${testUrl}/api/queue/${encodeURIComponent(queueName)}`);
  if (queueResponse.statusCode !== 200) {
    throw new Error(`Queue endpoint returned ${queueResponse.statusCode}: ${queueResponse.json.error || 'Unknown error'}`);
  }

  if (!queueResponse.json.queue || !Array.isArray(queueResponse.json.tasks)) {
    throw new Error(`Queue endpoint missing expected data: ${JSON.stringify(queueResponse.json)}`);
  }

  console.log(`✓ Queue endpoint returns valid data for '${queueName}'`);
  return {
    queueName,
    tasks: queueResponse.json.tasks,
  };
}

async function testTaskEndpoint(tasks) {
  console.log('Testing task API endpoint...');

  if (!actualServerPort) {
    throw new Error('Server port not detected');
  }

  if (!tasks || tasks.length === 0) {
    console.log('↷ No tasks in queue to test /api/task; skipping');
    return;
  }

  const taskId = tasks[0].id;
  if (!taskId) {
    throw new Error('Task id missing from queue response');
  }

  const testUrl = `http://localhost:${actualServerPort}`;
  const taskResponse = await httpGetJson(`${testUrl}/api/task/${taskId}`);
  if (taskResponse.statusCode !== 200) {
    throw new Error(`Task endpoint returned ${taskResponse.statusCode}: ${taskResponse.json.error || 'Unknown error'}`);
  }

  if (!taskResponse.json.task || taskResponse.json.task.id !== taskId) {
    throw new Error(`Task endpoint missing expected data: ${JSON.stringify(taskResponse.json)}`);
  }

  console.log(`✓ Task endpoint returns valid data for task #${taskId}`);
}

// Run the test
async function runTest() {
  try {
    await testServerStart();
    const queueResult = await testQueueEndpoint();
    await testTaskEndpoint(queueResult.tasks);
    console.log('\n✅ TEST PASSED: Server starts successfully and queue endpoint works');
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
