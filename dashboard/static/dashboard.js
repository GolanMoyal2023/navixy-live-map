// Dashboard JavaScript
let refreshInterval;

// Component names mapping
const componentNames = {
    '1_external_users': 'External Users',
    '2_github_pages': 'GitHub Pages',
    '3_cloudflare_tunnel': 'Cloudflare Quick Tunnel',
    '4_service_tunnel': 'Service: NavixyQuickTunnel',
    '5_service_api': 'Service: NavixyApi',
    '6_navixy_api': 'Navixy API Connection',
    '7_data_flow': 'Data Flow Status',
    '8_tunnel_url': 'Tunnel URL Status',
    '9_api_response': 'API Response Status',
    '10_service_health': 'Service Health',
    '11_system_status': 'Overall System Status'
};

function getStatusClass(status, healthy) {
    if (healthy === true) return 'status-healthy';
    if (healthy === false) return 'status-error';
    if (status === 'warning' || status === 'degraded') return 'status-warning';
    return 'status-unknown';
}

function getStatusText(status, healthy) {
    if (healthy === true) return 'Healthy';
    if (healthy === false) return 'Error';
    if (status === 'warning' || status === 'degraded') return 'Warning';
    return 'Unknown';
}

function formatTimestamp(timestamp) {
    if (!timestamp) return '--';
    const date = new Date(timestamp);
    return date.toLocaleTimeString();
}

function updateDashboard() {
    fetch('/api/status')
        .then(response => response.json())
        .then(data => {
            updateOverallHealth(data);
            updateComponents(data.components);
            updateLastUpdate(data.timestamp);
            updateTunnelUrl(data.components['3_cloudflare_tunnel']);
        })
        .catch(error => {
            console.error('Error fetching status:', error);
            document.getElementById('overallHealth').innerHTML = 
                '<span class="health-icon">❌</span><span class="health-text">Error loading status</span>';
        });
}

function updateOverallHealth(data) {
    const healthIndicator = document.getElementById('overallHealth');
    const healthPercentage = document.getElementById('healthPercentage');
    
    const isHealthy = data.overall_health;
    const percentage = data.health_percentage || 0;
    const systemStatus = data.components?.['11_system_status']?.status || 'unknown';
    const criticalFailure = data.critical_failure;
    
    healthPercentage.textContent = `${percentage}% Healthy`;
    
    if (isHealthy) {
        healthIndicator.innerHTML = 
            '<span class="health-icon">✅</span><span class="health-text">System Operational</span>';
        healthIndicator.style.color = '#10b981';
        healthPercentage.style.color = '#10b981';
    } else if (systemStatus === 'critical' || percentage === 0) {
        // CRITICAL - show in RED
        healthIndicator.innerHTML = 
            '<span class="health-icon">🚨</span><span class="health-text">CRITICAL FAILURE</span>';
        healthIndicator.style.color = '#ef4444';
        healthPercentage.style.color = '#ef4444';
        if (criticalFailure) {
            healthIndicator.innerHTML += `<br><span class="critical-message" style="font-size: 0.8em; color: #ef4444;">${criticalFailure}</span>`;
        }
    } else {
        // Degraded - show in yellow
        healthIndicator.innerHTML = 
            '<span class="health-icon">⚠️</span><span class="health-text">System Degraded</span>';
        healthIndicator.style.color = '#f59e0b';
        healthPercentage.style.color = '#f59e0b';
    }
}

function updateComponents(components) {
    const grid = document.getElementById('componentsGrid');
    grid.innerHTML = '';
    
    // Sort components by key to maintain order
    const sortedKeys = Object.keys(components).sort();
    
    sortedKeys.forEach(key => {
        const component = components[key];
        const card = createComponentCard(key, component);
        grid.appendChild(card);
    });
}

function createComponentCard(key, component) {
    const card = document.createElement('div');
    card.className = 'component-card';
    
    const name = component.name || componentNames[key] || key;
    const status = component.status || 'unknown';
    const healthy = component.healthy !== undefined ? component.healthy : false;
    const description = component.description || '';
    
    const statusClass = getStatusClass(status, healthy);
    const statusText = getStatusText(status, healthy);
    
    card.innerHTML = `
        <div class="component-header">
            <div class="component-name">${name}</div>
            <div class="component-status ${statusClass}">${statusText}</div>
        </div>
        ${description ? `<div class="component-description">${description}</div>` : ''}
        <div class="component-details">
            Status: ${status}<br>
            ${component.url ? `URL: ${component.url}<br>` : ''}
            ${component.status_code ? `HTTP: ${component.status_code}<br>` : ''}
            ${component.error ? `Error: ${component.error}<br>` : ''}
            ${component.trackers_count !== undefined ? `Trackers: ${component.trackers_count}<br>` : ''}
        </div>
    `;
    
    return card;
}

function updateLastUpdate(timestamp) {
    const lastUpdate = document.getElementById('lastUpdate');
    lastUpdate.textContent = `Last update: ${formatTimestamp(timestamp)}`;
}

function updateTunnelUrl(tunnelComponent) {
    const tunnelUrlElement = document.getElementById('tunnelUrl');
    const liveDataLink = document.getElementById('liveDataLink');
    
    if (tunnelComponent && tunnelComponent.url) {
        tunnelUrlElement.textContent = tunnelComponent.url;
        // Update the Live Data quick link
        if (liveDataLink) {
            liveDataLink.href = tunnelComponent.url;
        }
    } else {
        tunnelUrlElement.textContent = 'Not available';
        if (liveDataLink) {
            liveDataLink.href = '#';
        }
    }
}

function restartService(serviceName) {
    if (!confirm(`Are you sure you want to restart ${serviceName}?`)) {
        return;
    }
    
    const btn = event.target;
    btn.disabled = true;
    btn.textContent = 'Restarting...';
    
    fetch(`/api/restart/${serviceName}`)
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                alert(`${serviceName} restarted successfully`);
                setTimeout(() => updateDashboard(), 2000);
            } else {
                alert(`Error: ${data.message}`);
            }
        })
        .catch(error => {
            alert(`Error restarting service: ${error.message}`);
        })
        .finally(() => {
            btn.disabled = false;
            btn.textContent = `🔄 Restart ${serviceName.replace('Navixy', '')}`;
        });
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    // Initial load
    updateDashboard();
    
    // Set up auto-refresh (every 5 seconds)
    refreshInterval = setInterval(updateDashboard, 5000);
    
    // Manual refresh button
    document.getElementById('refreshBtn').addEventListener('click', () => {
        updateDashboard();
    });
});

function systemReset() {
    if (!confirm('This will restart ALL 4 services (API, Tunnel, Dashboard, URL Sync).\n\nThe dashboard will reload after reset.\n\nContinue?')) {
        return;
    }
    
    const btn = document.getElementById('systemResetBtn');
    btn.disabled = true;
    btn.innerHTML = '⏳ Resetting...';
    
    fetch('/api/system-reset')
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                btn.innerHTML = '✅ Restarting...';
                // Wait for services to restart, then reload
                setTimeout(() => {
                    window.location.reload();
                }, 8000);
            } else {
                alert(`Error: ${data.message}`);
                btn.disabled = false;
                btn.innerHTML = '🔄 System Reset';
            }
        })
        .catch(error => {
            alert(`Error: ${error.message}`);
            btn.disabled = false;
            btn.innerHTML = '🔄 System Reset';
        });
}

// Make functions available globally
window.restartService = restartService;
window.systemReset = systemReset;