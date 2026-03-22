/**
 * Solapur Safety System - Main Dashboard Application
 * Handles real-time updates, API calls, and UI interactions
 */

// ==================== CONFIGURATION ====================
const CONFIG = {
    API_URL: 'http://localhost:3000/api',
    SOCKET_URL: 'http://localhost:3000',
    REFRESH_INTERVAL: 5000, // 5 seconds
    MAP_CENTER: [17.6599, 75.9064], // Solapur coordinates
    MAP_ZOOM: 13
};

// ==================== GLOBAL STATE ====================
let state = {
    user: null,
    workers: [],
    sessions: [],
    alerts: [],
    gasReadings: [],
    connected: false,
    currentPage: 'dashboard',
    charts: {},
    map: null,
    markers: [],
    previewMap: null,
    fullMap: null
};

// ==================== SOCKET.IO CONNECTION ====================
const socket = io(CONFIG.SOCKET_URL, {
    auth: {
        token: localStorage.getItem('token')
    }
});

socket.on('connect', () => {
    console.log('✅ Connected to server');
    updateConnectionStatus(true);
    
    // Join control room
    socket.emit('join', { role: 'control', userId: state.user?.id });
});

socket.on('disconnect', () => {
    console.log('❌ Disconnected from server');
    updateConnectionStatus(false);
});

socket.on('new-alert', (alert) => {
    console.log('🔔 New alert:', alert);
    state.alerts.unshift(alert);
    updateAlertsFeed();
    updateAlertBadge();
    showNotification(alert);
    
    // Play sound for critical alerts
    if (alert.severity === 'critical') {
        playAlertSound();
    }
});

socket.on('alert-updated', (data) => {
    updateAlertStatus(data.alertId, data);
});

socket.on('new-reading', (reading) => {
    updateGasReadings(reading);
    updateCharts();
});

socket.on('worker-status', (status) => {
    updateWorkerStatus(status);
});

// ==================== INITIALIZATION ====================
document.addEventListener('DOMContentLoaded', async () => {
    console.log('🚀 Solapur Safety Dashboard initializing...');
    
    // Check authentication
    const token = localStorage.getItem('token');
    if (!token) {
        window.location.href = '/login.html';
        return;
    }
    
    // Request notification permission
    if ("Notification" in window) {
        Notification.requestPermission();
    }
    
    // Load user data
    await loadUserData();
    
    // Initialize UI
    initializeDateTime();
    initializeNavigation();
    initializeCharts();
    initializeMap();
    
    // Load initial data
    await loadDashboardData();
    
    // Start real-time updates
    startDataRefresh();
    
    // Setup event listeners
    setupEventListeners();
});

