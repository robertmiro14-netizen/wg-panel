# WireGuard VPN + Web Panel

Automatic WireGuard VPN installer with web management panel for Ubuntu 20.04 / 22.04 / 24.04.

## Features

- First launch: set your password directly in the browser
- - Client management: create and delete VPN users
  - - QR code: scan in the WireGuard app (iOS/Android)
    - - Download config: ready .conf file for any device
      - - Dashboard: server status, load, memory, uptime
        - - WireGuard status: live wg show output
          - - One-click WireGuard restart
           
            - ## Installation
           
            - ### 1. Connect to your server
           
            - ```bash
              ssh root@your-server-ip
              ```

              ### 2. Download and run the script

              ```bash
              curl -O https://raw.githubusercontent.com/robertmiro14-netizen/wg-panel/main/install_wg_panel.sh
              sudo bash install_wg_panel.sh
              ```

              The script will automatically:
              - Install Docker (if not present)
              - - Enable IP forwarding
                - - Configure UFW firewall
                  - - Launch wg-easy as a Docker container
                   
                    - ### 3. Open the panel in your browser
                   
                    - After installation, open:
                   
                    - ```
                      http://YOUR_SERVER_IP:51821
                      ```

                      Enter the password you set during installation.

                      ---

                      ## How to add a VPN client

                      1. Log into the panel -> Clients -> + Add Client
                      2. 2. Enter a name (e.g.: phone, laptop, office)
                         3. 3. Click Create Client
                            4. 4. Scan the QR code in the WireGuard app OR download the .conf file
                              
                               5. ### WireGuard apps:
                               6. | Platform | Link |
                               7. |----------|------|
                               8. | iOS | App Store |
                               9. | Android | Google Play |
                               10. | Windows | wireguard.com/install |
                               11. | macOS | App Store |
                               12. | Linux | sudo apt install wireguard |
                              
                               13. ---
                              
                               14. ## Technical Details
                              
                               15. | Parameter | Value |
                               16. |-----------|-------|
                               17. | WireGuard port | 51820/udp |
                               18. | Web panel port | 51821/tcp |
                               19. | VPN subnet | 10.8.0.0/24 |
                               20. | DNS | 1.1.1.1, 8.8.8.8 |
                               21. | Data location | /opt/wg-easy/ |
                              
                               22. ---
                              
                               23. ## Management
                              
                               24. ```bash
                                   # Status
                                   docker ps

                                   # Live logs
                                   docker logs -f wg-easy

                                   # Restart
                                   docker restart wg-easy

                                   # Update
                                   docker pull ghcr.io/wg-easy/wg-easy && docker restart wg-easy
                                   ```

                                   ---

                                   ## Reset Password

                                   If you forgot your password, recreate the container with a new password:

                                   ```bash
                                   docker stop wg-easy
                                   docker rm wg-easy
                                   sudo bash install_wg_panel.sh
                                   ```

                                   ---

                                   ## Requirements

                                   - Ubuntu 20.04 / 22.04 / 24.04
                                   - - Root access (or sudo)
                                     - - Open ports: 51820/udp and 51821/tcp
                                       - - Minimum 512 MB RAM
                                         - 
