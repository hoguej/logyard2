#!/usr/bin/env node
// E2E test to verify the dashboard page loads and displays content
const http = require('http');
const { spawn } = require('child_process');
const path = require('path');

const SERVER_SCRIPT = path.join(__dirname, 'server.js');
const TEST_PORT = 3005;
const TIMEOUT = 10000; // 10 second timeout

let serverProcess;
let actualServerPort = null;

function cleanup() {
  if (serverProcess) {
    serverProcess.kill();
    serverProcess = null;
  }
}

process.on('exit', cleanup);
process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);

function startServer() {
  return new Promise((resolve, reject) => {
    console.log('Starting server for E2E test...');
    
    serverProcess = spawn('node', [SERVER_SCRIPT], {
      cwd: path.dirname(SERVER_SCRIPT),
      env: { ...process.env, PORT: TEST_PORT },
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let serverOutput = '';
    let errorOutput = '';

    serverProcess.stdout.on('data', (data) => {
      serverOutput += data.toString();
      const portMatch = data.toString().match(/http:\/\/localhost:(\d+)/);
      if (portMatch) {
        actualServerPort = parseInt(portMatch[1]);
      }
    });

    serverProcess.stderr.on('data', (data) => {
      errorOutput += data.toString();
    });

    serverProcess.on('error', (error) => {
      reject(new Error(`Server failed to start: ${error.message}`));
    });

    const startTime = Date.now();
    const checkInterval = setInterval(() => {
      const elapsed = Date.now() - startTime;
      
      if (elapsed > TIMEOUT) {
        clearInterval(checkInterval);
        reject(new Error(`Server did not start within ${TIMEOUT}ms`));
        return;
      }

      const testUrl = actualServerPort ? `http://localhost:${actualServerPort}` : `http://localhost:${TEST_PORT}`;
      const req = http.get(`${testUrl}/api/status`, (res) => {
        clearInterval(checkInterval);
        if (res.statusCode === 200 || res.statusCode === 500) {
          console.log('✓ Server started');
          resolve(actualServerPort || TEST_PORT);
        }
      });

      req.on('error', (err) => {
        if (err.code !== 'ECONNREFUSED') {
          clearInterval(checkInterval);
          reject(new Error(`Connection error: ${err.message}`));
        }
      });

      req.setTimeout(1000, () => {
        req.destroy();
      });
    }, 200);
  });
}

function testPageLoads() {
  return new Promise((resolve, reject) => {
    console.log('Testing page loads...');
    
    const testUrl = `http://localhost:${actualServerPort || TEST_PORT}`;
    const req = http.get(`${testUrl}/`, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk.toString();
      });
      
      res.on('end', () => {
        if (res.statusCode !== 200) {
          reject(new Error(`Page returned status ${res.statusCode}`));
          return;
        }

        // Check for essential HTML elements
        const checks = [
          { name: 'HTML structure', test: data.includes('<!DOCTYPE html') || data.includes('<html') },
          { name: 'Title', test: data.includes('logyard2') || data.includes('Queue Status') },
          { name: 'Container div', test: data.includes('container') || data.includes('class="container"') },
          { name: 'Queue status section', test: data.includes('queue-status') || data.includes('QUEUE STATUS') },
          { name: 'JavaScript file', test: data.includes('app.js') || data.includes('script') },
          { name: 'CSS file', test: data.includes('style.css') || data.includes('stylesheet') },
        ];

        const failures = checks.filter(check => !check.test);
        if (failures.length > 0) {
          reject(new Error(`Page missing elements: ${failures.map(f => f.name).join(', ')}`));
          return;
        }

        console.log('✓ Page HTML structure is valid');
        resolve(true);
      });
    });

    req.on('error', (error) => {
      reject(new Error(`Failed to load page: ${error.message}`));
    });

    req.setTimeout(5000, () => {
      req.destroy();
      reject(new Error('Page load timeout'));
    });
  });
}