// ==================== AUTHENTICATION ====================
async function loadUserData() {
    try {
        const response = await fetch(`${CONFIG.API_URL}/auth/me`, {
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('token')}`
            }
        });
        
        if (response.ok) {
            const data = await response.json();
            state.user = data.user || data;
            document.getElementById('user-name').textContent = state.user.full_name || 'Control Admin';
            document.getElementById('user-role').textContent = state.user.role || 'Control Center';
        }
    } catch (error) {
        console.error('Failed to load user:', error);
    }
}

// ==================== NAVIGATION ====================
function initializeNavigation() {
    const navItems = document.querySelectorAll('.nav-item');
    
    navItems.forEach(item => {
        item.addEventListener('click', (e) => {
            e.preventDefault();
            
            // Update active state
            navItems.forEach(n => n.classList.remove('active'));
            item.classList.add('active');
            
            // Get page from data-page attribute
            const page = item.getAttribute('data-page');
            navigateToPage(page);
        });
    });
}

function navigateToPage(page) {
    // Hide all pages
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    
    // Show selected page
    const pageElement = document.getElementById(`${page}-page`);
    if (pageElement) {
        pageElement.classList.add('active');
    }
    
    document.getElementById('page-title').textContent = page.charAt(0).toUpperCase() + page.slice(1);
    
    state.currentPage = page;
    
    // Load page-specific data
    switch(page) {
        case 'map':
            setTimeout(() => {
                if (state.fullMap) state.fullMap.invalidateSize();
            }, 100);
            break;
        case 'workers':
            loadWorkersData();
            break;
        case 'alerts':
            loadAlertsData();
            break;
        case 'sessions':
            loadSessionsData();
            break;
        case 'analytics':
            loadAnalyticsData();
            break;
    }
}

// ==================== DATA LOADING ====================
async function loadDashboardData() {
    try {
        const [workers, sessions, alerts] = await Promise.all([
            fetch(`${CONFIG.API_URL}/workers/active`, {
                headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
            }).then(res => res.json()).catch(() => ({ data: [] })),
            
            fetch(`${CONFIG.API_URL}/sessions/active`, {
                headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
            }).then(res => res.json()).catch(() => ({ data: [] })),
            
            fetch(`${CONFIG.API_URL}/alerts/active`, {
                headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
            }).then(res => res.json()).catch(() => ({ data: [] }))
        ]);
        
        state.workers = workers.data || [];
        state.sessions = sessions.data || [];
        state.alerts = alerts.data || [];
        
        updateDashboard();
    } catch (error) {
        console.error('Failed to load dashboard data:', error);
    }
}

async function loadWorkersData() {
    try {
        const response = await fetch(`${CONFIG.API_URL}/workers`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
        });
        
        const data = await response.json();
        updateWorkersTable(data.data || []);
    } catch (error) {
        console.error('Failed to load workers:', error);
    }
}

async function loadAlertsData() {
    try {
        const response = await fetch(`${CONFIG.API_URL}/alerts/history`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
        });
        
        const data = await response.json();
        updateAlertsTable(data.data || []);
    } catch (error) {
        console.error('Failed to load alerts:', error);
    }
}

async function loadSessionsData() {
    try {
        const response = await fetch(`${CONFIG.API_URL}/sessions/active`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
        });
        
        const data = await response.json();
        updateSessionsDisplay(data.data || []);
    } catch (error) {
        console.error('Failed to load sessions:', error);
    }
}

async function loadAnalyticsData() {
    try {
        const response = await fetch(`${CONFIG.API_URL}/analytics/summary?days=7`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
        });
        
        const data = await response.json();
        updateAnalyticsCharts(data);
    } catch (error) {
        console.error('Failed to load analytics:', error);
    }
}

// ==================== UI UPDATES ====================
function updateDashboard() {
    updateStats();
    updateWorkerCards();
    updateAlertsFeed();
    updateMapMarkers();
    updateExposureBars();
    updateAlertBadge();
    updateSessionPieChart();
}

function updateStats() {
    const activeWorkers = state.workers.filter(w => w.is_active).length;
    const activeAlerts = state.alerts.filter(a => !a.acknowledged).length;
    const criticalAlerts = state.alerts.filter(a => a.severity === 'critical' && !a.acknowledged).length;
    const safeSessions = state.sessions.filter(s => s.pre_entry_decision === 'SAFE').length;
    
    document.getElementById('active-workers').textContent = activeWorkers;
    document.getElementById('active-alerts').textContent = activeAlerts;
    document.getElementById('safe-sessions').textContent = safeSessions;
    
    const alertChangeEl = document.getElementById('alert-change');
    if (alertChangeEl) {
        alertChangeEl.innerHTML = `<span class="critical">${criticalAlerts} critical</span>`;
    }
    
    // Update mini stats
    document.getElementById('today-sessions').textContent = state.sessions.length;
    document.getElementById('total-workers').textContent = state.workers.length;
    
    // Calculate average session duration
    const avgDuration = state.sessions.length > 0 
        ? Math.round(state.sessions.reduce((acc, s) => {
            const duration = s.end_time ? 
                (new Date(s.end_time) - new Date(s.start_time)) / 60000 : 
                (new Date() - new Date(s.start_time)) / 60000;
            return acc + duration;
        }, 0) / state.sessions.length)
        : 0;
    document.getElementById('avg-duration').textContent = `${avgDuration}m`;
}

function updateWorkerCards() {
    const container = document.getElementById('worker-cards-container');
    if (!container) return;
    
    const workers = state.workers.slice(0, 5);
    
    if (workers.length === 0) {
        container.innerHTML = '<div class="no-data">No active workers</div>';
        return;
    }
    
    container.innerHTML = workers.map(w => `
        <div class="worker-card">
            <div class="worker-avatar">
                <i class="fas fa-user-hard-hat"></i>
            </div>
            <div class="worker-info">
                <div class="worker-name">${w.full_name || `Worker ${w.worker_id}`}</div>
                <div class="worker-meta">
                    <span><i class="fas fa-heartbeat" style="color: #e74c3c;"></i> ${w.heart_rate || '--'} bpm</span>
                    <span><i class="fas fa-map-marker-alt"></i> ${w.location || 'Unknown'}</span>
                </div>
            </div>
            <div class="worker-status ${w.is_active ? 'active' : 'inactive'}">
                ${w.is_active ? 'Active' : 'Inactive'}
            </div>
        </div>
    `).join('');
}

function updateAlertsFeed() {
    const container = document.getElementById('alerts-feed-container');
    if (!container) return;
    
    const alerts = state.alerts.slice(0, 10);
    
    if (alerts.length === 0) {
        container.innerHTML = '<div class="no-data">No active alerts</div>';
        return;
    }
    
    container.innerHTML = alerts.map(a => `
        <div class="alert-item" onclick="viewAlert('${a.id}')">
            <div class="alert-icon ${a.severity}">
                <i class="fas ${a.severity === 'critical' ? 'fa-exclamation-triangle' : 
                                 a.severity === 'warning' ? 'fa-exclamation-circle' : 
                                 'fa-info-circle'}"></i>
            </div>
            <div class="alert-content">
                <div class="alert-title">${a.message || a.alert_type}</div>
                <div class="alert-meta">
                    <span><i class="fas fa-clock"></i> ${new Date(a.timestamp).toLocaleTimeString()}</span>
                    <span><i class="fas fa-user"></i> ${a.worker_name || 'Unknown'}</span>
                </div>
            </div>
            <div class="alert-status ${a.acknowledged ? 'acknowledged' : 'new'}">
                ${a.acknowledged ? 'Acknowledged' : 'New'}
            </div>
        </div>
    `).join('');
}

function updateAlertStatus(alertId, data) {
    const alert = state.alerts.find(a => a.id === alertId);
    if (alert) {
        alert.acknowledged = data.acknowledged;
        alert.acknowledged_by = data.acknowledged_by;
        updateAlertsFeed();
        updateAlertBadge();
    }
}

function updateAlertBadge() {
    const badge = document.getElementById('alert-badge');
    const unacknowledged = state.alerts.filter(a => !a.acknowledged).length;
    badge.textContent = unacknowledged;
    badge.style.display = unacknowledged > 0 ? 'inline' : 'none';
}

function updateExposureBars() {
    const container = document.getElementById('exposure-bars');
    if (!container) return;
    
    if (state.workers.length === 0) {
        container.innerHTML = '<div class="no-data">No worker data</div>';
        return;
    }
    
    // Calculate exposure for active workers
    const exposureData = state.workers.map(w => ({
        name: w.full_name || `Worker ${w.worker_id}`,
        h2s: w.current_h2s || Math.random() * 15, // Placeholder - would come from real data
        limit: 10,
        color: w.current_h2s > 10 ? 'critical' : w.current_h2s > 5 ? 'caution' : 'safe'
    }));
    
    container.innerHTML = exposureData.map(w => `
        <div class="exposure-item">
            <span class="exposure-label">${w.name}</span>
            <div class="exposure-bar-container">
                <div class="exposure-bar ${w.color}" 
                     style="width: ${(w.h2s / 15) * 100}%"></div>
            </div>
            <span class="exposure-value">${w.h2s.toFixed(1)}/15</span>
        </div>
    `).join('');
}

function updateGasReadings(reading) {
    state.gasReadings.push(reading);
    if (state.gasReadings.length > 100) {
        state.gasReadings.shift();
    }
    
    // Update worker current values
    if (reading.worker_id) {
        const worker = state.workers.find(w => w.id === reading.worker_id);
        if (worker) {
            worker.current_h2s = reading.h2s;
            worker.current_o2 = reading.o2;
        }
    }
}

function updateWorkerStatus(status) {
    const worker = state.workers.find(w => w.id === status.worker_id);
    if (worker) {
        worker.heart_rate = status.heart_rate;
        worker.is_active = status.is_active;
        worker.location = status.location;
        updateWorkerCards();
        updateWorkersTable(state.workers);
    }
}

function updateWorkersTable(workers) {
    const tbody = document.getElementById('workers-table-body');
    if (!tbody) return;
    
    if (workers.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="no-data">No workers found</td></tr>';
        return;
    }
    
    tbody.innerHTML = workers.map(w => `
        <tr>
            <td>${w.worker_id || 'N/A'}</td>
            <td>${w.full_name || 'Unknown'}</td>
            <td><span class="status-badge ${w.is_active ? 'safe' : 'caution'}">${w.is_active ? 'Active' : 'Inactive'}</span></td>
            <td>${w.heart_rate || '--'} bpm</td>
            <td>${w.location || 'Unknown'}</td>
            <td>${w.current_session || 'None'}</td>
            <td>
                <button class="btn-small" onclick="viewWorker('${w.id}')">
                    <i class="fas fa-eye"></i>
                </button>
                <button class="btn-small" onclick="contactWorker('${w.id}')">
                    <i class="fas fa-phone"></i>
                </button>
            </td>
        </tr>
    `).join('');
}

function updateAlertsTable(alerts) {
    const container = document.getElementById('alerts-table-container');
    if (!container) return;
    
    if (alerts.length === 0) {
        container.innerHTML = '<div class="no-data">No alerts found</div>';
        return;
    }
    
    container.innerHTML = `
        <table class="data-table">
            <thead>
                <tr>
                    <th>Time</th>
                    <th>Type</th>
                    <th>Severity</th>
                    <th>Worker</th>
                    <th>Value</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                ${alerts.map(a => `
                    <tr>
                        <td>${new Date(a.timestamp).toLocaleTimeString()}</td>
                        <td>${a.alert_type}</td>
                        <td><span class="status-badge ${a.severity}">${a.severity}</span></td>
                        <td>${a.worker_name || 'Unknown'}</td>
                        <td>${a.current_value || ''} ${a.threshold_value ? `/ ${a.threshold_value}` : ''}</td>
                        <td>
                            <span class="alert-status ${a.acknowledged ? 'acknowledged' : 'new'}">
                                ${a.acknowledged ? 'Acknowledged' : 'New'}
                            </span>
                        </td>
                        <td>
                            <button class="btn-small" onclick="viewAlert('${a.id}')">
                                <i class="fas fa-eye"></i>
                            </button>
                            ${!a.acknowledged ? `
                                <button class="btn-small" onclick="acknowledgeAlert('${a.id}')">
                                    <i class="fas fa-check"></i>
                                </button>
                            ` : ''}
                        </td>
                    </tr>
                `).join('')}
            </tbody>
        </table>
    `;
}

function updateSessionsDisplay(sessions) {
    const container = document.getElementById('sessions-container');
    if (!container) return;
    
    if (sessions.length === 0) {
        container.innerHTML = '<div class="no-data">No active sessions</div>';
        return;
    }
    
    container.innerHTML = `
        <div class="sessions-grid">
            ${sessions.map(s => `
                <div class="session-card">
                    <div class="session-header">
                        <h4>Session ${s.session_id}</h4>
                        <span class="status-badge ${(s.pre_entry_decision || 'safe').toLowerCase()}">
                            ${s.pre_entry_decision || 'SAFE'}
                        </span>
                    </div>
                    <div class="session-body">
                        <p><i class="fas fa-map-marker-alt"></i> Manhole: ${s.manhole_id || 'Unknown'}</p>
                        <p><i class="fas fa-user"></i> Workers: ${s.worker1_name || 'None'} ${s.worker2_name ? `, ${s.worker2_name}` : ''}</p>
                        <p><i class="fas fa-clock"></i> Started: ${new Date(s.start_time).toLocaleString()}</p>
                        <p><i class="fas fa-chart-line"></i> Duration: ${Math.floor((new Date() - new Date(s.start_time)) / 60000)} min</p>
                    </div>
                    <div class="session-footer">
                        <button class="btn-small" onclick="viewSession('${s.session_id}')">View Details</button>
                        <button class="btn-small" onclick="endSession('${s.session_id}')">End Session</button>
                    </div>
                </div>
            `).join('')}
        </div>
    `;
}

// ==================== MAP FUNCTIONS ====================
function initializeMap() {
    // Preview map
    const previewMapElement = document.getElementById('preview-map');
    if (previewMapElement) {
        const previewMap = L.map('preview-map').setView(CONFIG.MAP_CENTER, CONFIG.MAP_ZOOM);
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '© OpenStreetMap contributors'
        }).addTo(previewMap);
        state.previewMap = previewMap;
    }
    
    // Full map
    const fullMapElement = document.getElementById('full-map');
    if (fullMapElement) {
        const fullMap = L.map('full-map').setView(CONFIG.MAP_CENTER, CONFIG.MAP_ZOOM);
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '© OpenStreetMap contributors'
        }).addTo(fullMap);
        state.fullMap = fullMap;
        
        // Add scale control
        L.control.scale().addTo(fullMap);
        
        // Add legend
        const legend = L.control({ position: 'bottomright' });
        legend.onAdd = function() {
            const div = L.DomUtil.create('div', 'info legend');
            div.innerHTML = `
                <div style="background: white; padding: 10px; border-radius: 5px;">
                    <h4>Status</h4>
                    <div><span style="color: #27ae60;">●</span> SAFE</div>
                    <div><span style="color: #f39c12;">●</span> CAUTION</div>
                    <div><span style="color: #e74c3c;">●</span> BLOCK</div>
                </div>
            `;
            return div;
        };
        legend.addTo(fullMap);
    }
}

function updateMapMarkers() {
    // Clear existing markers
    if (state.markers.length) {
        state.markers.forEach(m => {
            if (state.previewMap) state.previewMap.removeLayer(m);
            if (state.fullMap) state.fullMap.removeLayer(m);
        });
    }
    state.markers = [];
    
    // Add markers for active sessions
    state.sessions.forEach(session => {
        if (session.location_lat && session.location_lon) {
            // Determine marker color based on status
            const color = session.pre_entry_decision === 'BLOCK' ? '#e74c3c' :
                         session.pre_entry_decision === 'CAUTION' ? '#f39c12' : '#27ae60';
            
            const marker = L.circleMarker([session.location_lat, session.location_lon], {
                radius: 10,
                color: color,
                fillColor: color,
                fillOpacity: 0.8,
                weight: 2
            }).bindPopup(`
                <b>Session ${session.session_id}</b><br>
                Status: ${session.pre_entry_decision || 'SAFE'}<br>
                Workers: ${session.worker1_name || 'None'}<br>
                Started: ${new Date(session.start_time).toLocaleTimeString()}
            `);
            
            if (state.previewMap) marker.addTo(state.previewMap);
            if (state.fullMap) marker.addTo(state.fullMap);
            state.markers.push(marker);
        }
    });
}

// ==================== CHART FUNCTIONS ====================
function initializeCharts() {
    // Gas chart
    const gasCtx = document.getElementById('gas-chart')?.getContext('2d');
    if (gasCtx) {
        state.charts.gas = new Chart(gasCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'H2S (ppm)',
                        data: [],
                        borderColor: '#e74c3c',
                        backgroundColor: 'rgba(231, 76, 60, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 3
                    },
                    {
                        label: 'O2 (%)',
                        data: [],
                        borderColor: '#3498db',
                        backgroundColor: 'rgba(52, 152, 219, 0.1)',
                        tension: 0.4,
                        borderWidth: 2,
                        pointRadius: 3,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: {
                    mode: 'index',
                    intersect: false
                },
                scales: {
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        title: {
                            display: true,
                            text: 'H2S (ppm)'
                        },
                        min: 0,
                        max: 20
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        title: {
                            display: true,
                            text: 'O2 (%)'
                        },
                        min: 18,
                        max: 22,
                        grid: {
                            drawOnChartArea: false
                        }
                    }
                },
                plugins: {
                    legend: {
                        position: 'top',
                    }
                }
            }
        });
    }
    
    // Session pie chart
    const pieCtx = document.getElementById('session-pie-chart')?.getContext('2d');
    if (pieCtx) {
        state.charts.pie = new Chart(pieCtx, {
            type: 'doughnut',
            data: {
                labels: ['SAFE', 'CAUTION', 'BLOCK'],
                datasets: [{
                    data: [0, 0, 0],
                    backgroundColor: ['#27ae60', '#f39c12', '#e74c3c'],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                },
                cutout: '70%'
            }
        });
    }
    
    // Risk pie chart for analytics
    const riskCtx = document.getElementById('risk-pie-chart')?.getContext('2d');
    if (riskCtx) {
        state.charts.riskPie = new Chart(riskCtx, {
            type: 'pie',
            data: {
                labels: ['SAFE', 'CAUTION', 'BLOCK'],
                datasets: [{
                    data: [85, 10, 5],
                    backgroundColor: ['#27ae60', '#f39c12', '#e74c3c']
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });
    }
    
    // Hourly risk chart
    const hourlyCtx = document.getElementById('hourly-risk-chart')?.getContext('2d');
    if (hourlyCtx) {
        state.charts.hourly = new Chart(hourlyCtx, {
            type: 'bar',
            data: {
                labels: ['0-3', '3-6', '6-9', '9-12', '12-15', '15-18', '18-21', '21-24'],
                datasets: [{
                    label: 'Average H2S (ppm)',
                    data: [2.1, 1.8, 3.2, 5.8, 6.2, 5.5, 4.1, 2.8],
                    backgroundColor: '#e74c3c'
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
    }
    
    // Trends chart
    const trendsCtx = document.getElementById('trends-chart')?.getContext('2d');
    if (trendsCtx) {
        state.charts.trends = new Chart(trendsCtx, {
            type: 'line',
            data: {
                labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
                datasets: [
                    {
                        label: 'H2S',
                        data: [3.2, 4.1, 5.3, 4.8, 6.2, 4.5, 3.1],
                        borderColor: '#e74c3c',
                        tension: 0.4
                    },
                    {
                        label: 'CO',
                        data: [12, 15, 18, 16, 22, 17, 13],
                        borderColor: '#f39c12',
                        tension: 0.4
                    }
                ]
            },
            options: {
                responsive: true
            }
        });
    }
}

function updateCharts() {
    if (!state.charts.gas) return;
    
    // Add new data point
    const now = new Date();
    const timeLabel = now.toLocaleTimeString();
    
    if (state.charts.gas.data.labels.length > 20) {
        state.charts.gas.data.labels.shift();
        state.charts.gas.data.datasets[0].data.shift();
        state.charts.gas.data.datasets[1].data.shift();
    }
    
    // Get latest readings
    const latestH2S = state.gasReadings.length > 0 ? state.gasReadings[state.gasReadings.length - 1].h2s : Math.random() * 10;
    const latestO2 = state.gasReadings.length > 0 ? state.gasReadings[state.gasReadings.length - 1].o2 : 19 + Math.random() * 2;
    
    state.charts.gas.data.labels.push(timeLabel);
    state.charts.gas.data.datasets[0].data.push(latestH2S);
    state.charts.gas.data.datasets[1].data.push(latestO2);
    
    state.charts.gas.update();
}

function updateSessionPieChart() {
    if (!state.charts.pie) return;
    
    const safe = state.sessions.filter(s => s.pre_entry_decision === 'SAFE').length;
    const caution = state.sessions.filter(s => s.pre_entry_decision === 'CAUTION').length;
    const block = state.sessions.filter(s => s.pre_entry_decision === 'BLOCK').length;
    
    state.charts.pie.data.datasets[0].data = [safe, caution, block];
    state.charts.pie.update();
}

function updateAnalyticsCharts(data) {
    // Update risk pie chart
    if (state.charts.riskPie && data) {
        state.charts.riskPie.data.datasets[0].data = [
            data.safe_percent || 85,
            data.caution_percent || 10,
            data.block_percent || 5
        ];
        state.charts.riskPie.update();
    }
}

// ==================== UTILITY FUNCTIONS ====================
function updateConnectionStatus(connected) {
    const statusEl = document.getElementById('connection-status');
    if (!statusEl) return;
    
    state.connected = connected;
    
    if (connected) {
        statusEl.innerHTML = '<i class="fas fa-circle"></i><span>Connected</span>';
        statusEl.classList.remove('disconnected');
    } else {
        statusEl.innerHTML = '<i class="fas fa-circle"></i><span>Disconnected</span>';
        statusEl.classList.add('disconnected');
    }
}

function initializeDateTime() {
    updateDateTime();
    setInterval(updateDateTime, 1000);
}

function updateDateTime() {
    const now = new Date();
    const datetimeEl = document.getElementById('datetime');
    if (datetimeEl) {
        datetimeEl.textContent = now.toLocaleString();
    }
}

function startDataRefresh() {
    setInterval(() => {
        if (state.connected) {
            loadDashboardData();
        }
    }, CONFIG.REFRESH_INTERVAL);
}

function showNotification(alert) {
    // Check if browser notifications are supported and permitted
    if (!("Notification" in window) || Notification.permission !== "granted") {
        return;
    }
    
    new Notification(`🚨 ${alert.severity.toUpperCase()} Alert`, {
        body: alert.message || `${alert.alert_type} detected`,
        icon: '/assets/icons/alert.png',
        silent: false
    });
}

function playAlertSound() {
    const audio = new Audio('https://www.soundjay.com/misc/sounds/bell-ringing-05.mp3');
    audio.play().catch(e => console.log('Sound play failed:', e));
}

// ==================== EVENT LISTENERS ====================
function setupEventListeners() {
    // Refresh button
    const refreshBtn = document.getElementById('refresh-btn');
    if (refreshBtn) {
        refreshBtn.addEventListener('click', () => {
            loadDashboardData();
        });
    }
    
    // Logout button
    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', () => {
            localStorage.removeItem('token');
            window.location.href = '/login.html';
        });
    }
    
    // Gas chart range selector
    const gasChartRange = document.getElementById('gas-chart-range');
    if (gasChartRange) {
        gasChartRange.addEventListener('change', (e) => {
            // Load different time range
            console.log('Chart range changed:', e.target.value);
        });
    }
    
    // Settings save
    const saveSettings = document.getElementById('save-settings');
    if (saveSettings) {
        saveSettings.addEventListener('click', () => {
            saveSettings();
        });
    }
    
    // Analytics update
    const analyticsUpdate = document.getElementById('analytics-update');
    if (analyticsUpdate) {
        analyticsUpdate.addEventListener('click', () => {
            loadAnalyticsData();
        });
    }
    
    // Map controls
    const mapRecenter = document.getElementById('map-recenter');
    if (mapRecenter) {
        mapRecenter.addEventListener('click', () => {
            if (state.fullMap) {
                state.fullMap.setView(CONFIG.MAP_CENTER, CONFIG.MAP_ZOOM);
            }
        });
    }
    
    const mapLayers = document.getElementById('map-layers');
    if (mapLayers) {
        mapLayers.addEventListener('click', () => {
            alert('Layer control would open here');
        });
    }
    
    // Worker search
    const workerSearch = document.getElementById('worker-search');
    if (workerSearch) {
        workerSearch.addEventListener('input', (e) => {
            filterWorkers(e.target.value);
        });
    }
    
    // Alert filters
    const alertSeverity = document.getElementById('alert-severity-filter');
    if (alertSeverity) {
        alertSeverity.addEventListener('change', filterAlerts);
    }
    
    const alertStatus = document.getElementById('alert-status-filter');
    if (alertStatus) {
        alertStatus.addEventListener('change', filterAlerts);
    }
    
    // Modal close
    const closeBtn = document.querySelector('.close');
    if (closeBtn) {
        closeBtn.addEventListener('click', closeModal);
    }
    
    window.addEventListener('click', (e) => {
        if (e.target.classList.contains('modal')) {
            closeModal();
        }
    });
}

// ==================== ACTION FUNCTIONS ====================
window.viewWorker = function(workerId) {
    console.log('View worker:', workerId);
    alert(`View worker details for ID: ${workerId}`);
    // Navigate to worker details page
};

window.contactWorker = function(workerId) {
    console.log('Contact worker:', workerId);
    alert(`Contact worker options for ID: ${workerId}`);
    // Show contact options modal
};

window.viewAlert = async function(alertId) {
    try {
        const response = await fetch(`${CONFIG.API_URL}/alerts/${alertId}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('token')}` }
        });
        
        if (response.ok) {
            const data = await response.json();
            showAlertModal(data.data || data);
        } else {
            // Fallback for demo
            showAlertModal({
                id: alertId,
                alert_type: 'Sample Alert',
                severity: 'critical',
                timestamp: new Date().toISOString(),
                worker_name: 'Worker 1',
                message: 'Sample alert for demonstration',
                current_value: 12.5,
                threshold_value: 10,
                acknowledged: false,
                resolved: false
            });
        }
    } catch (error) {
        console.error('Failed to load alert:', error);
        // Show demo modal
        showAlertModal({
            id: alertId,
            alert_type: 'Demo Alert',
            severity: 'warning',
            timestamp: new Date().toISOString(),
            worker_name: 'Demo Worker',
            message: 'This is a demonstration alert',
            current_value: 8.2,
            threshold_value: 10,
            acknowledged: false,
            resolved: false
        });
    }
};

window.acknowledgeAlert = async function(alertId) {
    try {
        const response = await fetch(`${CONFIG.API_URL}/alerts/${alertId}/acknowledge`, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('token')}`,
                'Content-Type': 'application/json'
            }
        });
        
        if (response.ok) {
            // Update local state
            const alert = state.alerts.find(a => a.id === alertId);
            if (alert) {
                alert.acknowledged = true;
                updateAlertsFeed();
                updateAlertBadge();
                updateAlertsTable(state.alerts);
            }
        } else {
            // Demo fallback
            const alert = state.alerts.find(a => a.id === alertId);
            if (alert) {
                alert.acknowledged = true;
                updateAlertsFeed();
                updateAlertBadge();
                updateAlertsTable(state.alerts);
            }
        }
    } catch (error) {
        console.error('Failed to acknowledge alert:', error);
        // Demo fallback
        const alert = state.alerts.find(a => a.id === alertId);
        if (alert) {
            alert.acknowledged = true;
            updateAlertsFeed();
            updateAlertBadge();
            updateAlertsTable(state.alerts);
        }
    }
};

