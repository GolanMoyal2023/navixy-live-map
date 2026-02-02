#!/usr/bin/env python3
"""
Navixy Live Map - Dashboard & Debug Interface
Provides real-time status monitoring for all system components.
"""

import os
import time
import subprocess
import requests
from datetime import datetime
from typing import Dict, Any, Optional
from flask import Flask, jsonify, render_template

# Use absolute paths for templates/static (important when run as service)
_base_dir = os.path.dirname(os.path.abspath(__file__))
app = Flask(__name__, 
            template_folder=os.path.join(_base_dir, 'dashboard', 'templates'),
            static_folder=os.path.join(_base_dir, 'dashboard', 'static'))

# Configuration
DASHBOARD_PORT = int(os.environ.get("DASHBOARD_PORT", "8766"))
API_PORT = int(os.environ.get("PORT", "8765"))
API_URL = f"http://127.0.0.1:{API_PORT}"
GITHUB_PAGES_URL = "https://golanmoyal2023.github.io/navixy-live-map/"

# Status cache (2 seconds)
_status_cache: Dict[str, Any] = {}
_cache_timestamp = 0
CACHE_DURATION = 2


def get_tunnel_url() -> Optional[str]:
    """Get current tunnel URL from file."""
    try:
        url_file = os.path.join(os.path.dirname(__file__), ".quick_tunnel_url.txt")
        if os.path.exists(url_file):
            with open(url_file, 'r', encoding='utf-8-sig') as f:  # Handle BOM
                url = f.read().strip()
                # Ensure URL starts with http
                if url and url.startswith('http'):
                    return url
    except Exception:
        pass
    return None


def check_service_status(service_name: str) -> Dict[str, Any]:
    """Check Windows service status."""
    try:
        result = subprocess.run(
            ["sc", "query", service_name],
            capture_output=True,
            text=True,
            timeout=5
        )
        output = result.stdout.lower()
        
        if "running" in output:
            return {"status": "running", "healthy": True}
        elif "stopped" in output:
            return {"status": "stopped", "healthy": False}
        else:
            return {"status": "unknown", "healthy": False}
    except Exception as e:
        return {"status": "error", "healthy": False, "error": str(e)}


def check_tunnel_url(url: str) -> Dict[str, Any]:
    """Check if tunnel URL is accessible."""
    try:
        response = requests.get(url, timeout=10)
        return {
            "status": "accessible",
            "healthy": response.status_code == 200,
            "status_code": response.status_code,
            "response_time": response.elapsed.total_seconds()
        }
    except Exception as e:
        return {
            "status": "inaccessible",
            "healthy": False,
            "error": str(e)
        }


def check_github_pages() -> Dict[str, Any]:
    """Check GitHub Pages accessibility."""
    try:
        response = requests.get(GITHUB_PAGES_URL, timeout=10)
        return {
            "status": "accessible" if response.status_code == 200 else "error",
            "healthy": response.status_code == 200,
            "status_code": response.status_code
        }
    except Exception as e:
        return {
            "status": "inaccessible",
            "healthy": False,
            "error": str(e)
        }


def check_local_api() -> Dict[str, Any]:
    """Check local API server."""
    try:
        response = requests.get(f"{API_URL}/health", timeout=5)
        return {
            "status": "running",
            "healthy": response.status_code == 200,
            "status_code": response.status_code
        }
    except Exception as e:
        return {
            "status": "down",
            "healthy": False,
            "error": str(e)
        }


def check_navixy_api() -> Dict[str, Any]:
    """Check Navixy API connectivity."""
    try:
        response = requests.get(f"{API_URL}/data", timeout=10)
        if response.status_code == 200:
            data = response.json()
            return {
                "status": "connected",
                "healthy": True,
                "trackers_count": len(data.get("rows", [])),
                "last_update": datetime.now().isoformat()
            }
        else:
            return {
                "status": "error",
                "healthy": False,
                "status_code": response.status_code
            }
    except Exception as e:
        return {
            "status": "disconnected",
            "healthy": False,
            "error": str(e)
        }


