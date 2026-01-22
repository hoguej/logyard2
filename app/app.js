// Queue Status Dashboard
let refreshInterval;
let refreshCount = 0;
let navigationHistory = [];
let handlersInitialized = false;

// Queue name mapping
const queueNames = {
    'requirements-research': '📋 Research',
    'planning': '📝 Planning',
    'execution': '⚙️  Execution',
    'pre-commit-check': '✅ Pre-Commit',
    'commit-build': '🔨 Commit/Build',
    'deploy': '🚀 Deploy',
    'e2e-test': '🧪 E2E Test',
    'announce': '📢 Announce',
};

// Status emoji mapping
const statusEmojis = {
    'pending': '⏳',
    'researching': '🔍',
    'planning': '📝',
    'executing': '⚙️ ',
    'checking': '✅',
    'building': '🔨',
    'deploying': '🚀',
    'testing': '🧪',
    'completed': '✅',
    'failed': '❌',
};

function formatTime(dateString) {
    if (!dateString) return '';
    const date = new Date(dateString);
    return date.toLocaleTimeString();
}

// Format task result to detect and link PRs and markdown files
function formatTaskResult(result) {
    if (!result) return '';
    
    let formatted = escapeHtml(result);
    
    // Detect PR links: "PR #123" or "PR created: https://github.com/..." or "https://github.com/.../pull/123"
    const prPatterns = [
        /PR #(\d+)/gi,
        /(https?:\/\/github\.com\/[^\/]+\/[^\/]+\/pull\/\d+)/gi,
        /PR created: (https?:\/\/[^\s]+)/gi,
        /PR: (https?:\/\/[^\s]+)/gi
    ];
    
    prPatterns.forEach(pattern => {
        formatted = formatted.replace(pattern, (match, urlOrNum) => {
            let prUrl;
            if (urlOrNum.match(/^https?:\/\//)) {
                prUrl = urlOrNum;
            } else {
                // Assume it's a PR number, construct URL (you may need to adjust the repo path)
                prUrl = `https://github.com/hoguej/logyard2/pull/${urlOrNum}`;
            }
            return `<a href="${prUrl}" target="_blank" class="pr-link">${match}</a>`;
        });
    });
    
    // Detect markdown file references: "requirements/00-overview.md" or "/requirements/00-overview.md"
    const mdPattern = /([\/]?[a-zA-Z0-9_\/-]+\.md)/g;
    formatted = formatted.replace(mdPattern, (match, filePath) => {
        // Remove leading slash if present for consistency
        const cleanPath = filePath.startsWith('/') ? filePath.substring(1) : filePath;
        return `<span class="file-link clickable" data-file-path="${cleanPath}">${match}</span>`;
    });
    
    return formatted;
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function formatDateTime(dateString) {
    if (!dateString) return '';
    const date = new Date(dateString);
    return date.toLocaleString();
}

function drawProgressBar(queued, working, max = 20) {
    const total = queued + working;
    if (total === 0) {
        return '<div class="progress-bar"><div class="progress-empty" style="width: 100%"></div></div>';
    }

    const workingWidth = (working / total) * 100;
    const queuedWidth = (queued / total) * 100;

    return `
        <div class="progress-bar">
            <div class="progress-working" style="width: ${workingWidth}%"></div>
            <div class="progress-queued" style="width: ${queuedWidth}%"></div>
        </div>
    `;
}

// Modal functions
function showModal(title, content, showBack = false) {
    const overlay = document.getElementById('modal-overlay');
    const modalTitle = document.getElementById('modal-title');
    const modalBody = document.getElementById('modal-body');
    const backBtn = document.getElementById('modal-back');
    
    modalTitle.textContent = title;
    modalBody.innerHTML = content;
    overlay.style.display = 'flex';
    backBtn.style.display = showBack ? 'block' : 'none';
}

function hideModal() {
    document.getElementById('modal-overlay').style.display = 'none';
    navigationHistory = [];
}

function navigateTo(title, content) {
    navigationHistory.push({ title, content });
    showModal(title, content, navigationHistory.length > 1);
}

function navigateBack() {
    if (navigationHistory.length > 1) {
        navigationHistory.pop();
        const current = navigationHistory[navigationHistory.length - 1];
        showModal(current.title, current.content, navigationHistory.length > 1);
    } else {
        hideModal();
    }
}

// Detail view renderers
function renderQueueDetails(data) {
    if (data.error) {
        return `<div class="modal-section"><p>Error: ${data.error}</p></div>`;
    }

    const queue = data.queue;
    const tasks = data.tasks || [];

    let html = `
        <div class="modal-section">
            <h3>Queue Information</h3>
            <div class="modal-field">
                <div class="modal-field-label">Name</div>
                <div class="modal-field-value">${queueNames[queue.name] || queue.name}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Description</div>
                <div class="modal-field-value">${queue.description || 'N/A'}</div>
            </div>
        </div>
    `;

    if (tasks.length > 0) {
        html += `
            <div class="modal-section">
                <h3>Tasks (${tasks.length})</h3>
                <ul class="modal-list">
                    ${tasks.map(task => {
                        const emoji = statusEmojis[task.status] || '❓';
                        return `
                            <li class="modal-list-item clickable" data-task-id="${task.id}">
                                ${emoji} [${task.id}] ${task.title} - ${task.status}
                                ${task.claimed_by ? ` (claimed by ${task.claimed_by})` : ''}
                            </li>
                        `;
                    }).join('')}
                </ul>
            </div>
        `;
    } else {
        html += `<div class="modal-section"><p>No tasks in this queue</p></div>`;
    }

    return html;
}

function renderTaskDetails(data) {
    if (data.error) {
        return `<div class="modal-section"><p>Error: ${data.error}</p></div>`;
    }

    const task = data.task;
    const parentTask = data.parentTask;
    const rootWorkItem = data.rootWorkItem;
    const childTasks = data.childTasks || [];

    let html = `
        <div class="modal-section">
            <h3>Task Information</h3>
            <div class="modal-field">
                <div class="modal-field-label">ID</div>
                <div class="modal-field-value">${task.id}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Title</div>
                <div class="modal-field-value">${task.title || 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Description</div>
                <div class="modal-field-value">${task.description || 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Status</div>
                <div class="modal-field-value">${task.status || 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Priority</div>
                <div class="modal-field-value">${task.priority || 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Queue</div>
                <div class="modal-field-value">${task.queue_name ? queueNames[task.queue_name] || task.queue_name : 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Created</div>
                <div class="modal-field-value">${formatDateTime(task.created_at)}</div>
            </div>
            ${task.claimed_at ? `
            <div class="modal-field">
                <div class="modal-field-label">Claimed At</div>
                <div class="modal-field-value">${formatDateTime(task.claimed_at)}</div>
            </div>
            ` : ''}
            ${task.claimed_by ? `
            <div class="modal-field">
                <div class="modal-field-label">Claimed By</div>
                <div class="modal-field-value clickable" data-agent-name="${task.claimed_by}">${task.claimed_by}</div>
            </div>
            ` : ''}
            ${task.completed_at ? `
            <div class="modal-field">
                <div class="modal-field-label">Completed At</div>
                <div class="modal-field-value">${formatDateTime(task.completed_at)}</div>
            </div>
            ` : ''}
            ${task.result ? `
            <div class="modal-field">
                <div class="modal-field-label">Result</div>
                <div class="modal-field-value">${formatTaskResult(task.result)}</div>
            </div>
            ` : ''}
            ${task.error ? `
            <div class="modal-field">
                <div class="modal-field-label">Error</div>
                <div class="modal-field-value" style="color: #f44336;">${task.error}</div>
            </div>
            ` : ''}
        </div>
    `;

    if (parentTask) {
        html += `
            <div class="modal-section">
                <h3>Parent Task</h3>
                <div class="modal-list-item clickable" data-task-id="${parentTask.id}">
                    [${parentTask.id}] ${parentTask.title} - ${parentTask.status}
                </div>
            </div>
        `;
    }

    if (rootWorkItem) {
        html += `
            <div class="modal-section">
                <h3>Root Work Item</h3>
                <div class="modal-list-item clickable" data-root-work-item-id="${rootWorkItem.id}">
                    [${rootWorkItem.id}] ${rootWorkItem.title} - ${rootWorkItem.status}
                </div>
            </div>
        `;
    }

    if (childTasks.length > 0) {
        html += `
            <div class="modal-section">
                <h3>Child Tasks (${childTasks.length})</h3>
                <ul class="modal-list">
                    ${childTasks.map(child => {
                        const emoji = statusEmojis[child.status] || '❓';
                        return `
                            <li class="modal-list-item clickable" data-task-id="${child.id}">
                                ${emoji} [${child.id}] ${child.title} - ${child.status}
                            </li>
                        `;
                    }).join('')}
                </ul>
            </div>
        `;
    }

    return html;
}

function renderRootWorkItemDetails(data) {
    if (data.error) {
        return `<div class="modal-section"><p>Error: ${data.error}</p></div>`;
    }

    const rootWorkItem = data.rootWorkItem;
    const tasks = data.tasks || [];

    let html = `
        <div class="modal-section">
            <h3>Root Work Item Information</h3>
            <div class="modal-field">
                <div class="modal-field-label">ID</div>
                <div class="modal-field-value">${rootWorkItem.id}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Title</div>
                <div class="modal-field-value">${rootWorkItem.title || 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Status</div>
                <div class="modal-field-value">${rootWorkItem.status || 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Created</div>
                <div class="modal-field-value">${formatDateTime(rootWorkItem.created_at)}</div>
            </div>
            ${rootWorkItem.started_at ? `
            <div class="modal-field">
                <div class="modal-field-label">Started</div>
                <div class="modal-field-value">${formatDateTime(rootWorkItem.started_at)}</div>
            </div>
            ` : ''}
            ${rootWorkItem.completed_at ? `
            <div class="modal-field">
                <div class="modal-field-label">Completed</div>
                <div class="modal-field-value">${formatDateTime(rootWorkItem.completed_at)}</div>
            </div>
            ` : ''}
            ${rootWorkItem.failed_at ? `
            <div class="modal-field">
                <div class="modal-field-label">Failed</div>
                <div class="modal-field-value">${formatDateTime(rootWorkItem.failed_at)}</div>
            </div>
            ` : ''}
        </div>
    `;

    if (tasks.length > 0) {
        html += `
            <div class="modal-section">
                <h3>All Tasks (${tasks.length})</h3>
                <ul class="modal-list">
                    ${tasks.map(task => {
                        const emoji = statusEmojis[task.status] || '❓';
                        const queueName = task.queue_name ? queueNames[task.queue_name] || task.queue_name : '';
                        return `
                            <li class="modal-list-item clickable" data-task-id="${task.id}">
                                ${emoji} [${task.id}] ${task.title} - ${task.status}
                                ${queueName ? ` (${queueName})` : ''}
                            </li>
                        `;
                    }).join('')}
                </ul>
            </div>
        `;
    } else {
        html += `<div class="modal-section"><p>No tasks for this work item</p></div>`;
    }

    return html;
}

function renderAgentDetails(data) {
    if (data.error) {
        return `<div class="modal-section"><p>Error: ${data.error}</p></div>`;
    }

    const agents = data.agents || [];
    const activeTasks = data.activeTasks || [];

    let html = '';

    if (agents.length > 0) {
        html += `
            <div class="modal-section">
                <h3>Agent Instances (${agents.length})</h3>
                ${agents.map(agent => `
                    <div class="modal-field">
                        <div class="modal-field-label">Agent: ${agent.name}</div>
                        <div class="modal-field-value">
                            Status: ${agent.status || 'N/A'}<br>
                            Last Heartbeat: ${formatDateTime(agent.last_heartbeat)}<br>
                            Current Task: ${agent.current_task_id || 'None'}
                        </div>
                    </div>
                `).join('')}
            </div>
        `;
    }

    if (activeTasks.length > 0) {
        html += `
            <div class="modal-section">
                <h3>Active Tasks (${activeTasks.length})</h3>
                <ul class="modal-list">
                    ${activeTasks.map(task => {
                        const emoji = statusEmojis[task.status] || '❓';
                        return `
                            <li class="modal-list-item clickable" data-task-id="${task.id}">
                                ${emoji} [${task.id}] ${task.title} - ${task.status}
                            </li>
                        `;
                    }).join('')}
                </ul>
            </div>
        `;
    } else {
        html += `<div class="modal-section"><p>No active tasks</p></div>`;
    }

    return html;
}

function renderAnnouncementDetails(data) {
    if (data.error) {
        return `<div class="modal-section"><p>Error: ${data.error}</p></div>`;
    }

    const announcement = data.announcement;
    const relatedTask = data.relatedTask;

    let html = `
        <div class="modal-section">
            <h3>Announcement Information</h3>
            <div class="modal-field">
                <div class="modal-field-label">Type</div>
                <div class="modal-field-value">${announcement.type || 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Agent</div>
                <div class="modal-field-value">${announcement.agent_name ? `<span class="clickable" data-agent-name="${announcement.agent_name}">${announcement.agent_name}</span>` : 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Message</div>
                <div class="modal-field-value">${announcement.message || 'N/A'}</div>
            </div>
            <div class="modal-field">
                <div class="modal-field-label">Created</div>
                <div class="modal-field-value">${formatDateTime(announcement.created_at)}</div>
            </div>
            ${announcement.context ? `
            <div class="modal-field">
                <div class="modal-field-label">Context</div>
                <div class="modal-field-value"><pre style="white-space: pre-wrap; font-size: 11px;">${announcement.context}</pre></div>
            </div>
            ` : ''}
        </div>
    `;

    if (relatedTask) {
        html += `
            <div class="modal-section">
                <h3>Related Task</h3>
                <div class="modal-list-item clickable" data-task-id="${relatedTask.id}">
                    [${relatedTask.id}] ${relatedTask.title} - ${relatedTask.status}
                </div>
            </div>
        `;
    }

    return html;
}

// API fetch functions
async function fetchQueueDetails(queueName) {
    try {
        const response = await fetch(`/api/queue/${encodeURIComponent(queueName)}`);
        return await response.json();
    } catch (error) {
        return { error: error.message };
    }
}

async function fetchTaskDetails(taskId) {
    try {
        const response = await fetch(`/api/task/${taskId}`);
        return await response.json();
    } catch (error) {
        return { error: error.message };
    }
}

async function fetchRootWorkItemDetails(rootWorkItemId) {
    try {
        const response = await fetch(`/api/root-work-item/${rootWorkItemId}`);
        return await response.json();
    } catch (error) {
        return { error: error.message };
    }
}

async function fetchAgentDetails(agentName) {
    try {
        const response = await fetch(`/api/agent/${encodeURIComponent(agentName)}`);
        return await response.json();
    } catch (error) {
        return { error: error.message };
    }
}

async function fetchAnnouncementDetails(announcementId) {
    try {
        const response = await fetch(`/api/announcement/${announcementId}`);
        return await response.json();
    } catch (error) {
        return { error: error.message };
    }
}

async function fetchMarkdownFile(filePath) {
    try {
        const response = await fetch(`/api/file?path=${encodeURIComponent(filePath)}`);
        return await response.json();
    } catch (error) {
        return { error: error.message };
    }
}

function renderMarkdownFile(data) {
    if (data.error) {
        return `<div class="modal-section"><p>Error: ${data.error}</p></div>`;
    }

    const displayPath = data.absolutePath || data.path;
    const isMarkdown = data.extension === '.md' || data.extension === '.markdown';

    return `
        <div class="modal-section">
            <h3>File: ${displayPath}</h3>
            <div class="modal-field">
                <div class="modal-field-label">Path</div>
                <div class="modal-field-value">${displayPath}</div>
            </div>
            ${data.extension ? `
            <div class="modal-field">
                <div class="modal-field-label">Type</div>
                <div class="modal-field-value">${data.extension.substring(1).toUpperCase()} file</div>
            </div>
            ` : ''}
            <div class="modal-field">
                <div class="modal-field-label">Content</div>
                <div class="modal-field-value ${isMarkdown ? 'markdown-content' : 'file-content'}">${data.html || escapeHtml(data.content)}</div>
            </div>
        </div>
    `;
}

function initializeClickHandlers() {
    if (handlersInitialized) return;
    handlersInitialized = true;

    const queuesContainer = document.getElementById('queues');
    const workItemsContainer = document.getElementById('work-items');
    const agentsContainer = document.getElementById('agents');
    const announcementsContainer = document.getElementById('announcements');
    const modalBody = document.getElementById('modal-body');

    if (queuesContainer) {
        queuesContainer.addEventListener('click', async (e) => {
            const item = e.target.closest('.queue-item');
            if (!item) return;
            const queueName = item.dataset.queueName;
            if (!queueName) return;

            const data = await fetchQueueDetails(queueName);
            const content = renderQueueDetails(data);
            navigateTo(`${queueNames[queueName] || queueName} - Queue Details`, content);
        });
    }

    if (workItemsContainer) {
        workItemsContainer.addEventListener('click', async (e) => {
            const item = e.target.closest('.work-item');
            if (!item) return;
            const rootWorkItemId = item.dataset.rootWorkItemId;
            if (!rootWorkItemId) return;

            const data = await fetchRootWorkItemDetails(parseInt(rootWorkItemId));
            const content = renderRootWorkItemDetails(data);
            navigateTo(`Root Work Item #${rootWorkItemId}`, content);
        });
    }

    if (agentsContainer) {
        agentsContainer.addEventListener('click', async (e) => {
            const item = e.target.closest('.agent-item');
            if (!item) return;
            const agentName = item.dataset.agentName;
            if (!agentName) return;

            const data = await fetchAgentDetails(agentName);
            const content = renderAgentDetails(data);
            navigateTo(`Agent: ${agentName}`, content);
        });
    }

    if (announcementsContainer) {
        announcementsContainer.addEventListener('click', async (e) => {
            const item = e.target.closest('.announcement');
            if (!item) return;
            const announcementId = item.dataset.announcementId;
            if (!announcementId) return;

            const data = await fetchAnnouncementDetails(parseInt(announcementId));
            const content = renderAnnouncementDetails(data);
            navigateTo(`Announcement #${announcementId}`, content);
        });
    }

    if (modalBody) {
        modalBody.addEventListener('click', async (e) => {
            const taskItem = e.target.closest('[data-task-id]');
            if (taskItem) {
                e.stopPropagation();
                const taskId = taskItem.dataset.taskId;
                if (!taskId) return;
                const data = await fetchTaskDetails(parseInt(taskId));
                const content = renderTaskDetails(data);
                navigateTo(`Task #${taskId}`, content);
                return;
            }

            const rootItem = e.target.closest('[data-root-work-item-id]');
            if (rootItem) {
                e.stopPropagation();
                const rootWorkItemId = rootItem.dataset.rootWorkItemId;
                if (!rootWorkItemId) return;
                const data = await fetchRootWorkItemDetails(parseInt(rootWorkItemId));
                const content = renderRootWorkItemDetails(data);
                navigateTo(`Root Work Item #${rootWorkItemId}`, content);
                return;
            }

            const agentItem = e.target.closest('[data-agent-name]');
            if (agentItem) {
                e.stopPropagation();
                const agentName = agentItem.dataset.agentName;
                if (!agentName) return;
                const data = await fetchAgentDetails(agentName);
                const content = renderAgentDetails(data);
                navigateTo(`Agent: ${agentName}`, content);
                return;
            }

            const fileItem = e.target.closest('[data-file-path]');
            if (fileItem) {
                e.stopPropagation();
                const filePath = fileItem.dataset.filePath;
                if (!filePath) return;
                const data = await fetchMarkdownFile(filePath);
                const content = renderMarkdownFile(data);
                const displayPath = data.absolutePath || filePath;
                navigateTo(`File: ${displayPath}`, content);
                return;
            }
        });
    }
}

function renderQueues(queues) {
    const container = document.getElementById('queues');
    if (!queues || queues.length === 0) {
        container.innerHTML = '<div class="empty">No queues found</div>';
        return;
    }

    container.innerHTML = queues.map(queue => {
        const name = queueNames[queue.name] || queue.name;
        const queued = parseInt(queue.queued) || 0;
        const working = parseInt(queue.in_progress) || 0;
        const done = parseInt(queue.done_last_hour) || 0;

        return `
            <div class="queue-item" data-queue-name="${queue.name}">
                <div class="queue-name">${name}</div>
                <div class="progress-bar-container">
                    ${drawProgressBar(queued, working)}
                </div>
                <div class="queue-stats">
                    Q:${queued} W:${working}${done > 0 ? ` <span class="done">✓:${done}</span>` : ''}
                </div>
            </div>
        `;
    }).join('');

}

function renderWorkItems(items) {
    const container = document.getElementById('work-items');
    if (!items || items.length === 0) {
        container.innerHTML = '<div class="empty">No active work items</div>';
        return;
    }

    // Limit to 5 items for compact display
    const displayItems = items.slice(0, 5);

    container.innerHTML = displayItems.map(item => {
        const emoji = statusEmojis[item.status] || '❓';
        const statusClass = item.status === 'completed' ? 'completed' : 
                          item.status === 'failed' ? 'failed' : '';
        const timeStr = item.completed_at ? formatTime(item.completed_at) :
                       item.failed_at ? formatTime(item.failed_at) : '';
        const title = item.title.length > 35 ? item.title.substring(0, 35) + '...' : item.title;

        return `
            <div class="work-item ${statusClass}" data-root-work-item-id="${item.id}">
                <span>${emoji}</span>
                <span class="work-item-id">[${item.id}]</span>
                <span class="work-item-title">${title}</span>
                <span class="work-item-status">[${item.status}]${timeStr ? ` ${timeStr}` : ''}</span>
            </div>
        `;
    }).join('');

}

function renderAgents(agents) {
    const container = document.getElementById('agents');
    if (!agents || agents.length === 0) {
        container.innerHTML = '<div class="empty">No agents running</div>';
        return;
    }

    container.innerHTML = agents.map(agent => {
        const total = parseInt(agent.total) || 0;
        const working = parseInt(agent.working) || 0;
        const idle = parseInt(agent.idle) || 0;
        const agentName = agent.script.replace('.sh', '').replace('agent-', '');

        if (total === 0) {
            return `
                <div class="agent-item" data-agent-name="${agentName}">
                    <span class="agent-script">${agent.script}</span>
                    <span class="agent-count">(0)</span>
                </div>
            `;
        }

        const parts = [];
        if (working > 0) parts.push(`<span class="working">🟢 ${working} working</span>`);
        if (idle > 0) parts.push(`<span class="idle">🟡 ${idle} idle</span>`);

        return `
            <div class="agent-item" data-agent-name="${agentName}">
                <span class="agent-script">${agent.script}</span>
                <span class="agent-count">
                    (${total}) ${parts.join(', ')}
                </span>
            </div>
        `;
    }).join('');

}

function renderAnnouncements(announcements) {
    const container = document.getElementById('announcements');
    if (!announcements || announcements.length === 0) {
        container.innerHTML = '<div class="empty">No recent announcements</div>';
        return;
    }

    // Limit to 3 announcements for compact display
    const displayAnnouncements = announcements.slice(0, 3);

    container.innerHTML = displayAnnouncements.map(ann => {
        const typeClass = ann.type || '';
        const emoji = ann.type === 'error' ? '🔴' :
                     ann.type === 'work-completed' ? '✅' :
                     ann.type === 'work-taken' ? '🟢' :
                     ann.type === 'question' ? '❓' : '📢';
        const message = ann.message.length > 50 ? ann.message.substring(0, 50) + '...' : ann.message;

        return `
            <div class="announcement ${typeClass}" data-announcement-id="${ann.id}">
                <span class="announcement-message">${emoji} ${ann.agent_name || 'system'}: ${message}</span>
                <span class="announcement-meta">${formatTime(ann.created_at)}</span>
            </div>
        `;
    }).join('');

}

async function fetchStatus() {
    try {
        const response = await fetch('/api/status');
        const data = await response.json();

        if (data.error) {
            console.error('Error:', data.error);
            return;
        }

        renderQueues(data.queues);
        renderWorkItems(data.rootWorkItems);
        renderAgents(data.agents);
        renderAnnouncements(data.announcements);

        if (data.timestamp) {
            document.getElementById('timestamp').textContent = 
                new Date(data.timestamp).toLocaleString();
        }

        refreshCount += 5;
        document.getElementById('refresh-count').textContent = refreshCount;
    } catch (error) {
        console.error('Failed to fetch status:', error);
    }
}

// Modal event handlers
document.getElementById('modal-close').addEventListener('click', hideModal);
document.getElementById('modal-back').addEventListener('click', navigateBack);
document.getElementById('modal-overlay').addEventListener('click', (e) => {
    if (e.target.id === 'modal-overlay') {
        hideModal();
    }
});

initializeClickHandlers();

// Initial load
fetchStatus();

// Auto-refresh every 5 seconds
refreshInterval = setInterval(fetchStatus, 5000);

// Setup Server-Sent Events for auto-reload on file changes
let reloadEventSource = null;
function setupAutoReload() {
    if (reloadEventSource) {
        reloadEventSource.close();
    }

    reloadEventSource = new EventSource('/api/reload');
    
    reloadEventSource.onmessage = (event) => {
        if (event.data === 'reload') {
            console.log('File change detected, reloading page...');
            window.location.reload();
        } else if (event.data === 'connected') {
            console.log('Auto-reload connected');
        }
    };

    reloadEventSource.onerror = (error) => {
        console.error('Auto-reload connection error:', error);
        // Try to reconnect after 5 seconds
        setTimeout(() => {
            if (reloadEventSource.readyState === EventSource.CLOSED) {
                setupAutoReload();
            }
        }, 5000);
    };
}

// Start auto-reload listener
setupAutoReload();

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (refreshInterval) {
        clearInterval(refreshInterval);
    }
    if (reloadEventSource) {
        reloadEventSource.close();
    }
});
