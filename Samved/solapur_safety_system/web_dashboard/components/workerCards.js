/**
 * Worker Cards Component
 * Renders worker status cards for real-time monitoring
 */

window.WorkerCards = (function() {
    'use strict';
    
    // Worker status configuration
    const WORKER_STATUS = {
        active: {
            label: 'Active',
            color: '#27ae60',
            icon: 'fa-check-circle'
        },
        inactive: {
            label: 'Inactive',
            color: '#95a5a6',
            icon: 'fa-circle'
        },
        warning: {
            label: 'Warning',
            color: '#f39c12',
            icon: 'fa-exclamation-triangle'
        },
        critical: {
            label: 'Critical',
            color: '#e74c3c',
            icon: 'fa-exclamation-circle'
        },
        offline: {
            label: 'Offline',
            color: '#7f8c8d',
            icon: 'fa-power-off'
        }
    };
    
    // Get worker status based on vitals
    function getWorkerStatus(worker) {
        if (!worker.is_active) return 'inactive';
        
        // Check heart rate
        if (worker.heart_rate > 120 || worker.heart_rate < 40) {
            return 'critical';
        } else if (worker.heart_rate > 100) {
            return 'warning';
        }
        
        // Check gas exposure (if available)
        if (worker.current_h2s > 10) return 'critical';
        if (worker.current_h2s > 5) return 'warning';
        
        // Check fall detection
        if (worker.fall_detected) return 'critical';
        
        // Check panic button
        if (worker.panic_pressed) return 'critical';
        
        return 'active';
    }
    
    // Format duration
    function formatDuration(minutes) {
        if (minutes < 60) {
            return `${minutes} min`;
        }
        const hours = Math.floor(minutes / 60);
        const mins = minutes % 60;
        return `${hours}h ${mins}m`;
    }
    
    // Get time on site
    function getTimeOnSite(worker) {
        if (!worker.session_start) return 'Not started';
        const minutes = Math.floor((new Date() - new Date(worker.session_start)) / 60000);
        return formatDuration(minutes);
    }
    
    // Render a single worker card
    function renderWorkerCard(worker, options = {}) {
        const {
            showDetails = true,
            showActions = true,
            size = 'medium'
        } = options;
        
        const status = getWorkerStatus(worker);
        const statusConfig = WORKER_STATUS[status];
        const timeOnSite = getTimeOnSite(worker);
        
        const sizeClass = {
            small: 'worker-card-small',
            medium: 'worker-card-medium',
            large: 'worker-card-large'
        }[size] || 'worker-card-medium';
        
        // Determine avatar content
        const avatarContent = worker.avatar 
            ? `<img src="${worker.avatar}" alt="${worker.full_name}">`
            : `<i class="fas fa-user-hard-hat"></i>`;
        
        return `
            <div class="worker-card ${sizeClass}" data-worker-id="${worker.id}" data-status="${status}">
                <div class="worker-card-header">
                    <div class="worker-avatar">
                        ${avatarContent}
                    </div>
                    <div class="worker-title">
                        <h4>${worker.full_name || `Worker ${worker.worker_id}`}</h4>
                        <span class="worker-id">ID: ${worker.worker_id || 'Unknown'}</span>
                    </div>
                    <div class="worker-status-badge" style="background: ${statusConfig.color}20; color: ${statusConfig.color};">
                        <i class="fas ${statusConfig.icon}"></i>
                        ${statusConfig.label}
                    </div>
                </div>
                
                ${showDetails ? `
                    <div class="worker-details">
                        <div class="detail-row">
                            <div class="detail-item">
                                <i class="fas fa-heartbeat" style="color: #e74c3c;"></i>
                                <span class="detail-label">Heart Rate:</span>
                                <span class="detail-value ${worker.heart_rate > 100 ? 'warning' : ''}">
                                    ${worker.heart_rate || '--'} bpm
                                </span>
                            </div>
                            <div class="detail-item">
                                <i class="fas fa-lungs" style="color: #3498db;"></i>
                                <span class="detail-label">SpO2:</span>
                                <span class="detail-value">${worker.spo2 || '--'}%</span>
                            </div>
                        </div>
                        
                        <div class="detail-row">
                            <div class="detail-item">
                                <i class="fas fa-flask" style="color: #e74c3c;"></i>
                                <span class="detail-label">H2S:</span>
                                <span class="detail-value ${worker.current_h2s > 10 ? 'critical' : worker.current_h2s > 5 ? 'warning' : ''}">
                                    ${worker.current_h2s?.toFixed(1) || '0.0'} ppm
                                </span>
                            </div>
                            <div class="detail-item">
                                <i class="fas fa-wind" style="color: #3498db;"></i>
                                <span class="detail-label">O2:</span>
                                <span class="detail-value ${worker.current_o2 < 19.5 ? 'critical' : worker.current_o2 < 20.8 ? 'warning' : ''}">
                                    ${worker.current_o2?.toFixed(1) || '20.9'}%
                                </span>
                            </div>
                        </div>
                        
                        <div class="detail-row">
                            <div class="detail-item">
                                <i class="fas fa-map-marker-alt" style="color: #f39c12;"></i>
                                <span class="detail-label">Location:</span>
                                <span class="detail-value">${worker.location || 'Unknown'}</span>
                            </div>
                            <div class="detail-item">
                                <i class="fas fa-clock" style="color: #9b59b6;"></i>
                                <span class="detail-label">On Site:</span>
                                <span class="detail-value">${timeOnSite}</span>
                            </div>
                        </div>
                        
                        ${worker.fall_detected ? `
                            <div class="alert-badge fall">
                                <i class="fas fa-person-falling"></i> Fall Detected
                            </div>
                        ` : ''}
                        
                        ${worker.panic_pressed ? `
                            <div class="alert-badge panic">
                                <i class="fas fa-bell"></i> Panic Button
                            </div>
                        ` : ''}
                        
                        <div class="detail-row">
                            <div class="detail-item">
                                <i class="fas fa-battery-three-quarters" style="color: #27ae60;"></i>
                                <span class="detail-label">Battery:</span>
                                <span class="detail-value">${worker.battery || 100}%</span>
                            </div>
                            <div class="detail-item">
                                <i class="fas fa-wifi"></i>
                                <span class="detail-label">Signal:</span>
                                <span class="detail-value">${worker.signal || 'Good'}</span>
                            </div>
                        </div>
                    </div>
                ` : ''}
                
                ${showActions ? `
                    <div class="worker-actions">
                        <button class="btn-worker" onclick="window.WorkerCards.viewWorker('${worker.id}')">
                            <i class="fas fa-eye"></i> View
                        </button>
                        <button class="btn-worker" onclick="window.WorkerCards.contactWorker('${worker.id}')">
                            <i class="fas fa-phone"></i> Contact
                        </button>
                        <button class="btn-worker emergency" onclick="window.WorkerCards.emergency('${worker.id}')">
                            <i class="fas fa-exclamation-triangle"></i> Emergency
                        </button>
                    </div>
                ` : ''}
            </div>
        `;
    }
    
    // Render a grid of worker cards
    function renderGrid(workers = [], options = {}) {
        const {
            columns = 2,
            maxWorkers = 10,
            showDetails = true,
            showActions = true,
            size = 'medium'
        } = options;
        
        if (!workers || workers.length === 0) {
            return `
                <div class="workers-empty">
                    <i class="fas fa-users-slash" style="font-size: 48px; color: #34495e;"></i>
                    <h3>No Active Workers</h3>
                    <p>No workers are currently on site</p>
                </div>
            `;
        }
        
        const displayWorkers = workers.slice(0, maxWorkers);
        const gridClass = `workers-grid columns-${columns}`;
        
        return `
            <div class="${gridClass}">
                ${displayWorkers.map(worker => renderWorkerCard(worker, {
                    showDetails,
                    showActions,
                    size
                })).join('')}
            </div>
        `;
    }
    
    // Render compact list for sidebar
    function renderCompact(workers = [], maxItems = 3) {
        if (!workers || workers.length === 0) {
            return `
                <div class="workers-compact empty">
                    <i class="fas fa-users-slash"></i>
                    <span>No workers</span>
                </div>
            `;
        }
        
        return `
            <div class="workers-compact">
                ${workers.slice(0, maxItems).map(worker => {
                    const status = getWorkerStatus(worker);
                    const statusConfig = WORKER_STATUS[status];
                    
                    return `
                        <div class="worker-mini" data-status="${status}" onclick="window.WorkerCards.viewWorker('${worker.id}')">
                            <div class="worker-mini-avatar">
                                <i class="fas fa-user-hard-hat"></i>
                            </div>
                            <div class="worker-mini-info">
                                <div class="worker-mini-name">${worker.full_name || `Worker ${worker.worker_id}`}</div>
                                <div class="worker-mini-status">
                                    <span class="status-dot" style="background: ${statusConfig.color};"></span>
                                    ${statusConfig.label}
                                </div>
                            </div>
                            <div class="worker-mini-value">
                                ${worker.heart_rate || '--'} <small>bpm</small>
                            </div>
                        </div>
                    `;
                }).join('')}
                ${workers.length > maxItems ? `
                    <div class="worker-mini more">
                        +${workers.length - maxItems} more workers
                    </div>
                ` : ''}
            </div>
        `;
    }
    
    // Render worker statistics
    function renderStats(workers = []) {
        const active = workers.filter(w => w.is_active).length;
        const warning = workers.filter(w => getWorkerStatus(w) === 'warning').length;
        const critical = workers.filter(w => getWorkerStatus(w) === 'critical').length;
        const inactive = workers.filter(w => !w.is_active).length;
        
        return `
            <div class="workers-stats">
                <div class="stat-circle active">
                    <div class="stat-number">${active}</div>
                    <div class="stat-label">Active</div>
                </div>
                <div class="stat-circle warning">
                    <div class="stat-number">${warning}</div>
                    <div class="stat-label">Warning</div>
                </div>
                <div class="stat-circle critical">
                    <div class="stat-number">${critical}</div>
                    <div class="stat-label">Critical</div>
                </div>
                <div class="stat-circle inactive">
                    <div class="stat-number">${inactive}</div>
                    <div class="stat-label">Inactive</div>
                </div>
            </div>
        `;
    }
    
    // Event handlers (to be overridden by main app)
    const eventHandlers = {
        onView: null,
        onContact: null,
        onEmergency: null
    };
    
    // Set event handlers
    function setHandlers(handlers) {
        Object.assign(eventHandlers, handlers);
    }
    
    // Handle view worker
    function viewWorker(workerId) {
        if (eventHandlers.onView) {
            eventHandlers.onView(workerId);
        }
    }
    
    // Handle contact worker
    function contactWorker(workerId) {
        if (eventHandlers.onContact) {
            eventHandlers.onContact(workerId);
        }
    }
    
    // Handle emergency
    function emergency(workerId) {
        if (eventHandlers.onEmergency) {
            eventHandlers.onEmergency(workerId);
        }
    }
    
    // Public API
    return {
        renderWorkerCard,
        renderGrid,
        renderCompact,
        renderStats,
        getWorkerStatus,
        setHandlers,
        viewWorker,
        contactWorker,
        emergency
    };
})();

