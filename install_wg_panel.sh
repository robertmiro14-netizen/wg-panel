#!/bin/bash
# ============================================================
#  VOL WG — WireGuard + wg-easy (автоматическая установка)
#  Поддерживает Ubuntu 20.04 / 22.04 / 24.04
#  Запуск: sudo bash install_wg_panel.sh
# ============================================================
set -e

# ─── Цвета ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# ─── Проверки ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Запускайте от root (sudo bash $0)"
command -v apt >/dev/null 2>&1 || error "Поддерживается только Debian/Ubuntu"

echo -e "${BOLD}${CYAN}"
echo "  ██╗   ██╗ ██████╗ ██╗         ██╗    ██╗  ██████╗ "
echo "  ██║   ██║██╔═══██╗██║         ██║    ██║ ██╔════╝ "
echo "  ██║   ██║██║   ██║██║         ██║ █╗ ██║ ██║  ███╗"
echo "  ╚██╗ ██╔╝██║   ██║██║         ██║███╗██║ ██║   ██║"
echo "   ╚████╔╝ ╚██████╔╝███████╗    ╚███╔███╔╝ ╚██████╔╝"
echo "    ╚═══╝   ╚═════╝ ╚══════╝     ╚══╝╚══╝   ╚═════╝ "
echo -e "${NC}"
echo -e "${BOLD}  VOL WG — WireGuard VPN + Web Panel${NC}"
echo "  ─────────────────────────────────────"

# ─── Определение публичного IP ──────────────────────────────
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || \
            curl -s --max-time 5 https://ifconfig.me  || \
            hostname -I | awk '{print $1}')
info "Публичный IP сервера: ${BOLD}${SERVER_IP}${NC}"

# ─── Порты ──────────────────────────────────────────────────
WG_PORT=51820    # WireGuard UDP
WEB_PORT=51821   # Веб-панель

# ─── Запрос пароля ──────────────────────────────────────────
PANEL_PASS=""
echo ""
while [[ -z "$PANEL_PASS" ]]; do
    read -rsp "  Придумайте пароль для веб-панели: " PANEL_PASS
    echo ""
    if [[ ${#PANEL_PASS} -lt 6 ]]; then
        warn "Пароль должен быть минимум 6 символов"
        PANEL_PASS=""
    fi
done
success "Пароль установлен"
echo ""

# ─── 1. Обновление системы ──────────────────────────────────
info "Обновление пакетов..."
apt update -qq
apt install -y -qq curl ufw iptables 2>/dev/null || true

# ─── 2. Установка Docker ────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    info "Установка Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    success "Docker установлен: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
    success "Docker уже установлен: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

# ─── 3. Включение IP forwarding ─────────────────────────────
info "Включение IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
success "IP forwarding включён"

# ─── 4. Настройка UFW ───────────────────────────────────────
info "Настройка UFW..."
ufw allow 22/tcp          >/dev/null 2>&1 || true
ufw allow ${WG_PORT}/udp  >/dev/null 2>&1 || true
ufw allow ${WEB_PORT}/tcp >/dev/null 2>&1 || true
ufw --force enable        >/dev/null 2>&1 || true
success "Порты открыты: 22/tcp, ${WG_PORT}/udp, ${WEB_PORT}/tcp"

# ─── 5. Директория данных ───────────────────────────────────
mkdir -p /opt/wg-easy
chmod 700 /opt/wg-easy

# ─── 6. Запуск wg-easy ──────────────────────────────────────
info "Запуск wg-easy..."

# Остановить и удалить старый контейнер если есть
docker stop wg-easy 2>/dev/null || true
docker rm   wg-easy 2>/dev/null || true

docker run -d \
  --name=wg-easy \
  -e LANG=ru \
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

# ─── 7. Проверка ────────────────────────────────────────────
CONTAINER_ST=$(docker inspect -f '{{.State.Running}}' wg-easy 2>/dev/null || echo "false")

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║      VOL WG — УСТАНОВКА ЗАВЕРШЕНА       ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
if [[ "$CONTAINER_ST" == "true" ]]; then
    echo -e "  ${BOLD}Статус панели:${NC}    ${GREEN}● Работает${NC}"
else
    echo -e "  ${BOLD}Статус панели:${NC}    ${RED}● Ошибка запуска${NC}"
    echo -e "  ${YELLOW}Логи:${NC} docker logs wg-easy"
fi
echo ""
echo -e "  ${BOLD}Веб-панель:${NC}       http://${SERVER_IP}:${WEB_PORT}"
echo -e "  ${BOLD}Пароль:${NC}           ${PANEL_PASS}"
echo -e "  ${BOLD}WireGuard порт:${NC}   ${WG_PORT}/udp"
echo ""
echo -e "  ${CYAN}Логи:${NC}      docker logs -f wg-easy"
echo -e "  ${CYAN}Restart:${NC}   docker restart wg-easy"
echo -e "  ${CYAN}Обновление:${NC} docker pull ghcr.io/wg-easy/wg-easy && docker restart wg-easy"
echo ""
echo -e "  ${YELLOW}Откройте в браузере:${NC} http://${SERVER_IP}:${WEB_PORT}"
echo ""
