# WireGuard VPN + Web Panel

Automatic installer for WireGuard VPN with web control panel for Ubuntu 20.04 / 22.04 / 24.04.

## Features

- First run - set password directly in browser
- - Client management - create and delete VPN users
  - - QR code - scan in WireGuard app (iOS/Android)
    - - Download config - ready-to-use .conf file for any device
      - - Dashboard - server status, load, memory, uptime
        - - WireGuard status - real-time wg show output
          - - Restart WireGuard with one button
           
            - ## Installation
           
            - ### 1. Connect to server
           
            - ```bash
              ssh root@your-server-ip
              ```

              ### 2. Download and run script

              ```bash
              curl -O https://raw.githubusercontent.com/robertmiro14-netizen/wg-panel/main/install_wg_panel.sh
              sudo bash install_wg_panel.sh
              ```

              > The script will automatically:
              > > - Install WireGuard and all dependencies
              > > - > - Install Node.js 20 LTS (if needed)
              > >   > - > - Create server keys
              > >   >   > - > - Run WireGuard and web panel as services
              > >   >   >   > - > - Configure UFW (ports 51820/udp and 8080/tcp)
              > >   >   >   >   >
              > >   >   >   >   > - ### 3. Open panel in browser
              > >   >   >   >   >
              > >   >   >   >   > - After installation, open:
              > >   >   >   >   >
              > >   >   >   >   > - ```
              > >   >   >   >   >   http://YOUR_SERVER_IP:8080
              > >   >   >   >   >   ```
              > >   >   >   >   >
              > >   >   >   >   > On first login, you will be prompted to set a password (min 6 characters).
              > >   >   >   >   >
              > >   >   >   >   > ---
              > >   >   >   >   >
              > >   >   >   >   > ## How to add a client (VPN user)
              > >   >   >   >   >
              > >   >   >   >   > 1. Log in to panel -> Clients -> + Add client
              > >   >   >   >   > 2. 2. Enter name (e.g., phone, laptop, office)
              > >   >   >   >   >    3. 3. Click Create client
              > >   >   >   >   >       4. 4. Scan QR code in WireGuard app or download .conf file
              > >   >   >   >   >         
              > >   >   >   >   >          5. ### WireGuard Apps:
              > >   >   >   >   >          6. | Platform | Link |
              > >   >   >   >   >          7. |-----------|--------|
              > >   >   >   >   >          8. | iOS | [App Store](https://apps.apple.com/app/wireguard/id1441195209) |
              > >   >   >   >   >          9. | Android | [Google Play](https://play.google.com/store/apps/details?id=com.wireguard.android) |
              > >   >   >   >   >          10. | Windows | [Download](https://www.wireguard.com/install/) |
              > >   >   >   >   >          11. | macOS | [App Store](https://apps.apple.com/app/wireguard/id1451685025) |
              > >   >   >   >   >          12. | Linux | sudo apt install wireguard |
              > >   >   >   >   >         
              > >   >   >   >   >          13. ---
              > >   >   >   >   >         
              > >   >   >   >   >          14. ## Technical Details
              > >   >   >   >   > 
              | Parameter | Value |
              |----------|----------|
              | WireGuard port | 51820/udp |
              | Web panel port | 51821/tcp |
              | VPN subnet | 10.8.0.0/24 |
              | DNS | 1.1.1.1, 8.8.8.8 |
              | wg-easy data | /opt/wg-easy/ |

              ---

              ## Management

              ```bash
              # Status
              docker ps

              # Real-time logs
              docker logs -f wg-easy

              # Restart
              docker restart wg-easy

              # Update
              docker pull ghcr.io/wg-easy/wg-easy && docker restart wg-easy
              ```

              ---

              ## Password Reset

              If you forgot your password, recreate the container with a new one:

              ```bash
              docker stop wg-easy
              docker rm wg-easy
              sudo bash install_wg_panel.sh
              ```

              ---

              ## Screenshots

              | First setup | Dashboard | Clients | QR Code |
              |:---:|:---:|:---:|:---:|
              | Set password | Server stats | User list | Scanning in WG |

              ---

              ## Requirements

              - Ubuntu 20.04 / 22.04 / 24.04
              - - root access (or sudo)
                - - Open ports: 51820/udp and 51821/tcp
                  - - Min 512 MB RAM
                    - 
