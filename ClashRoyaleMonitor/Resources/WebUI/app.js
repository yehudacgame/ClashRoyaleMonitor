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

    // Update video list UI (don't call the function - just update the DOM)
    updateVideoListUI();

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

// Update video list UI with session grouping
function updateVideoListUI() {
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
        // Group videos by play session (based on timestamp proximity)
        const videoSessions = groupVideosBySession(appState.videos);
        
        let html = '';
        videoSessions.forEach((session, index) => {
            const sessionStart = formatTime(session.startTime);
            const sessionDuration = formatDuration(session.duration);
            const killCount = session.videos.length;
            
            html += `
                <div class="session-group">
                    <div class="session-header">
                        <div class="session-info">
                            <h3>Play Session ${index + 1}</h3>
                            <div class="session-meta">
                                ${sessionStart} • ${sessionDuration} • ${killCount} kill${killCount !== 1 ? 's' : ''}
                            </div>
                        </div>
                        <button class="session-toggle" onclick="toggleSession(${index})" id="toggle-${index}">
                            <svg viewBox="0 0 24 24">
                                <path d="M7 10l5 5 5-5z"/>
                            </svg>
                        </button>
                    </div>
                    <div class="session-content" id="session-${index}">
                        ${session.videos.map((video, videoIndex) => `
                            <div class="video-item">
                                <div class="video-info">
                                    <div class="video-title">Kill #${videoIndex + 1}</div>
                                    <div class="video-meta">${video.date} • ${video.size}</div>
                                </div>
                                <button class="play-btn" onclick="playVideo('${video.path}')">Play</button>
                            </div>
                        `).join('')}
                    </div>
                </div>
            `;
        });
        
        videoList.innerHTML = html;
    }
}

// Group videos into play sessions based on actual broadcast start/stop events
function groupVideosBySession(videos) {
    if (videos.length === 0) return [];
    
    // Sort videos by timestamp
    const sortedVideos = videos.slice().sort((a, b) => {
        const timeA = parseTimestampFromFilename(a.name);
        const timeB = parseTimestampFromFilename(b.name);
        return timeA - timeB;
    });
    
    // Use session events if available
    if (appState.sessionEvents && appState.sessionEvents.length > 0) {
        return groupVideosByBroadcastSessions(sortedVideos);
    }
    
    // Fallback to old time-gap method if no session events
    console.log('No session events found, using time-gap fallback');
    const sessions = [];
    let currentSession = null;
    const maxGapMinutes = 5;
    
    sortedVideos.forEach((video, index) => {
        const videoTime = parseTimestampFromFilename(video.name);
        
        if (!currentSession || (videoTime - currentSession.lastTime) > (maxGapMinutes * 60 * 1000)) {
            currentSession = {
                startTime: videoTime,
                lastTime: videoTime,
                videos: [video],
                duration: 0
            };
            sessions.push(currentSession);
        } else {
            currentSession.videos.push(video);
            currentSession.lastTime = videoTime;
            currentSession.duration = videoTime - currentSession.startTime;
        }
    });
    
    return sessions;
}

// Group videos by actual broadcast sessions
function groupVideosByBroadcastSessions(sortedVideos) {
    const sessions = [];
    const sessionEvents = appState.sessionEvents.slice().sort((a, b) => a.timestamp - b.timestamp);
    
    console.log('Session events:', sessionEvents);
    
    // Build session pairs (start -> end)
    const sessionPairs = [];
    let currentSessionStart = null;
    
    sessionEvents.forEach(event => {
        if (event.type === 'start') {
            currentSessionStart = event;
        } else if (event.type === 'end' && currentSessionStart) {
            sessionPairs.push({
                start: currentSessionStart.timestamp * 1000, // Convert to ms
                end: event.timestamp * 1000,
                startDate: currentSessionStart.date,
                endDate: event.date
            });
            currentSessionStart = null;
        }
    });
    
    // Handle case where session started but never ended (still recording)
    if (currentSessionStart) {
        sessionPairs.push({
            start: currentSessionStart.timestamp * 1000,
            end: Date.now(),
            startDate: currentSessionStart.date,
            endDate: new Date().toISOString(),
            ongoing: true
        });
    }
    
    console.log('Session pairs:', sessionPairs);
    
    // Group videos into these sessions
    sessionPairs.forEach((sessionPair, sessionIndex) => {
        const sessionVideos = sortedVideos.filter(video => {
            const videoTime = parseTimestampFromFilename(video.name);
            return videoTime >= sessionPair.start && videoTime <= sessionPair.end;
        });
        
        if (sessionVideos.length > 0) {
            sessions.push({
                startTime: sessionPair.start,
                endTime: sessionPair.end,
                duration: sessionPair.end - sessionPair.start,
                videos: sessionVideos,
                ongoing: sessionPair.ongoing || false,
                startDate: sessionPair.startDate,
                endDate: sessionPair.endDate
            });
        }
    });
    
    console.log(`Created ${sessions.length} sessions from ${sortedVideos.length} videos using broadcast events`);
    return sessions;
}

// Parse timestamp from filename like "COD_Kill_2025-08-08_08-24-07.mp4"
function parseTimestampFromFilename(filename) {
    const match = filename.match(/COD_Kill_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})/);
    if (match) {
        const dateStr = match[1].replace(/_/g, ' ').replace(/-/g, ':');
        const parts = dateStr.split(' ');
        const datePart = parts[0].replace(/:/g, '-');
        const timePart = parts[1];
        return new Date(`${datePart}T${timePart}`).getTime();
    }
    return Date.now();
}

// Format time for display
function formatTime(timestamp) {
    return new Date(timestamp).toLocaleString();
}

// Format duration for display
function formatDuration(durationMs) {
    const minutes = Math.floor(durationMs / (60 * 1000));
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    
    if (hours > 0) {
        return `${hours}h ${remainingMinutes}m`;
    } else if (minutes > 0) {
        return `${minutes}m`;
    } else {
        return 'Quick session';
    }
}

// Toggle session visibility
function toggleSession(sessionIndex) {
    const content = document.getElementById(`session-${sessionIndex}`);
    const toggle = document.getElementById(`toggle-${sessionIndex}`);
    
    if (content.style.display === 'none') {
        content.style.display = 'block';
        toggle.style.transform = 'rotate(0deg)';
    } else {
        content.style.display = 'none';
        toggle.style.transform = 'rotate(-90deg)';
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
    updateVideoListUI();
};

window.updateVideoListWithSessions = function(data) {
    appState.videos = data.videos || [];
    appState.sessionEvents = data.sessions || [];
    console.log('Received session events:', appState.sessionEvents);
    updateVideoListUI();
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