def get_system_status() -> Dict[str, Any]:
    """Get complete system status for all 11 components."""
    global _status_cache, _cache_timestamp
    
    # Use cache if recent
    if time.time() - _cache_timestamp < CACHE_DURATION:
        return _status_cache
    
    tunnel_url = get_tunnel_url()
    
    # Check all components
    status = {
        "timestamp": datetime.now().isoformat(),
        "components": {
            "1_external_users": {
                "name": "External Users",
                "description": "User access to system",
                "status": "active",  # Always active if system is running
                "healthy": True
            },
            "2_github_pages": check_github_pages(),
            "3_cloudflare_tunnel": {
                "name": "Cloudflare Quick Tunnel",
                "status": "connected" if tunnel_url else "disconnected",
                "healthy": tunnel_url is not None,
                "url": tunnel_url
            },
            "4_service_tunnel": check_service_status("NavixyQuickTunnel"),
            "5_service_api": check_service_status("NavixyApi"),
            "6_navixy_api": check_navixy_api(),
            "7_data_flow": {
                "name": "Data Flow",
                "status": "flowing",
                "healthy": True  # Will be determined by other checks
            },
            "8_tunnel_url": check_tunnel_url(tunnel_url) if tunnel_url else {
                "status": "no_url",
                "healthy": False
            },
            "9_api_response": check_local_api(),
            "10_service_health": {
                "name": "Service Health",
                "status": "healthy",
                "healthy": True
            },
            "11_system_status": {
                "name": "Overall System",
                "status": "operational",
                "healthy": True
            }
        }
    }
    
    # Update component names
    status["components"]["2_github_pages"]["name"] = "GitHub Pages"
    status["components"]["3_cloudflare_tunnel"]["name"] = "Cloudflare Quick Tunnel"
    status["components"]["4_service_tunnel"]["name"] = "Service: NavixyQuickTunnel"
    status["components"]["5_service_api"]["name"] = "Service: NavixyApi"
    status["components"]["6_navixy_api"]["name"] = "Navixy API Connection"
    status["components"]["7_data_flow"]["name"] = "Data Flow Status"
    status["components"]["8_tunnel_url"]["name"] = "Tunnel URL Status"
    status["components"]["9_api_response"]["name"] = "API Response Status"
    status["components"]["10_service_health"]["name"] = "Service Health"
    status["components"]["11_system_status"]["name"] = "Overall System Status"
    
    # Calculate overall health with CRITICAL components
    # Tunnel URL is CRITICAL - if down, external access is completely broken
    critical_components = ["8_tunnel_url", "5_service_api", "4_service_tunnel"]
    critical_healthy = all(
        status["components"].get(comp, {}).get("healthy", False) 
        for comp in critical_components
    )
    
    # Count healthy components
    healthy_count = sum(1 for comp in status["components"].values() if comp.get("healthy", False))
    total_count = len(status["components"])
    
    # If ANY critical component is down, system is CRITICAL (not just degraded)
    if not critical_healthy:
        status["components"]["11_system_status"]["healthy"] = False
        status["components"]["11_system_status"]["status"] = "critical"
        status["overall_health"] = False
        # If tunnel is down, health is 0% because external access is broken
        tunnel_healthy = status["components"].get("8_tunnel_url", {}).get("healthy", False)
        if not tunnel_healthy:
            status["health_percentage"] = 0
            status["critical_failure"] = "Tunnel URL inaccessible - external access broken!"
        else:
            status["health_percentage"] = int((healthy_count / total_count) * 100)
    else:
        status["components"]["11_system_status"]["healthy"] = healthy_count == total_count
        status["components"]["11_system_status"]["status"] = "operational" if healthy_count == total_count else "degraded"
        status["overall_health"] = healthy_count == total_count
        status["health_percentage"] = int((healthy_count / total_count) * 100)
    
    # Cache result
    _status_cache = status
    _cache_timestamp = time.time()
    
    return status


@app.route('/')
def dashboard():
    """Dashboard main page."""
    return render_template('dashboard.html')


@app.route('/api/status')
def api_status():
    """API endpoint for system status."""
    return jsonify(get_system_status())


@app.route('/api/restart/<service_name>')
def api_restart(service_name: str):
    """Restart a Windows service."""
    try:
        if service_name in ["NavixyApi", "NavixyQuickTunnel", "NavixyDashboard"]:
            subprocess.run(["sc", "stop", service_name], timeout=10)
            time.sleep(2)
            subprocess.run(["sc", "start", service_name], timeout=10)
            return jsonify({"success": True, "message": f"Service {service_name} restarted"})
        else:
            return jsonify({"success": False, "message": "Invalid service name"}), 400
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@app.route('/api/system-reset')
def api_system_reset():
    """Restart ALL 4 services (simulates system restart)."""
    try:
        services = ["NavixyUrlSync", "NavixyDashboard", "NavixyQuickTunnel", "NavixyApi"]
        boot_order = ["NavixyApi", "NavixyQuickTunnel", "NavixyDashboard", "NavixyUrlSync"]
        
        # Stop all services (reverse order)
        for svc in services:
            try:
                subprocess.run(["sc", "stop", svc], timeout=10, capture_output=True)
            except:
                pass
        
        time.sleep(3)
        
        # Start all services (boot order)
        for svc in boot_order:
            try:
                subprocess.run(["sc", "start", svc], timeout=10, capture_output=True)
                time.sleep(1)
            except:
                pass
        
        return jsonify({
            "success": True, 
            "message": "All 4 services restarted. URL sync will update GitHub automatically."
        })
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


if __name__ == '__main__':
    print(f"Starting Dashboard on http://127.0.0.1:{DASHBOARD_PORT}")
    app.run(host='127.0.0.1', port=DASHBOARD_PORT, debug=False)
