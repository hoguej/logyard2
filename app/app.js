// Queue Status Dashboard
let refreshInterval;
let refreshCount = 0;

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
            <div class="queue-item">
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
            <div class="work-item ${statusClass}">
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

        if (total === 0) {
            return `
                <div class="agent-item">
                    <span class="agent-script">${agent.script}</span>
                    <span class="agent-count">(0)</span>
                </div>
            `;
        }

        const parts = [];
        if (working > 0) parts.push(`<span class="working">🟢 ${working} working</span>`);
        if (idle > 0) parts.push(`<span class="idle">🟡 ${idle} idle</span>`);

        return `
            <div class="agent-item">
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
            <div class="announcement ${typeClass}">
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

// Initial load
fetchStatus();

// Auto-refresh every 5 seconds
refreshInterval = setInterval(fetchStatus, 5000);

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (refreshInterval) {
        clearInterval(refreshInterval);
    }
});
