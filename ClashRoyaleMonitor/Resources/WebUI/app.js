// Bridge to communicate with native iOS code
const nativeBridge = {
    postMessage: function(action, data) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.iosApp) {
            window.webkit.messageHandlers.iosApp.postMessage({
                action: action,
                data: data
            });
        }
    }
};

// State management
let appState = {
    isMonitoring: false,
    sessionStartTime: null,
    killCount: 0,
    deathCount: 0,
    videos: [],
    events: []
};

// UI Elements
const statusDot = document.getElementById('statusDot');
const statusText = document.getElementById('statusText');
const sessionDuration = document.getElementById('sessionDuration');
const killCountEl = document.getElementById('killCount');
const deathCountEl = document.getElementById('deathCount');
const startBtn = document.getElementById('startMonitoring');
const launchBtn = document.getElementById('launchGame');
const videoList = document.getElementById('videoList');
const eventsList = document.getElementById('eventsList');

// Update UI based on state
function updateUI() {
    // Update status indicator
    if (appState.isMonitoring) {
        statusDot.classList.add('active');
        statusText.textContent = 'Monitoring Active';
        startBtn.innerHTML = `
            <svg class="icon" viewBox="0 0 24 24">
                <path d="M6 6h12v12H6z"/>
            </svg>
            Stop Monitoring
        `;
        startBtn.classList.add('stop');
    } else {
        statusDot.classList.remove('active');
        statusText.textContent = 'Monitoring Inactive';
        startBtn.innerHTML = `
            <svg class="icon" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z"/>
            </svg>
            Start Monitoring
        `;
        startBtn.classList.remove('stop');
    }

    // Update stats
    killCountEl.textContent = appState.killCount;
    deathCountEl.textContent = appState.deathCount;

    // Update video list
    updateVideoList();

    // Update events list
    updateEventsList();
}

// Update session duration timer
function updateDuration() {
    if (appState.isMonitoring && appState.sessionStartTime) {
        const now = Date.now();
        const duration = Math.floor((now - appState.sessionStartTime) / 1000);
        const minutes = Math.floor(duration / 60);
        const seconds = duration % 60;
        sessionDuration.textContent = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }
}

// Update video list UI
function updateVideoList() {
    if (appState.videos.length === 0) {
        videoList.innerHTML = `
            <div class="empty-state">
                <svg class="empty-icon" viewBox="0 0 24 24">
                    <path d="M18 3v2h-2V3H8v2H6V3H4v18h2v-2h2v2h8v-2h2v2h2V3h-2zM8 17H6v-2h2v2zm0-4H6v-2h2v2zm0-4H6V7h2v2zm10 8h-2v-2h2v2zm0-4h-2v-2h2v2zm0-4h-2V7h2v2z"/>
                </svg>
                <p>No kill highlights yet</p>
                <p class="empty-subtitle">Highlights will appear here when kills are detected</p>
            </div>
        `;
    } else {
        videoList.innerHTML = appState.videos.map(video => `
            <div class="video-item">
                <div class="video-info">
                    <div class="video-title">${video.name}</div>
                    <div class="video-meta">${video.date} • ${video.size}</div>
                </div>
                <button class="play-btn" onclick="playVideo('${video.path}')">Play</button>
            </div>
        `).join('');
    }
}

// Update events list UI
function updateEventsList() {
    if (appState.events.length === 0) {
        eventsList.innerHTML = '<div class="empty-state-small">No events yet</div>';
    } else {
        eventsList.innerHTML = appState.events.slice(0, 10).map(event => `
            <div class="event-item ${event.type === 'death' ? 'death' : ''}">
                <div>${event.type === 'kill' ? '🎯 Kill detected' : '💀 Death detected'}</div>
                <div class="event-time">${event.time}</div>
            </div>
        `).join('');
    }
}

// Button handlers
startBtn.addEventListener('click', () => {
    if (appState.isMonitoring) {
        nativeBridge.postMessage('stopMonitoring', {});
    } else {
        nativeBridge.postMessage('startMonitoring', {});
    }
});

launchBtn.addEventListener('click', () => {
    nativeBridge.postMessage('launchGame', {});
});

// Video player functions
function playVideo(path) {
    nativeBridge.postMessage('playVideo', { path: path });
}

function closeVideoPlayer() {
    const modal = document.getElementById('videoPlayer');
    const video = document.getElementById('videoElement');
    video.pause();
    modal.classList.add('hidden');
}

// Native iOS can call these functions to update the UI
window.updateAppState = function(newState) {
    appState = { ...appState, ...newState };
    updateUI();
};

window.addKillEvent = function() {
    appState.killCount++;
    appState.events.unshift({
        type: 'kill',
        time: new Date().toLocaleTimeString()
    });
    updateUI();
};

window.addDeathEvent = function() {
    appState.deathCount++;
    appState.events.unshift({
        type: 'death',
        time: new Date().toLocaleTimeString()
    });
    updateUI();
};

window.updateVideoList = function(videos) {
    appState.videos = videos;
    updateUI();
};

window.setMonitoringStatus = function(isActive) {
    appState.isMonitoring = isActive;
    if (isActive && !appState.sessionStartTime) {
        appState.sessionStartTime = Date.now();
    } else if (!isActive) {
        appState.sessionStartTime = null;
        appState.killCount = 0;
        appState.deathCount = 0;
    }
    updateUI();
};

// Initialize
setInterval(updateDuration, 1000);
updateUI();

// Request initial state from native
nativeBridge.postMessage('requestState', {});