/**
 * Gas Gauges Component
 * Renders beautiful circular gauges for gas monitoring
 */

window.GasGauges = (function() {
    'use strict';
    
    // Gas configuration (matching Flutter app)
    const GAS_CONFIG = {
        h2s: {
            name: 'H2S',
            unit: 'ppm',
            min: 0,
            max: 20,
            caution: 5,
            block: 10,
            color: '#e74c3c',
            description: 'Hydrogen Sulfide',
            thresholds: {
                safe: { min: 0, max: 5, color: '#27ae60' },
                caution: { min: 5, max: 10, color: '#f39c12' },
                block: { min: 10, max: 20, color: '#e74c3c' }
            }
        },
        ch4: {
            name: 'CH₄',
            unit: '%LEL',
            min: 0,
            max: 5,
            caution: 0.5,
            block: 2,
            color: '#f39c12',
            description: 'Methane',
            thresholds: {
                safe: { min: 0, max: 0.5, color: '#27ae60' },
                caution: { min: 0.5, max: 2, color: '#f39c12' },
                block: { min: 2, max: 5, color: '#e74c3c' }
            }
        },
        co: {
            name: 'CO',
            unit: 'ppm',
            min: 0,
            max: 50,
            caution: 25,
            block: 35,
            color: '#e67e22',
            description: 'Carbon Monoxide',
            thresholds: {
                safe: { min: 0, max: 25, color: '#27ae60' },
                caution: { min: 25, max: 35, color: '#f39c12' },
                block: { min: 35, max: 50, color: '#e74c3c' }
            }
        },
        o2: {
            name: 'O₂',
            unit: '%',
            min: 18,
            max: 22,
            caution: 20.8,
            block: 19.5,
            color: '#3498db',
            description: 'Oxygen',
            inverted: true,
            thresholds: {
                safe: { min: 20.8, max: 22, color: '#27ae60' },
                caution: { min: 19.5, max: 20.8, color: '#f39c12' },
                block: { min: 18, max: 19.5, color: '#e74c3c' }
            }
        }
    };
    
    // Get status based on gas type and value
    function getGasStatus(gasType, value) {
        const config = GAS_CONFIG[gasType];
        if (!config) return 'unknown';
        
        if (config.inverted) {
            if (value <= config.block) return 'block';
            if (value <= config.caution) return 'caution';
            return 'safe';
        } else {
            if (value >= config.block) return 'block';
            if (value >= config.caution) return 'caution';
            return 'safe';
        }
    }
    
    // Get color based on status
    function getStatusColor(status) {
        switch(status) {
            case 'safe': return '#27ae60';
            case 'caution': return '#f39c12';
            case 'block': return '#e74c3c';
            default: return '#95a5a6';
        }
    }
    
    // Format value with proper decimals
    function formatValue(value, gasType) {
        if (value === undefined || value === null) return '--';
        
        if (gasType === 'o2') {
            return value.toFixed(1);
        }
        return value.toFixed(1);
    }
    
    // Render a single gas gauge
    function renderGauge(gasType, value, options = {}) {
        const config = GAS_CONFIG[gasType];
        if (!config) return '<div>Invalid gas type</div>';
        
        const {
            size = 'medium',
            showLabel = true,
            showValue = true,
            showUnit = true,
            animated = true,
            thresholds = config.thresholds
        } = options;
        
        const status = getGasStatus(gasType, value);
        const color = getStatusColor(status);
        const percentage = ((value - config.min) / (config.max - config.min)) * 100;
        const clampedPercentage = Math.min(100, Math.max(0, percentage));
        
        // Size classes
        const sizeClass = {
            small: 'gauge-small',
            medium: 'gauge-medium',
            large: 'gauge-large'
        }[size] || 'gauge-medium';
        
        // SVG Arc calculation
        const radius = 80;
        const circumference = 2 * Math.PI * radius;
        const offset = circumference - (clampedPercentage / 100) * circumference;
        
        return `
            <div class="gas-gauge ${sizeClass}" data-gas="${gasType}" data-status="${status}">
                <svg viewBox="0 0 200 200" class="gauge-svg">
                    <!-- Background circle -->
                    <circle
                        cx="100"
                        cy="100"
                        r="${radius}"
                        fill="none"
                        stroke="#34495e"
                        stroke-width="15"
                        stroke-linecap="round"
                    />
                    
                    <!-- Value arc -->
                    <circle
                        cx="100"
                        cy="100"
                        r="${radius}"
                        fill="none"
                        stroke="${color}"
                        stroke-width="15"
                        stroke-linecap="round"
                        stroke-dasharray="${circumference}"
                        stroke-dashoffset="${offset}"
                        transform="rotate(-90 100 100)"
                        class="${animated ? 'gauge-arc-animated' : ''}"
                    />
                    
                    <!-- Threshold markers -->
                    ${Object.entries(thresholds).map(([level, th]) => {
                        const thPercentage = ((th.min - config.min) / (config.max - config.min)) * 100;
                        const angle = (thPercentage / 100) * 360 - 90;
                        const rad = angle * (Math.PI / 180);
                        const x1 = 100 + (radius + 5) * Math.cos(rad);
                        const y1 = 100 + (radius + 5) * Math.sin(rad);
                        const x2 = 100 + (radius + 15) * Math.cos(rad);
                        const y2 = 100 + (radius + 15) * Math.sin(rad);
                        
                        return `
                            <line
                                x1="${x1}"
                                y1="${y1}"
                                x2="${x2}"
                                y2="${y2}"
                                stroke="${th.color}"
                                stroke-width="2"
                                stroke-dasharray="4 4"
                            />
                        `;
                    }).join('')}
                    
                    <!-- Center circle -->
                    <circle
                        cx="100"
                        cy="100"
                        r="35"
                        fill="rgba(0,0,0,0.5)"
                        stroke="#34495e"
                        stroke-width="2"
                    />
                    
                    <!-- Value text -->
                    ${showValue ? `
                        <text
                            x="100"
                            y="100"
                            text-anchor="middle"
                            dominant-baseline="middle"
                            fill="white"
                            font-size="24"
                            font-weight="bold"
                        >
                            ${formatValue(value, gasType)}
                        </text>
                    ` : ''}
                    
                    ${showUnit ? `
                        <text
                            x="100"
                            y="130"
                            text-anchor="middle"
                            fill="#95a5a6"
                            font-size="12"
                        >
                            ${config.unit}
                        </text>
                    ` : ''}
                </svg>
                
                ${showLabel ? `
                    <div class="gauge-label">
                        <span class="gas-name">${config.name}</span>
                        <span class="gas-desc">${config.description}</span>
                    </div>
                ` : ''}
                
                <div class="gauge-thresholds">
                    <span class="threshold safe">Safe: ≤${config.caution}${config.unit}</span>
                    <span class="threshold caution">Caution: ${config.caution}-${config.block}${config.unit}</span>
                    <span class="threshold block">Block: ≥${config.block}${config.unit}</span>
                </div>
            </div>
        `;
    }
    
    // Render a grid of gauges
    function renderGrid(readings = {}, options = {}) {
        const {
            columns = 2,
            gases = ['h2s', 'ch4', 'co', 'o2'],
            showAll = true,
            size = 'medium'
        } = options;
        
        const gridClass = `gauges-grid columns-${columns}`;
        
        return `
            <div class="${gridClass}">
                ${gases.map(gas => {
                    const value = readings[gas] !== undefined ? readings[gas] : 0;
                    return renderGauge(gas, value, { size, ...options });
                }).join('')}
            </div>
        `;
    }
    
    // Render a mini gauge for dashboard cards
    function renderMini(gasType, value, options = {}) {
        const config = GAS_CONFIG[gasType];
        if (!config) return '';
        
        const status = getGasStatus(gasType, value);
        const color = getStatusColor(status);
        
        return `
            <div class="gauge-mini" data-gas="${gasType}" data-status="${status}">
                <div class="gauge-mini-header">
                    <span class="gauge-mini-name">${config.name}</span>
                    <span class="gauge-mini-value" style="color: ${color}">
                        ${formatValue(value, gasType)} ${config.unit}
                    </span>
                </div>
                <div class="gauge-mini-bar">
                    <div class="gauge-mini-bar-fill" style="width: ${(value / config.max) * 100}%; background: ${color};"></div>
                </div>
                <div class="gauge-mini-status ${status}">
                    ${status.toUpperCase()}
                </div>
            </div>
        `;
    }
    
    // Render historical trend chart
    function renderTrend(gasType, history = [], options = {}) {
        const config = GAS_CONFIG[gasType];
        if (!config || history.length === 0) {
            return '<div>No data available</div>';
        }
        
        const width = options.width || 300;
        const height = options.height || 100;
        const padding = 20;
        
        const chartWidth = width - 2 * padding;
        const chartHeight = height - 2 * padding;
        
        // Find min/max for scaling
        const values = history.map(h => h.value);
        const minValue = Math.min(...values, config.min);
        const maxValue = Math.max(...values, config.max);
        const range = maxValue - minValue;
        
        // Generate path
        const points = history.map((h, i) => {
            const x = padding + (i / (history.length - 1)) * chartWidth;
            const y = padding + chartHeight - ((h.value - minValue) / range) * chartHeight;
            return `${x},${y}`;
        });
        
        const pathData = `M ${points.join(' L ')}`;
        
        return `
            <div class="gauge-trend">
                <svg width="${width}" height="${height}">
                    <!-- Grid lines -->
                    ${[0, 0.25, 0.5, 0.75, 1].map((p, i) => {
                        const y = padding + chartHeight * p;
                        return `
                            <line
                                x1="${padding}"
                                y1="${y}"
                                x2="${width - padding}"
                                y2="${y}"
                                stroke="#34495e"
                                stroke-width="1"
                                stroke-dasharray="4 4"
                            />
                            <text
                                x="${padding - 5}"
                                y="${y + 4}"
                                text-anchor="end"
                                fill="#95a5a6"
                                font-size="10"
                            >
                                ${(maxValue - range * p).toFixed(1)}
                            </text>
                        `;
                    }).join('')}
                    
                    <!-- Threshold lines -->
                    <line
                        x1="${padding}"
                        y1="${padding + chartHeight - ((config.block - minValue) / range) * chartHeight}"
                        x2="${width - padding}"
                        y2="${padding + chartHeight - ((config.block - minValue) / range) * chartHeight}"
                        stroke="#e74c3c"
                        stroke-width="1"
                        stroke-dasharray="2 2"
                    />
                    <line
                        x1="${padding}"
                        y1="${padding + chartHeight - ((config.caution - minValue) / range) * chartHeight}"
                        x2="${width - padding}"
                        y2="${padding + chartHeight - ((config.caution - minValue) / range) * chartHeight}"
                        stroke="#f39c12"
                        stroke-width="1"
                        stroke-dasharray="2 2"
                    />
                    
                    <!-- Data line -->
                    <path
                        d="${pathData}"
                        stroke="${config.color}"
                        stroke-width="2"
                        fill="none"
                    />
                    
                    <!-- Data points -->
                    ${history.map((h, i) => {
                        const x = padding + (i / (history.length - 1)) * chartWidth;
                        const y = padding + chartHeight - ((h.value - minValue) / range) * chartHeight;
                        const status = getGasStatus(gasType, h.value);
                        return `
                            <circle
                                cx="${x}"
                                cy="${y}"
                                r="3"
                                fill="${getStatusColor(status)}"
                            />
                        `;
                    }).join('')}
                </svg>
                <div class="trend-labels">
                    <span>${history[0].time || ''}</span>
                    <span>Now</span>
                </div>
            </div>
        `;
    }
    
    // Public API
    return {
        GAS_CONFIG,
        renderGauge,
        renderGrid,
        renderMini,
        renderTrend,
        getGasStatus,
        getStatusColor,
        formatValue
    };
})();