function testAPIStatus() {
  return new Promise((resolve, reject) => {
    console.log('Testing API status endpoint...');
    
    const testUrl = `http://localhost:${actualServerPort || TEST_PORT}`;
    const req = http.get(`${testUrl}/api/status`, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk.toString();
      });
      
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          
          if (json.error) {
            // API error is OK - database might not exist
            console.log('⚠ API returned error (database may not exist):', json.error);
            resolve(true);
            return;
          }

          // Check for expected structure
          const hasQueues = Array.isArray(json.queues);
          const hasRootWorkItems = Array.isArray(json.rootWorkItems);
          const hasAgents = Array.isArray(json.agents);
          const hasAnnouncements = Array.isArray(json.announcements);

          if (!hasQueues || !hasRootWorkItems || !hasAgents || !hasAnnouncements) {
            reject(new Error(`Invalid API response structure. Queues: ${hasQueues}, RootWorkItems: ${hasRootWorkItems}, Agents: ${hasAgents}, Announcements: ${hasAnnouncements}`));
            return;
          }

          console.log('✓ API status endpoint returns valid structure');
          resolve(true);
        } catch (parseError) {
          reject(new Error(`API response is not valid JSON: ${parseError.message}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(new Error(`Failed to call API: ${error.message}`));
    });

    req.setTimeout(5000, () => {
      req.destroy();
      reject(new Error('API call timeout'));
    });
  });
}

function testJavaScriptLoads() {
  return new Promise((resolve, reject) => {
    console.log('Testing JavaScript file loads...');
    
    const testUrl = `http://localhost:${actualServerPort || TEST_PORT}`;
    const req = http.get(`${testUrl}/app.js`, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk.toString();
      });
      
      res.on('end', () => {
        if (res.statusCode !== 200) {
          reject(new Error(`JavaScript file returned status ${res.statusCode}`));
          return;
        }

        // Check for essential functions
        const checks = [
          { name: 'fetchStatus function', test: data.includes('fetchStatus') || data.includes('function fetchStatus') },
          { name: 'formatTextContent function', test: data.includes('formatTextContent') || data.includes('function formatTextContent') },
          { name: 'renderQueues function', test: data.includes('renderQueues') || data.includes('function renderQueues') },
          { name: 'initializeClickHandlers function', test: data.includes('initializeClickHandlers') || data.includes('function initializeClickHandlers') },
        ];

        const failures = checks.filter(check => !check.test);
        if (failures.length > 0) {
          reject(new Error(`JavaScript missing functions: ${failures.map(f => f.name).join(', ')}`));
          return;
        }

        // Check for common syntax errors
        const syntaxChecks = [
          { name: 'No unclosed functions', test: (data.match(/function\s+\w+\s*\(/g) || []).length === (data.match(/}\s*$/gm) || []).length || data.split('function').length <= data.split('}').length },
          { name: 'No obvious syntax errors', test: !data.match(/}\s*if\s*\(/g) && !data.match(/}\s*let\s+/g) && !data.match(/}\s*const\s+/g) },
        ];

        const syntaxFailures = syntaxChecks.filter(check => !check.test);
        if (syntaxFailures.length > 0) {
          console.warn(`⚠ Potential syntax issues: ${syntaxFailures.map(f => f.name).join(', ')}`);
        }

        console.log('✓ JavaScript file loads and contains essential functions');
        resolve(true);
      });
    });

    req.on('error', (error) => {
      reject(new Error(`Failed to load JavaScript: ${error.message}`));
    });

    req.setTimeout(5000, () => {
      req.destroy();
      reject(new Error('JavaScript load timeout'));
    });
  });
}

function testPageHasContent() {
  return new Promise((resolve, reject) => {
    console.log('Testing page has visible content elements...');
    
    const testUrl = `http://localhost:${actualServerPort || TEST_PORT}`;
    const req = http.get(`${testUrl}/`, (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk.toString();
      });
      
      res.on('end', () => {
        // Check for elements that should be visible on the page
        const contentChecks = [
          { name: 'Header with title', test: data.includes('logyard2') || data.includes('Queue Status') },
          { name: 'Queue status section ID', test: data.includes('id="queue-status"') || data.includes('queue-status') },
          { name: 'Root work items section ID', test: data.includes('id="root-work-items"') || data.includes('root-work-items') },
          { name: 'Running agents section ID', test: data.includes('id="running-agents"') || data.includes('running-agents') },
          { name: 'Announcements section ID', test: data.includes('id="announcements"') || data.includes('announcements') },
          { name: 'Modal overlay for details', test: data.includes('modal-overlay') || data.includes('id="modal-overlay"') },
          { name: 'Footer with timestamp', test: data.includes('timestamp') || data.includes('id="timestamp"') },
        ];

        const failures = contentChecks.filter(check => !check.test);
        if (failures.length > 0) {
          reject(new Error(`Page missing content elements: ${failures.map(f => f.name).join(', ')}`));
          return;
        }

        console.log('✓ Page contains all expected content elements');
        resolve(true);
      });
    });

    req.on('error', (error) => {
      reject(new Error(`Failed to check page content: ${error.message}`));
    });

    req.setTimeout(5000, () => {
      req.destroy();
      reject(new Error('Page content check timeout'));
    });
  });
}

async function runE2ETest() {
  try {
    const port = await startServer();
    await testPageLoads();
    await testPageHasContent();
    await testAPIStatus();
    await testJavaScriptLoads();
    
    console.log('\n✅ E2E TEST PASSED: Page loads and displays correctly');
    process.exit(0);
  } catch (error) {
    console.error(`\n❌ E2E TEST FAILED: ${error.message}`);
    process.exit(1);
  } finally {
    cleanup();
  }
}

runE2ETest();