window.viewSession = function(sessionId) {
    console.log('View session:', sessionId);
    alert(`View session details for ID: ${sessionId}`);
    navigateToPage('sessions');
};

window.endSession = async function(sessionId) {
    if (!confirm('Are you sure you want to end this session?')) return;
    
    try {
        const response = await fetch(`${CONFIG.API_URL}/sessions/${sessionId}/end`, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('token')}`,
                'Content-Type': 'application/json'
            }
        });
        
        if (response.ok) {
            loadSessionsData();
        } else {
            // Demo fallback
            state.sessions = state.sessions.filter(s => s.session_id !== sessionId);
            updateSessionsDisplay(state.sessions);
            updateSessionPieChart();
        }
    } catch (error) {
        console.error('Failed to end session:', error);
        // Demo fallback
        state.sessions = state.sessions.filter(s => s.session_id !== sessionId);
        updateSessionsDisplay(state.sessions);
        updateSessionPieChart();
    }
};

// ==================== MODAL FUNCTIONS ====================
function showAlertModal(alert) {
    const modal = document.getElementById('alert-modal');
    const body = document.getElementById('alert-modal-body');
    
    if (!modal || !body) return;
    
    body.innerHTML = `
        <div class="alert-detail-item">
            <div class="alert-detail-label">Alert ID:</div>
            <div class="alert-detail-value">${alert.id}</div>
        </div>
        <div class="alert-detail-item">
            <div class="alert-detail-label">Type:</div>
            <div class="alert-detail-value">${alert.alert_type}</div>
        </div>
        <div class="alert-detail-item">
            <div class="alert-detail-label">Severity:</div>
            <div class="alert-detail-value"><span class="status-badge ${alert.severity}">${alert.severity}</span></div>
        </div>
        <div class="alert-detail-item">
            <div class="alert-detail-label">Time:</div>
            <div class="alert-detail-value">${new Date(alert.timestamp).toLocaleString()}</div>
        </div>
        <div class="alert-detail-item">
            <div class="alert-detail-label">Worker:</div>
            <div class="alert-detail-value">${alert.worker_name || 'Unknown'}</div>
        </div>
        <div class="alert-detail-item">
            <div class="alert-detail-label">Location:</div>
            <div class="alert-detail-value">Manhole ${alert.manhole_id || 'Unknown'}</div>
        </div>
        <div class="alert-detail-item">
            <div class="alert-detail-label">Value:</div>
            <div class="alert-detail-value">${alert.current_value || ''} ${alert.threshold_value ? `(threshold: ${alert.threshold_value})` : ''}</div>
        </div>
        <div class="alert-detail-item">
            <div class="alert-detail-label">Message:</div>
            <div class="alert-detail-value">${alert.message || 'No message'}</div>
        </div>
        <div class="alert-detail-item">
            <div class="alert-detail-label">Status:</div>
            <div class="alert-detail-value">
                ${alert.acknowledged ? 'Acknowledged' : 'Not Acknowledged'} | 
                ${alert.resolved ? 'Resolved' : 'Not Resolved'}
            </div>
        </div>
    `;
    
    // Set up acknowledge button
    const ackBtn = document.getElementById('acknowledge-alert-btn');
    if (ackBtn) {
        if (alert.acknowledged) {
            ackBtn.disabled = true;
            ackBtn.textContent = 'Already Acknowledged';
        } else {
            ackBtn.disabled = false;
            ackBtn.textContent = 'Acknowledge';
            ackBtn.onclick = () => {
                acknowledgeAlert(alert.id);
                closeModal();
            };
        }
    }
    
    modal.style.display = 'block';
}

function closeModal() {
    const modal = document.getElementById('alert-modal');
    if (modal) {
        modal.style.display = 'none';
    }
}

// ==================== FILTER FUNCTIONS ====================
function filterWorkers(query) {
    if (!query) {
        loadWorkersData();
        return;
    }
    
    const filtered = state.workers.filter(w => 
        w.full_name?.toLowerCase().includes(query.toLowerCase()) ||
        w.worker_id?.toLowerCase().includes(query.toLowerCase())
    );
    updateWorkersTable(filtered);
}

function filterAlerts() {
    const severity = document.getElementById('alert-severity-filter')?.value || 'all';
    const status = document.getElementById('alert-status-filter')?.value || 'all';
    
    let filtered = state.alerts;
    
    if (severity !== 'all') {
        filtered = filtered.filter(a => a.severity === severity);
    }
    
    if (status === 'active') {
        filtered = filtered.filter(a => !a.acknowledged && !a.resolved);
    } else if (status === 'acknowledged') {
        filtered = filtered.filter(a => a.acknowledged && !a.resolved);
    } else if (status === 'resolved') {
        filtered = filtered.filter(a => a.resolved);
    }
    
    updateAlertsTable(filtered);
}

// ==================== SETTINGS FUNCTIONS ====================
function saveSettings() {
    const settings = {
        thresholds: {
            h2s: {
                caution: parseFloat(document.getElementById('th-h2s-caution')?.value || 5),
                block: parseFloat(document.getElementById('th-h2s-block')?.value || 10)
            },
            o2: {
                caution: parseFloat(document.getElementById('th-o2-caution')?.value || 20.8),
                block: parseFloat(document.getElementById('th-o2-block')?.value || 19.5)
            }
        },
        escalation: {
            level1: parseInt(document.getElementById('esc-level1')?.value || 5),
            level2: parseInt(document.getElementById('esc-level2')?.value || 10),
            level3: parseInt(document.getElementById('esc-level3')?.value || 15)
        },
        notifications: {
            email: document.getElementById('notif-email')?.checked || false,
            sms: document.getElementById('notif-sms')?.checked || false,
            sound: document.getElementById('notif-sound')?.checked || false
        },
        retention: parseInt(document.getElementById('data-retention')?.value || 30)
    };
    
    // Save to localStorage for demo
    localStorage.setItem('dashboard_settings', JSON.stringify(settings));
    
    alert('Settings saved successfully!');
    
    // Show notification if sound is enabled
    if (settings.notifications.sound) {
        playAlertSound();
    }
}

// ==================== EXPORT FUNCTIONS ====================
window.exportData = function(format = 'csv') {
    console.log('Exporting data as:', format);
    
    let data = '';
    let filename = '';
    
    if (format === 'csv') {
        // Create CSV
        const headers = ['timestamp', 'h2s', 'ch4', 'co', 'o2', 'worker_id'];
        data = headers.join(',') + '\n';
        
        state.gasReadings.slice(-100).forEach(r => {
            data += `${r.timestamp},${r.h2s},${r.ch4},${r.co},${r.o2},${r.worker_id}\n`;
        });
        
        filename = `safety_data_${new Date().toISOString().slice(0,10)}.csv`;
    } else {
        // Create JSON
        data = JSON.stringify({
            workers: state.workers,
            sessions: state.sessions,
            alerts: state.alerts,
            readings: state.gasReadings.slice(-100)
        }, null, 2);
        
        filename = `safety_data_${new Date().toISOString().slice(0,10)}.json`;
    }
    
    // Download file
    const blob = new Blob([data], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
};

// ==================== DEMO DATA INITIALIZATION ====================
function initDemoData() {
    if (state.workers.length === 0) {
        // Add demo workers
        state.workers = [
            { id: '1', worker_id: 'W001', full_name: 'Suresh Patil', is_active: true, heart_rate: 72, location: 'MH-023', current_h2s: 2.3 },
            { id: '2', worker_id: 'W002', full_name: 'Mahesh Desai', is_active: true, heart_rate: 78, location: 'MH-045', current_h2s: 4.1 },
            { id: '3', worker_id: 'W003', full_name: 'Rajesh Kumar', is_active: false, heart_rate: 0, location: 'Offline' }
        ];
    }
    
    if (state.sessions.length === 0) {
        // Add demo sessions
        state.sessions = [
            { session_id: 'S001', manhole_id: 'MH-023', pre_entry_decision: 'SAFE', worker1_name: 'Suresh Patil', start_time: new Date(Date.now() - 2*3600000).toISOString() },
            { session_id: 'S002', manhole_id: 'MH-045', pre_entry_decision: 'CAUTION', worker1_name: 'Mahesh Desai', start_time: new Date(Date.now() - 1.5*3600000).toISOString() }
        ];
    }
    
    if (state.alerts.length === 0) {
        // Add demo alerts
        state.alerts = [
            { id: 'a1', alert_type: 'High H2S', severity: 'critical', message: 'H2S level exceeded 10ppm', timestamp: new Date(Date.now() - 5*60000).toISOString(), worker_name: 'Suresh Patil', acknowledged: false },
            { id: 'a2', alert_type: 'Low O2', severity: 'warning', message: 'O2 level below 19.5%', timestamp: new Date(Date.now() - 15*60000).toISOString(), worker_name: 'Mahesh Desai', acknowledged: true }
        ];
    }
    
    updateDashboard();
}

// Call demo data init after a short delay if no data
setTimeout(() => {
    if (state.workers.length === 0) {
        initDemoData();
    }
}, 2000);

// Initialize on load
console.log('✅ Dashboard app initialized');