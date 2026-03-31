#!/bin/bash
# ============================================================
#  VOL WG PANEL — WireGuard + Node.js web panel
#  Поддерживает Ubuntu 20.04 / 22.04 / 24.04
#  Запуск: sudo bash install_wg_panel.sh
#  или:    curl -fsSL <url>/install_wg_panel.sh | bash
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

# ─── Публичный IP ───────────────────────────────────────────
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || \
            curl -s --max-time 5 https://ifconfig.me  || \
            hostname -I | awk '{print $1}')
info "Публичный IP: ${BOLD}${SERVER_IP}${NC}"

WG_PORT=51820       # WireGuard UDP
INTERNAL=3051       # wg-easy (только localhost)
WEB_PORT=51821      # Vol WG Panel (публичный)
REPO_RAW="https://raw.githubusercontent.com/robertmiro14-netizen/wg-panel/main"

# ─── 1. Системные пакеты ────────────────────────────────────
info "Обновление пакетов..."
apt update -qq
apt install -y -qq curl ufw iptables openssl 2>/dev/null || true
success "Пакеты готовы"

# ─── 2. Node.js 20 LTS ──────────────────────────────────────
if ! command -v node >/dev/null 2>&1 || [[ $(node -e "process.exit(process.version.split('.')[0].slice(1)<18?1:0)" 2>/dev/null; echo $?) -eq 1 ]]; then
    info "Установка Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt install -y nodejs >/dev/null 2>&1
    success "Node.js установлен: $(node --version)"
else
    success "Node.js уже установлен: $(node --version)"
fi

# ─── 3. Docker ──────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    info "Установка Docker..."
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
    systemctl enable docker >/dev/null 2>&1
    systemctl start docker
    success "Docker установлен: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
    success "Docker уже установлен: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

# ─── 4. IP forwarding ───────────────────────────────────────
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
success "IP forwarding включён"

# ─── 5. UFW ─────────────────────────────────────────────────
info "Настройка UFW..."
ufw allow 22/tcp          >/dev/null 2>&1 || true
ufw allow ${WG_PORT}/udp  >/dev/null 2>&1 || true
ufw allow ${WEB_PORT}/tcp >/dev/null 2>&1 || true
ufw --force enable        >/dev/null 2>&1 || true
success "Порты открыты: 22/tcp, ${WG_PORT}/udp, ${WEB_PORT}/tcp"

# ─── 6. Vol WG Panel (Node.js) ──────────────────────────────
info "Создание Vol WG Panel..."
mkdir -p /opt/vol-panel
chmod 750 /opt/vol-panel

# package.json — через printf (без heredoc, работает в curl|bash)
printf '{"name":"vol-wg-panel","version":"1.0.0","main":"server.js","dependencies":{"bcryptjs":"^2.4.3","express":"^4.19.2","express-session":"^1.18.0"}}\n' \
    > /opt/vol-panel/package.json
success "package.json создан"

# server.js — скачать из репозитория
info "Скачивание server.js..."
curl -fsSL "${REPO_RAW}/server.js" -o /opt/vol-panel/server.js \
    || error "Не удалось скачать server.js с ${REPO_RAW}"
success "server.js загружен"

# panel.html — скачать из репозитория
info "Скачивание panel.html..."
curl -fsSL "${REPO_RAW}/panel.html" -o /opt/vol-panel/panel.html \
    || error "Не удалось скачать panel.html с ${REPO_RAW}"
success "panel.html загружен"

# npm install
info "Установка npm зависимостей..."
cd /opt/vol-panel && npm install --production --quiet 2>/dev/null
success "Зависимости установлены"

# ─── 7. SSL сертификат (самоподписанный) ────────────────────
info "Генерация SSL сертификата..."
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /opt/vol-panel/cert.key \
    -out    /opt/vol-panel/cert.crt \
    -days 3650 \
    -subj "/CN=${SERVER_IP}/O=Vol WG Panel/C=UA" \
    >/dev/null 2>&1
chmod 600 /opt/vol-panel/cert.key
success "SSL сертификат создан (действителен 10 лет)"

# ─── 8. Systemd сервис vol-panel ────────────────────────────
# Используем printf вместо heredoc для совместимости с curl|bash
printf '[Unit]\nDescription=Vol WG Panel\nAfter=network.target docker.service\nWants=docker.service\n\n[Service]\nType=simple\nWorkingDirectory=/opt/vol-panel\nExecStart=/usr/bin/node /opt/vol-panel/server.js\nRestart=always\nRestartSec=5\nEnvironment=NODE_ENV=production\n\n[Install]\nWantedBy=multi-user.target\n' \
    > /etc/systemd/system/vol-panel.service

systemctl daemon-reload
systemctl enable vol-panel >/dev/null 2>&1
systemctl restart vol-panel
success "Vol WG Panel запущена на порту ${WEB_PORT}"

# ─── 8. wg-easy (localhost:3051 only) ───────────────────────
info "Загрузка образа wg-easy..."
mkdir -p /opt/wg-easy
chmod 700 /opt/wg-easy
docker pull ghcr.io/wg-easy/wg-easy >/dev/null 2>&1
success "Образ загружен"

info "Запуск wg-easy (внутренний)..."
docker stop wg-easy 2>/dev/null || true
docker rm   wg-easy 2>/dev/null || true

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
  -p 127.0.0.1:${INTERNAL}:51821/tcp \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  --sysctl="net.ipv6.conf.all.disable_ipv6=1" \
  --restart unless-stopped \
  ghcr.io/wg-easy/wg-easy

sleep 4
success "wg-easy запущен"

# ─── 9. Итоги ───────────────────────────────────────────────
PANEL_OK=$(systemctl is-active vol-panel 2>/dev/null || echo "inactive")
DOCKER_OK=$(docker inspect -f '{{.State.Running}}' wg-easy 2>/dev/null || echo "false")

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║      VOL WG — УСТАНОВКА ЗАВЕРШЕНА       ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
[[ "$PANEL_OK" == "active" ]] \
    && echo -e "  ${BOLD}Vol WG Panel:${NC}     ${GREEN}● Работает${NC}" \
    || echo -e "  ${BOLD}Vol WG Panel:${NC}     ${RED}● Ошибка${NC} (journalctl -u vol-panel)"
[[ "$DOCKER_OK" == "true" ]] \
    && echo -e "  ${BOLD}wg-easy:${NC}          ${GREEN}● Работает${NC}" \
    || echo -e "  ${BOLD}wg-easy:${NC}          ${RED}● Ошибка${NC} (docker logs wg-easy)"
echo ""
echo -e "  ${BOLD}Веб-панель:${NC}  ${CYAN}https://${SERVER_IP}:${WEB_PORT}${NC}"
  echo -e "  ${YELLOW}★  Браузер покажет предупреждение о сертификате — нажмите «Продолжить»${NC}"
  echo -e "  ${YELLOW}★  При первом входе задайте пароль в браузере${NC}"
echo ""
echo -e "  ${CYAN}Логи панели:${NC}   journalctl -u vol-panel -f"
echo -e "  ${CYAN}Логи wg-easy:${NC}  docker logs -f wg-easy"
echo -e "  ${CYAN}Перезапуск:${NC}    systemctl restart vol-panel && docker restart wg-easy"
echo ""
echo ""
