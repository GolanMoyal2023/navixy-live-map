// Local & External: unified data - both maps use same merged endpoint (Navixy + broker)
// Port 8765 = server.py with BROKER_MERGE (ngrok exposes this for external)
window.NAVIXY_MAP_API_BASE = "http://127.0.0.1:8765";
// Public: ngrok URL - updated by start_ngrok_tunnel.ps1 -Push (no Cloudflare)
window.NAVIXY_MAP_API_BASE_PUBLIC = "https://absently-dispensible-chanel.ngrok-free.dev";
