#!/bin/bash
# ============================================================
#  VOL WG -- WireGuard + wg-easy (automatic install)
#  Supports Ubuntu 20.04 / 22.04 / 24.04
#  Run: sudo bash install_wg_panel.sh
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root (sudo bash $0)"
command -v apt >/dev/null 2>&1 || error "Only Debian/Ubuntu is supported"

echo -e "${BOLD}${CYAN}"
echo "  VOL WG -- WireGuard VPN + Web Panel"
echo "  =====================================  "
echo -e "${NC}"

SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || \
            curl -s --max-time 5 https://ifconfig.me  || \
                        hostname -I | awk '{print $1}')
                        info "Server public IP: ${BOLD}${SERVER_IP}${NC}"

                        WG_PORT=51820
                        WEB_PORT=51821

                        PANEL_PASS=""
                        echo ""
                        while [[ -z "$PANEL_PASS" ]]; do
                            read -rsp "  Create a password for the web panel: " PANEL_PASS
                                echo ""
                                    if [[ ${#PANEL_PASS} -lt 6 ]]; then
                                            warn "Password must be at least 6 characters"
                                                    PANEL_PASS=""
                                                        fi
                                                        done
                                                        success "Password set"
                                                        echo ""

                                                        info "Updating packages..."
                                                        apt update -qq
                                                        apt install -y -qq curl ufw iptables 2>/dev/null || true

                                                        if ! command -v docker >/dev/null 2>&1; then
                                                            info "Installing Docker..."
                                                                curl -fsSL https://get.docker.com | sh
                                                                    systemctl enable docker
                                                                        systemctl start docker
                                                                            success "Docker installed: $(docker --version | cut -d' ' -f3 | tr -d ',')"
                                                                            else
                                                                                success "Docker already installed: $(docker --version | cut -d' ' -f3 | tr -d ',')"
                                                                                fi

                                                                                info "Enabling IP forwarding..."
                                                                                sysctl -w net.ipv4.ip_forward=1 >/dev/null
                                                                                grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
                                                                                    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
                                                                                    success "IP forwarding enabled"

                                                                                    info "Configuring UFW..."
                                                                                    ufw allow 22/tcp          >/dev/null 2>&1 || true
                                                                                    ufw allow ${WG_PORT}/udp  >/dev/null 2>&1 || true
                                                                                    ufw allow ${WEB_PORT}/tcp >/dev/null 2>&1 || true
                                                                                    ufw --force enable        >/dev/null 2>&1 || true
                                                                                    success "Ports opened: 22/tcp, ${WG_PORT}/udp, ${WEB_PORT}/tcp"

                                                                                    mkdir -p /opt/wg-easy
                                                                                    chmod 700 /opt/wg-easy

                                                                                    info "Starting wg-easy..."

                                                                                    docker stop wg-easy 2>/dev/null || true
                                                                                    docker rm   wg-easy 2>/dev/null || true

                                                                                    docker run -d \
                                                                                      --name=wg-easy \
                                                                                        -e LANG=en \
                                                                                          -e WG_HOST="${SERVER_IP}" \
                                                                                            -e PASSWORD="${PANEL_PASS}" \
                                                                                              -e WG_PORT=${WG_PORT} \
                                                                                                -e WG_DEFAULT_DNS="1.1.1.1, 8.8.8.8" \
                                                                                                  -e WG_MTU=1420 \
                                                                                                    -e WG_PERSISTENT_KEEPALIVE=25 \
                                                                                                      -e WG_DEFAULT_ADDRESS="10.8.0.x" \
                                                                                                        -e UI_TRAFFIC_STATS=true \
                                                                                                          -e UI_CHART_TYPE=1 \
                                                                                                            -v /opt/wg-easy:/etc/wireguard \
                                                                                                              -p ${WG_PORT}:${WG_PORT}/udp \
                                                                                                                -p ${WEB_PORT}:${WEB_PORT}/tcp \
                                                                                                                  --cap-add=NET_ADMIN \
                                                                                                                    --cap-add=SYS_MODULE \
                                                                                                                      --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
                                                                                                                        --sysctl="net.ipv6.conf.all.disable_ipv6=1" \
                                                                                                                          --restart unless-stopped \
                                                                                                                            ghcr.io/wg-easy/wg-easy
                                                                                                                            
                                                                                                                            sleep 3
                                                                                                                            
                                                                                                                            CONTAINER_ST=$(docker inspect -f '{{.State.Running}}' wg-easy 2>/dev/null || echo "false")
                                                                                                                            
                                                                                                                            echo ""
                                                                                                                            echo -e "${BOLD}${GREEN}============================================${NC}"
                                                                                                                            echo -e "${BOLD}${GREEN}      VOL WG -- INSTALLATION COMPLETE      ${NC}"
                                                                                                                            echo -e "${BOLD}${GREEN}============================================${NC}"
                                                                                                                            echo ""
                                                                                                                            if [[ "$CONTAINER_ST" == "true" ]]; then
                                                                                                                                echo -e "  Panel status:    ${GREEN}Running${NC}"
                                                                                                                                else
                                                                                                                                    echo -e "  Panel status:    ${RED}Error starting${NC}"
                                                                                                                                        echo -e "  Logs: docker logs wg-easy"
                                                                                                                                        fi
                                                                                                                                        echo ""
                                                                                                                                        echo -e "  Web panel:       http://${SERVER_IP}:${WEB_PORT}"
                                                                                                                                        echo -e "  Password:        ${PANEL_PASS}"
                                                                                                                                        echo -e "  WireGuard port:  ${WG_PORT}/udp"
                                                                                                                                        echo ""
                                                                                                                                        echo -e "  Logs:      docker logs -f wg-easy"
                                                                                                                                        echo -e "  Restart:   docker restart wg-easy"
                                                                                                                                        echo -e "  Update:    docker pull ghcr.io/wg-easy/wg-easy && docker restart wg-easy"
                                                                                                                                        echo ""
                                                                                                                                        echo -e "  Open in browser: http://${SERVER_IP}:${WEB_PORT}"
                                                                                                                                        echo ""
                                                                                                                                        
