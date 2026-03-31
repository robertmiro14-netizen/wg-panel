#!/bin/bash
# ============================================================
#  VOL WG — WireGuard + wg-easy + Nginx (Vol WG Panel)
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
echo -e "${BOLD}  VOL WG PANEL — WireGuard VPN${NC}"
echo "  ──────────────────────────────"
echo ""

# ─── Определение публичного IP ──────────────────────────────
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || \
            curl -s --max-time 5 https://ifconfig.me  || \
            hostname -I | awk '{print $1}')
info "Публичный IP сервера: ${BOLD}${SERVER_IP}${NC}"

# ─── Порты ──────────────────────────────────────────────────
WG_PORT=51820        # WireGuard UDP (туннель)
INTERNAL_PORT=3051   # wg-easy внутренний (только localhost)
WEB_PORT=51821       # Публичный порт (Nginx → Vol WG Panel)

# ─── 1. Обновление системы ──────────────────────────────────
info "Обновление пакетов..."
apt update -qq
apt install -y -qq curl ufw iptables nginx 2>/dev/null || true
success "Пакеты установлены"

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

# ─── 6. Загрузка образа wg-easy ─────────────────────────────
info "Загрузка образа wg-easy (это займёт минуту)..."
docker pull ghcr.io/wg-easy/wg-easy >/dev/null 2>&1
success "Образ загружен"

# ─── 7. Запуск wg-easy (localhost only, без пароля) ─────────
info "Запуск wg-easy..."

docker stop wg-easy 2>/dev/null || true
docker rm   wg-easy 2>/dev/null || true

# Пароль НЕ задаётся здесь — пользователь установит его
# при первом открытии панели в браузере
docker run -d \
  --name=wg-easy \
  -e LANG=ru \
  -e WG_HOST="${SERVER_IP}" \
  -e WG_PORT=${WG_PORT} \
  -e WG_DEFAULT_DNS="1.1.1.1, 8.8.8.8" \
  -e WG_MTU=1420 \
  -e WG_PERSISTENT_KEEPALIVE=25 \
  -e WG_DEFAULT_ADDRESS="10.8.0.x" \
  -e UI_TRAFFIC_STATS=true \
  -e UI_CHART_TYPE=1 \
  -v /opt/wg-easy:/etc/wireguard \
  -p ${WG_PORT}:${WG_PORT}/udp \
  -p 127.0.0.1:${INTERNAL_PORT}:51821/tcp \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  --sysctl="net.ipv6.conf.all.disable_ipv6=1" \
  --restart unless-stopped \
  ghcr.io/wg-easy/wg-easy

sleep 3
success "wg-easy запущен (порт ${INTERNAL_PORT}, localhost)"

# ─── 8. Nginx — брендинг «Vol WG Panel» ─────────────────────
info "Настройка Nginx с брендингом Vol WG Panel..."

cat > /etc/nginx/sites-available/vol-wg-panel << NGINXEOF
server {
    listen ${WEB_PORT};
    server_name _;

    # Отключаем показ версии Nginx
    server_tokens off;

    location / {
        proxy_pass         http://127.0.0.1:${INTERNAL_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$http_host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";

        # Отключаем сжатие — нужно для sub_filter
        proxy_set_header   Accept-Encoding   "";

        # Замена брендинга
        sub_filter_once off;
        sub_filter_types text/html;
        sub_filter 'WireGuard' 'Vol WG Panel';
    }
}
NGINXEOF

# Включаем сайт, отключаем default
ln -sf /etc/nginx/sites-available/vol-wg-panel /etc/nginx/sites-enabled/vol-wg-panel
rm -f /etc/nginx/sites-enabled/default

nginx -t >/dev/null 2>&1 && systemctl restart nginx && systemctl enable nginx >/dev/null 2>&1
success "Nginx настроен и запущен"

# ─── 9. Итоги ───────────────────────────────────────────────
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
    echo -e "  ${YELLOW}Логи:${NC}  docker logs wg-easy"
fi
echo ""
echo -e "  ${BOLD}Веб-панель:${NC}       ${CYAN}http://${SERVER_IP}:${WEB_PORT}${NC}"
echo -e "  ${YELLOW}★ При первом входе установите пароль в браузере${NC}"
echo -e "  ${BOLD}WireGuard порт:${NC}   ${WG_PORT}/udp"
echo ""
echo -e "  ${CYAN}Логи wg-easy:${NC}   docker logs -f wg-easy"
echo -e "  ${CYAN}Перезапуск:${NC}     docker restart wg-easy"
echo -e "  ${CYAN}Обновление:${NC}     docker pull ghcr.io/wg-easy/wg-easy && docker restart wg-easy"
echo ""
echo -e "  Откройте в браузере: ${BOLD}http://${SERVER_IP}:${WEB_PORT}${NC}"
echo ""