// Add CSS styles dynamically
const style = document.createElement('style');
style.textContent = `
    .worker-card {
        background: rgba(255,255,255,0.05);
        border-radius: 12px;
        padding: 20px;
        transition: all 0.3s ease;
        border-left: 4px solid transparent;
    }
    
    .worker-card[data-status="active"] {
        border-left-color: #27ae60;
    }
    
    .worker-card[data-status="warning"] {
        border-left-color: #f39c12;
        animation: glow-warning 2s infinite;
    }
    
    .worker-card[data-status="critical"] {
        border-left-color: #e74c3c;
        animation: glow-critical 2s infinite;
    }
    
    .worker-card[data-status="inactive"] {
        border-left-color: #95a5a6;
        opacity: 0.7;
    }
    
    @keyframes glow-warning {
        0% { box-shadow: 0 0 5px rgba(243, 156, 18, 0.2); }
        50% { box-shadow: 0 0 15px rgba(243, 156, 18, 0.4); }
        100% { box-shadow: 0 0 5px rgba(243, 156, 18, 0.2); }
    }
    
    @keyframes glow-critical {
        0% { box-shadow: 0 0 5px rgba(231, 76, 60, 0.2); }
        50% { box-shadow: 0 0 20px rgba(231, 76, 60, 0.5); }
        100% { box-shadow: 0 0 5px rgba(231, 76, 60, 0.2); }
    }
    
    .worker-card:hover {
        transform: translateY(-2px);
        background: rgba(255,255,255,0.08);
    }
    
    .worker-card-header {
        display: flex;
        align-items: center;
        gap: 15px;
        margin-bottom: 15px;
    }
    
    .worker-avatar {
        width: 60px;
        height: 60px;
        border-radius: 50%;
        background: linear-gradient(135deg, #3498db, #2980b9);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 30px;
        color: white;
        overflow: hidden;
    }
    
    .worker-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
    }
    
    .worker-title {
        flex: 1;
    }
    
    .worker-title h4 {
        margin: 0 0 5px 0;
        font-size: 18px;
    }
    
    .worker-id {
        font-size: 12px;
        color: #95a5a6;
    }
    
    .worker-status-badge {
        padding: 6px 12px;
        border-radius: 20px;
        font-size: 12px;
        font-weight: 600;
        display: flex;
        align-items: center;
        gap: 5px;
    }
    
    .worker-details {
        margin: 15px 0;
    }
    
    .detail-row {
        display: flex;
        gap: 15px;
        margin-bottom: 10px;
    }
    
    .detail-item {
        flex: 1;
        display: flex;
        align-items: center;
        gap: 5px;
        font-size: 13px;
    }
    
    .detail-item i {
        width: 20px;
    }
    
    .detail-label {
        color: #95a5a6;
    }
    
    .detail-value {
        font-weight: 600;
        margin-left: auto;
    }
    
    .detail-value.warning {
        color: #f39c12;
    }
    
    .detail-value.critical {
        color: #e74c3c;
        animation: pulse 1s infinite;
    }
    
    .alert-badge {
        padding: 8px 12px;
        border-radius: 6px;
        margin: 10px 0;
        font-size: 13px;
        font-weight: 600;
        display: flex;
        align-items: center;
        gap: 8px;
    }
    
    .alert-badge.fall {
        background: rgba(231, 76, 60, 0.2);
        color: #e74c3c;
        animation: pulse 1s infinite;
    }
    
    .alert-badge.panic {
        background: rgba(243, 156, 18, 0.2);
        color: #f39c12;
        animation: pulse 1s infinite;
    }
    
    .worker-actions {
        display: flex;
        gap: 10px;
        margin-top: 15px;
    }
    
    .btn-worker {
        flex: 1;
        padding: 8px;
        border: none;
        border-radius: 6px;
        background: rgba(255,255,255,0.1);
        color: white;
        cursor: pointer;
        font-size: 12px;
        transition: all 0.3s ease;
    }
    
    .btn-worker:hover {
        background: rgba(255,255,255,0.2);
    }
    
    .btn-worker.emergency {
        background: rgba(231, 76, 60, 0.2);
        color: #e74c3c;
    }
    
    .btn-worker.emergency:hover {
        background: rgba(231, 76, 60, 0.3);
    }
    
    .workers-grid {
        display: grid;
        gap: 20px;
    }
    
    .workers-grid.columns-2 {
        grid-template-columns: repeat(2, 1fr);
    }
    
    .workers-grid.columns-3 {
        grid-template-columns: repeat(3, 1fr);
    }
    
    .workers-empty {
        text-align: center;
        padding: 40px;
        background: rgba(255,255,255,0.05);
        border-radius: 12px;
    }
    
    .workers-empty h3 {
        margin: 15px 0 5px;
        color: #95a5a6;
    }
    
    .workers-empty p {
        color: #7f8c8d;
    }
    
    .workers-compact {
        background: rgba(255,255,255,0.05);
        border-radius: 8px;
        overflow: hidden;
    }
    
    .worker-mini {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px;
        border-bottom: 1px solid rgba(255,255,255,0.05);
        cursor: pointer;
        transition: all 0.3s ease;
    }
    
    .worker-mini:hover {
        background: rgba(255,255,255,0.1);
    }
    
    .worker-mini[data-status="warning"] {
        border-left: 3px solid #f39c12;
    }
    
    .worker-mini[data-status="critical"] {
        border-left: 3px solid #e74c3c;
    }
    
    .worker-mini-avatar {
        width: 30px;
        height: 30px;
        border-radius: 50%;
        background: #34495e;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 16px;
    }
    
    .worker-mini-info {
        flex: 1;
    }
    
    .worker-mini-name {
        font-size: 13px;
        font-weight: 600;
    }
    
    .worker-mini-status {
        font-size: 11px;
        display: flex;
        align-items: center;
        gap: 4px;
    }
    
    .status-dot {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        display: inline-block;
    }
    
    .worker-mini-value {
        font-size: 14px;
        font-weight: 600;
    }
    
    .worker-mini-value small {
        font-size: 10px;
        color: #95a5a6;
    }
    
    .worker-mini.more {
        justify-content: center;
        color: #3498db;
    }
    
    .workers-stats {
        display: flex;
        justify-content: space-around;
        padding: 20px;
        background: rgba(255,255,255,0.05);
        border-radius: 12px;
    }
    
    .stat-circle {
        text-align: center;
    }
    
    .stat-number {
        font-size: 24px;
        font-weight: 700;
    }
    
    .stat-label {
        font-size: 12px;
        color: #95a5a6;
    }
    
    .stat-circle.active .stat-number { color: #27ae60; }
    .stat-circle.warning .stat-number { color: #f39c12; }
    .stat-circle.critical .stat-number { color: #e74c3c; }
    .stat-circle.inactive .stat-number { color: #95a5a6; }
    
    @media (max-width: 768px) {
        .workers-grid.columns-3 {
            grid-template-columns: 1fr;
        }
        
        .detail-row {
            flex-direction: column;
            gap: 5px;
        }
    }
`;

document.head.appendChild(style);

console.log('✅ WorkerCards component loaded');