// Add CSS styles dynamically
const style = document.createElement('style');
style.textContent = `
    .gas-gauge {
        text-align: center;
        padding: 15px;
        background: rgba(255,255,255,0.05);
        border-radius: 12px;
        transition: all 0.3s ease;
    }
    
    .gas-gauge:hover {
        background: rgba(255,255,255,0.1);
        transform: translateY(-2px);
    }
    
    .gas-gauge[data-status="safe"] {
        box-shadow: 0 0 15px rgba(39, 174, 96, 0.2);
    }
    
    .gas-gauge[data-status="caution"] {
        box-shadow: 0 0 15px rgba(243, 156, 18, 0.2);
    }
    
    .gas-gauge[data-status="block"] {
        box-shadow: 0 0 15px rgba(231, 76, 60, 0.2);
        animation: pulse 2s infinite;
    }
    
    @keyframes pulse {
        0% { box-shadow: 0 0 15px rgba(231, 76, 60, 0.2); }
        50% { box-shadow: 0 0 25px rgba(231, 76, 60, 0.4); }
        100% { box-shadow: 0 0 15px rgba(231, 76, 60, 0.2); }
    }
    
    .gauge-svg {
        width: 100%;
        height: auto;
    }
    
    .gauge-arc-animated {
        transition: stroke-dashoffset 0.5s ease;
    }
    
    .gauge-label {
        margin-top: 10px;
    }
    
    .gas-name {
        display: block;
        font-size: 18px;
        font-weight: bold;
    }
    
    .gas-desc {
        display: block;
        font-size: 12px;
        color: #95a5a6;
    }
    
    .gauge-thresholds {
        margin-top: 10px;
        font-size: 11px;
        display: flex;
        justify-content: center;
        gap: 15px;
    }
    
    .threshold {
        padding: 2px 6px;
        border-radius: 3px;
    }
    
    .threshold.safe {
        background: rgba(39, 174, 96, 0.2);
        color: #27ae60;
    }
    
    .threshold.caution {
        background: rgba(243, 156, 18, 0.2);
        color: #f39c12;
    }
    
    .threshold.block {
        background: rgba(231, 76, 60, 0.2);
        color: #e74c3c;
    }
    
    .gauges-grid {
        display: grid;
        gap: 20px;
    }
    
    .gauges-grid.columns-2 {
        grid-template-columns: repeat(2, 1fr);
    }
    
    .gauges-grid.columns-4 {
        grid-template-columns: repeat(4, 1fr);
    }
    
    .gauge-mini {
        background: rgba(255,255,255,0.05);
        border-radius: 8px;
        padding: 10px;
        margin-bottom: 10px;
    }
    
    .gauge-mini-header {
        display: flex;
        justify-content: space-between;
        margin-bottom: 8px;
    }
    
    .gauge-mini-name {
        font-weight: 600;
    }
    
    .gauge-mini-bar {
        height: 4px;
        background: rgba(255,255,255,0.1);
        border-radius: 2px;
        overflow: hidden;
        margin-bottom: 5px;
    }
    
    .gauge-mini-bar-fill {
        height: 100%;
        transition: width 0.3s ease;
    }
    
    .gauge-mini-status {
        font-size: 10px;
        text-align: right;
        text-transform: uppercase;
    }
    
    .gauge-mini-status.safe { color: #27ae60; }
    .gauge-mini-status.caution { color: #f39c12; }
    .gauge-mini-status.block { color: #e74c3c; }
    
    .gauge-trend {
        background: rgba(255,255,255,0.05);
        border-radius: 8px;
        padding: 15px;
    }
    
    .trend-labels {
        display: flex;
        justify-content: space-between;
        margin-top: 5px;
        font-size: 11px;
        color: #95a5a6;
    }
    
    @media (max-width: 768px) {
        .gauges-grid.columns-4 {
            grid-template-columns: repeat(2, 1fr);
        }
    }
`;

document.head.appendChild(style);

console.log('✅ GasGauges component loaded');