/**
 * Alerts Feed Component
 * Renders real-time alerts feed for the dashboard
 */

window.AlertsFeed = (function() {
    'use strict';
    
    // Alert severity icons
    const SEVERITY_ICONS = {
        critical: 'fa-exclamation-triangle',
        warning: 'fa-exclamation-circle',
        info: 'fa-info-circle',
        success: 'fa-check-circle'
    };
    
    // Alert severity colors
    const SEVERITY_COLORS = {
        critical: '#e74c3c',
        warning: '#f39c12',
        info: '#3498db',
        success: '#27ae60'
    };
    
    // Format timestamp to relative time
    function formatRelativeTime(timestamp) {
        const now = new Date();
        const alertTime = new Date(timestamp);
        const diffSeconds = Math.floor((now - alertTime) / 1000);
        
        if (diffSeconds < 60) {
            return `${diffSeconds} seconds ago`;
        } else if (diffSeconds < 3600) {
            const minutes = Math.floor(diffSeconds / 60);
            return `${minutes} minute${minutes > 1 ? 's' : ''} ago`;
        } else if (diffSeconds < 86400) {
            const hours = Math.floor(diffSeconds / 3600);
            return `${hours} hour${hours > 1 ? 's' : ''} ago`;
        } else {
            return alertTime.toLocaleDateString();
        }
    }
    
    // Get alert icon based on type and severity
    function getAlertIcon(alert) {
        if (alert.alert_type?.toLowerCase().includes('h2s')) return 'fa-flask';
        if (alert.alert_type?.toLowerCase().includes('o2')) return 'fa-wind';
        if (alert.alert_type?.toLowerCase().includes('fall')) return 'fa-person-falling';
        if (alert.alert_type?.toLowerCase().includes('panic')) return 'fa-bell';
        if (alert.alert_type?.toLowerCase().includes('flood')) return 'fa-water';
        if (alert.alert_type?.toLowerCase().includes('vibration')) return 'fa-wave-square';
        return SEVERITY_ICONS[alert.severity] || 'fa-bell';
    }
    
    // Get severity class name
    function getSeverityClass(severity) {
        switch(severity?.toLowerCase()) {
            case 'critical': return 'critical';
            case 'warning': return 'warning';
            case 'info': return 'info';
            case 'success': return 'success';
            default: return 'info';
        }
    }
    
    // Render a single alert item
    function renderAlertItem(alert) {
        const severityClass = getSeverityClass(alert.severity);
        const icon = getAlertIcon(alert);
        const relativeTime = formatRelativeTime(alert.timestamp);
        const statusClass = alert.acknowledged ? 'acknowledged' : 'new';
        const statusText = alert.acknowledged ? 'Acknowledged' : 'New';
        
        return `
            <div class="alert-item" data-alert-id="${alert.id}" onclick="window.AlertsFeed.onAlertClick('${alert.id}')">
                <div class="alert-icon ${severityClass}">
                    <i class="fas ${icon}"></i>
                </div>
                <div class="alert-content">
                    <div class="alert-title">
                        ${alert.message || alert.alert_type || 'Unknown Alert'}
                    </div>
                    <div class="alert-meta">
                        <span class="alert-time">
                            <i class="fas fa-clock"></i> ${relativeTime}
                        </span>
                        <span class="alert-worker">
                            <i class="fas fa-user"></i> ${alert.worker_name || 'Unknown'}
                        </span>
                        ${alert.location ? `
                            <span class="alert-location">
                                <i class="fas fa-map-marker-alt"></i> ${alert.location}
                            </span>
                        ` : ''}
                        ${alert.current_value ? `
                            <span class="alert-value" style="color: ${SEVERITY_COLORS[alert.severity]}">
                                <i class="fas fa-chart-line"></i> ${alert.current_value}${alert.unit || ''}
                            </span>
                        ` : ''}
                    </div>
                </div>
                <div class="alert-status ${statusClass}">
                    ${statusText}
                </div>
                <div class="alert-actions">
                    <button class="btn-icon" onclick="event.stopPropagation(); window.AlertsFeed.acknowledgeAlert('${alert.id}')" 
                            ${alert.acknowledged ? 'disabled' : ''} title="Acknowledge">
                        <i class="fas fa-check"></i>
                    </button>
                    <button class="btn-icon" onclick="event.stopPropagation(); window.AlertsFeed.viewDetails('${alert.id}')" title="View Details">
                        <i class="fas fa-eye"></i>
                    </button>
                </div>
            </div>
        `;
    }
    
    // Render alert feed with filters
    function render(alerts = [], options = {}) {
        const {
            maxItems = 50,
            showFilters = true,
            showHeader = true,
            filterable = true,
            onAcknowledge = null,
            onClick = null
        } = options;
        
        if (!alerts || alerts.length === 0) {
            return `
                <div class="alerts-feed empty">
                    <div class="empty-state">
                        <i class="fas fa-check-circle" style="font-size: 48px; color: #27ae60;"></i>
                        <h3>All Clear!</h3>
                        <p>No active alerts at this time</p>
                    </div>
                </div>
            `;
        }
        
        // Sort by timestamp (newest first)
        const sortedAlerts = [...alerts]
            .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
            .slice(0, maxItems);
        
        // Count by severity
        const counts = {
            critical: alerts.filter(a => a.severity === 'critical' && !a.acknowledged).length,
            warning: alerts.filter(a => a.severity === 'warning' && !a.acknowledged).length,
            info: alerts.filter(a => a.severity === 'info' && !a.acknowledged).length
        };
        
        const filters = showFilters ? `
            <div class="alerts-filters">
                <div class="filter-badges">
                    <span class="filter-badge critical" data-severity="critical">
                        Critical <span class="count">${counts.critical}</span>
                    </span>
                    <span class="filter-badge warning" data-severity="warning">
                        Warning <span class="count">${counts.warning}</span>
                    </span>
                    <span class="filter-badge info" data-severity="info">
                        Info <span class="count">${counts.info}</span>
                    </span>
                </div>
                <div class="filter-actions">
                    <button class="filter-btn active" data-filter="all">All</button>
                    <button class="filter-btn" data-filter="unacknowledged">New</button>
                </div>
            </div>
        ` : '';
        
        const header = showHeader ? `
            <div class="alerts-header">
                <h4><i class="fas fa-bell"></i> Real-time Alerts</h4>
                <span class="alerts-count">${alerts.filter(a => !a.acknowledged).length} new</span>
            </div>
        ` : '';
        
        return `
            <div class="alerts-feed-container">
                ${header}
                ${filters}
                <div class="alerts-list">
                    ${sortedAlerts.map(alert => renderAlertItem(alert)).join('')}
                </div>
                ${alerts.length > maxItems ? `
                    <div class="alerts-footer">
                        <button class="view-all-btn" onclick="window.AlertsFeed.viewAll()">
                            View All ${alerts.length} Alerts
                        </button>
                    </div>
                ` : ''}
            </div>
        `;
    }
    
    // Render compact version for sidebar/widget
    function renderCompact(alerts = [], maxItems = 5) {
        if (!alerts || alerts.length === 0) {
            return `
                <div class="alerts-compact empty">
                    <i class="fas fa-check-circle" style="color: #27ae60;"></i>
                    <span>No alerts</span>
                </div>
            `;
        }
        
        const unacknowledged = alerts.filter(a => !a.acknowledged);
        const displayAlerts = unacknowledged.length > 0 ? unacknowledged : alerts;
        const recentAlerts = displayAlerts.slice(0, maxItems);
        
        return `
            <div class="alerts-compact">
                ${recentAlerts.map(alert => {
                    const severityClass = getSeverityClass(alert.severity);
                    return `
                        <div class="alert-mini ${severityClass}" title="${alert.message || alert.alert_type}">
                            <i class="fas ${getAlertIcon(alert)}"></i>
                            <span class="alert-mini-time">${formatRelativeTime(alert.timestamp)}</span>
                        </div>
                    `;
                }).join('')}
                ${displayAlerts.length > maxItems ? `
                    <div class="alert-mini more">
                        +${displayAlerts.length - maxItems} more
                    </div>
                ` : ''}
            </div>
        `;
    }
    
    // Render alert statistics
    function renderStats(alerts = []) {
        const total = alerts.length;
        const critical = alerts.filter(a => a.severity === 'critical').length;
        const warning = alerts.filter(a => a.severity === 'warning').length;
        const info = alerts.filter(a => a.severity === 'info').length;
        const unacknowledged = alerts.filter(a => !a.acknowledged).length;
        
        return `
            <div class="alerts-stats">
                <div class="stat-item">
                    <span class="stat-label">Total</span>
                    <span class="stat-value">${total}</span>
                </div>
                <div class="stat-item critical">
                    <span class="stat-label">Critical</span>
                    <span class="stat-value">${critical}</span>
                </div>
                <div class="stat-item warning">
                    <span class="stat-label">Warning</span>
                    <span class="stat-value">${warning}</span>
                </div>
                <div class="stat-item info">
                    <span class="stat-label">Info</span>
                    <span class="stat-value">${info}</span>
                </div>
                <div class="stat-item unacknowledged">
                    <span class="stat-label">New</span>
                    <span class="stat-value">${unacknowledged}</span>
                </div>
            </div>
        `;
    }
    
    // Event handlers (to be overridden by main app)
    const eventHandlers = {
        onAcknowledge: null,
        onClick: null,
        onFilter: null
    };
    
    // Set event handlers
    function setHandlers(handlers) {
        Object.assign(eventHandlers, handlers);
    }
    
    // Handle alert click
    function onAlertClick(alertId) {
        if (eventHandlers.onClick) {
            eventHandlers.onClick(alertId);
        }
    }
    
    // Handle acknowledge
    function acknowledgeAlert(alertId) {
        if (eventHandlers.onAcknowledge) {
            eventHandlers.onAcknowledge(alertId);
        }
    }
    
    // Handle view details
    function viewDetails(alertId) {
        if (eventHandlers.onClick) {
            eventHandlers.onClick(alertId);
        }
    }
    
    // Handle view all
    function viewAll() {
        // Navigate to alerts page
        if (window.navigateToPage) {
            window.navigateToPage('alerts');
        }
    }
    
    // Initialize filter buttons
    function initFilters(container) {
        const filterBtns = container?.querySelectorAll('.filter-btn');
        filterBtns?.forEach(btn => {
            btn.addEventListener('click', (e) => {
                filterBtns.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                
                const filter = btn.dataset.filter;
                if (eventHandlers.onFilter) {
                    eventHandlers.onFilter(filter);
                }
            });
        });
        
        const severityBadges = container?.querySelectorAll('.filter-badge');
        severityBadges?.forEach(badge => {
            badge.addEventListener('click', () => {
                const severity = badge.dataset.severity;
                if (eventHandlers.onFilter) {
                    eventHandlers.onFilter(severity);
                }
            });
        });
    }
    
    // Public API
    return {
        render,
        renderCompact,
        renderStats,
        setHandlers,
        onAlertClick,
        acknowledgeAlert,
        viewDetails,
        viewAll,
        initFilters,
        
        // Utility functions (exposed for testing)
        formatRelativeTime,
        getSeverityClass
    };
})();

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    // Connect to main app event handlers if available
    if (window.app) {
        window.AlertsFeed.setHandlers({
            onClick: window.app.viewAlert,
            onAcknowledge: window.app.acknowledgeAlert
        });
    }
});

console.log('✅ AlertsFeed component loaded');