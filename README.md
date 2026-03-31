# Waigyard Panel (Vol WG)
Simple web panel for WireGuard management (based on wg-easy).

## Features
- One-click installation
- Secure admin password setup on first login
- Client management (Add/Delete/Toggle)
- QR Code for easy mobile setup
- Config file download
- Real-time connection status

## Quick Start
Run this command on your server (Ubuntu 20.04+):
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/robertmiro14-netizen/wg-panel/main/install_wg_panel.sh)
```

## Management
The panel runs on port 51821 by default.
- Panel logs: journalctl -u vol-panel -f
- WireGuard logs: docker logs -f wg-easy

---
Based on wg-easy.
