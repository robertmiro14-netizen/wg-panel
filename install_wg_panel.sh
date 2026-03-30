#!/bin/bash
# ============================================================
#  VOL WG  (auto install)
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

# ─── Переменные ─────────────────────────────────────────────
WG_DIR="/etc/wireguard"
PANEL_DIR="/opt/wg-panel"
PANEL_PORT=51820   # WireGuard UDP
WEB_PORT=8080      # Веб-панель HTTP
WG_IFACE="wg0"
WG_NET="10.8.0"
SERVER_WG_IP="${WG_NET}.1"
SUBNET="24"
DNS="1.1.1.1,8.8.8.8"
echo -e "${BOLD}${CYAN}"
echo "  ██╗    ██╗ ██████╗     ██████╗  █████╗ ███╗   ██╗███████╗██╗     "
echo "  ██║    ██║██╔════╝     ██╔══██╗██╔══██╗████╗  ██║██╔════╝██║     "
echo "  ██║ █╗ ██║██║  ███╗    ██████╔╝███████║██╔██╗ ██║█████╗  ██║     "
echo "  ██║███╗██║██║   ██║    ██╔═══╝ ██╔══██║██║╚██╗██║██╔══╝  ██║     "
echo "  ╚███╔███╔╝╚██████╔╝    ██║     ██║  ██║██║ ╚████║███████╗███████╗"
echo "   ╚══╝╚══╝  ╚═════╝     ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝"
echo -e "${NC}"
echo -e "${BOLD}  WireGuard VPN + Web Panel Installer${NC}"
echo "  ─────────────────────────────────────"

# ─── Определение публичного IP ──────────────────────────────
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || \
            curl -s --max-time 5 https://ifconfig.me  || \
            hostname -I | awk '{print $1}')
info "Публичный IP сервера: ${BOLD}${SERVER_IP}${NC}"
info "Пароль панели будет задан при первом заходе в браузере"

# ─── 1. Обновление системы и установка зависимостей ─────────
info "Обновление пакетов..."
apt update -qq
apt install -y -qq wireguard wireguard-tools qrencode iptables curl ufw \
    nodejs npm 2>/dev/null || true

# Node.js — если версия < 18, обновляем через NodeSource
NODE_VER=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo "0")
if [[ "$NODE_VER" -lt 18 ]]; then
    info "Обновление Node.js до v20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt install -y -qq nodejs
fi
success "Node.js $(node -v) установлен"

# ─── 2. Включение IP forwarding ─────────────────────────────
info "Включение IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# ─── 3. Генерация ключей сервера ────────────────────────────
info "Генерация ключей WireGuard..."
mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

if [[ ! -f "$WG_DIR/server_private.key" ]]; then
    wg genkey | tee "$WG_DIR/server_private.key" | \
        wg pubkey > "$WG_DIR/server_public.key"
    chmod 600 "$WG_DIR/server_private.key"
fi

SERVER_PRIV=$(cat "$WG_DIR/server_private.key")
SERVER_PUB=$(cat "$WG_DIR/server_public.key")
success "Ключи сервера готовы"

# ─── 4. Определение интерфейса с выходом в интернет ─────────
DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -1)
info "Основной сетевой интерфейс: ${BOLD}${DEFAULT_IFACE}${NC}"

# ─── 5. Создание конфигурации WireGuard сервера ─────────────
info "Создание конфигурации WireGuard..."
cat > "$WG_DIR/${WG_IFACE}.conf" <<EOF
[Interface]
PrivateKey = ${SERVER_PRIV}
Address = ${SERVER_WG_IP}/${SUBNET}
ListenPort = ${PANEL_PORT}
PostUp   = iptables -A FORWARD -i ${WG_IFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
EOF
chmod 600 "$WG_DIR/${WG_IFACE}.conf"
success "Конфигурация сервера создана"

# ─── 6. Запуск WireGuard ────────────────────────────────────
info "Запуск WireGuard..."
systemctl enable "wg-quick@${WG_IFACE}" >/dev/null 2>&1
systemctl stop  "wg-quick@${WG_IFACE}" 2>/dev/null || true
systemctl start "wg-quick@${WG_IFACE}"
success "WireGuard запущен"

# ─── 7. Правила UFW ─────────────────────────────────────────
info "Настройка UFW..."
ufw allow "${PANEL_PORT}/udp" >/dev/null
ufw allow "${WEB_PORT}/tcp"   >/dev/null
ufw allow 22/tcp              >/dev/null
ufw --force enable            >/dev/null 2>&1 || true

# ─── 8. Директория для клиентов ─────────────────────────────
mkdir -p "$WG_DIR/clients"
# Счётчик IP: храним последний используемый октет
echo "1" > "$WG_DIR/clients/last_ip.txt"

# ─── 9. Установка веб-панели ────────────────────────────────
info "Установка веб-панели..."
mkdir -p "$PANEL_DIR"
cd "$PANEL_DIR"

# — package.json ——————————————————————
cat > package.json <<'PKGJSON'
{
  "name": "wg-panel",
  "version": "1.0.0",
  "description": "WireGuard Web Panel",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "express": "^4.18.2",
    "express-session": "^1.17.3",
    "qrcode": "^1.5.3",
    "multer": "^1.4.5-lts.1",
    "archiver": "^6.0.1"
  }
}
PKGJSON

# — server.js ─────────────────────────────────────────────────
cat > server.js <<'SERVERJS'
'use strict';
const express       = require('express');
const session       = require('express-session');
const { execSync }  = require('child_process');
const fs            = require('fs');
const path          = require('path');
const QRCode        = require('qrcode');
const crypto        = require('crypto');

const app         = express();
const WG_DIR      = '/etc/wireguard';
const WG_IFACE    = 'wg0';
const PANEL_DIR   = '/opt/wg-panel';
const PASS_FILE   = path.join(PANEL_DIR, '.password');
const SECRET_FILE = path.join(PANEL_DIR, '.session_secret');
const WEB_PORT    = parseInt(process.env.WEB_PORT || '8080');
const SERVER_IP   = process.env.SERVER_IP  || '0.0.0.0';
const SERVER_PUB  = fs.readFileSync(path.join(WG_DIR, 'server_public.key'), 'utf8').trim();
const DNS         = process.env.WG_DNS || '1.1.1.1, 8.8.8.8';
const WG_PORT     = parseInt(process.env.WG_PORT || '51820');
const WG_NET      = process.env.WG_NET || '10.8.0';

// ── Постоянный секрет сессии ─────────────────────────────────
let SESSION_SECRET;
if (fs.existsSync(SECRET_FILE)) {
  SESSION_SECRET = fs.readFileSync(SECRET_FILE, 'utf8').trim();
} else {
  SESSION_SECRET = crypto.randomBytes(32).toString('hex');
  fs.writeFileSync(SECRET_FILE, SESSION_SECRET, { mode: 0o600 });
}

// ── Функции пароля ───────────────────────────────────────────
function getPassword() {
  if (!fs.existsSync(PASS_FILE)) return null;
  const p = fs.readFileSync(PASS_FILE, 'utf8').trim();
  return p.length > 0 ? p : null;
}
function isSetupDone() { return getPassword() !== null; }

// ── Middleware ──────────────────────────────────────────────
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(session({
  secret: SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 86400000 }
}));

// ── Auth middleware ─────────────────────────────────────────
function auth(req, res, next) {
  if (!isSetupDone()) return res.redirect('/setup');
  if (req.session.loggedIn) return next();
  res.redirect('/login');
}

// ── Helpers ─────────────────────────────────────────────────
function shell(cmd) {
  try { return execSync(cmd, { encoding: 'utf8' }).trim(); }
  catch (e) { return ''; }
}

function nextClientIP() {
  const f = path.join(WG_DIR, 'clients', 'last_ip.txt');
  let last = parseInt(fs.readFileSync(f, 'utf8').trim() || '1');
  last++;
  fs.writeFileSync(f, String(last));
  return `${WG_NET}.${last}`;
}

function getClients() {
  const dir = path.join(WG_DIR, 'clients');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(n => n.endsWith('.conf'))
    .map(n => {
      const name = n.replace('.conf', '');
      const conf = fs.readFileSync(path.join(dir, n), 'utf8');
      const ipMatch = conf.match(/Address\s*=\s*([\d.]+)/);
      const ip = ipMatch ? ipMatch[1] : '?';
      const pubMatch = conf.match(/PublicKey\s*=\s*(\S+)/i);
      const pub = pubMatch ? pubMatch[1] : '';
      return { name, ip, conf, pub };
    });
}

function getWgStatus() {
  try {
    return shell(`wg show ${WG_IFACE}`);
  } catch { return 'WireGuard не запущен'; }
}

function getServerStatus() {
  const uptime  = shell('uptime -p');
  const load    = shell("cat /proc/loadavg | awk '{print $1, $2, $3}'");
  const mem     = shell("free -m | awk '/Mem/{printf \"%s MB / %s MB\", $3, $2}'");
  const wgUp    = shell(`systemctl is-active wg-quick@${WG_IFACE}`) === 'active';
  const peers   = shell(`wg show ${WG_IFACE} peers 2>/dev/null | wc -l`);
  return { uptime, load, mem, wgUp, peers };
}

// ── HTML Builder ─────────────────────────────────────────────
function html(title, body, user = true) {
  const nav = user ? `
    <nav>
      <div class="nav-brand">⚡ WG Panel</div>
      <div class="nav-links">
        <a href="/">Dashboard</a>
        <a href="/clients">Клиенты</a>
        <a href="/status">Статус</a>
        <a href="/logout">Выйти</a>
      </div>
    </nav>` : '';
  return `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} — WG Panel</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root {
  --bg:       #0d0f14;
  --surface:  #161a23;
  --card:     #1c2130;
  --border:   #2a3045;
  --accent:   #6c63ff;
  --accent2:  #00d4aa;
  --red:      #ff4d6d;
  --text:     #e2e8f0;
  --muted:    #8892a4;
  --radius:   12px;
}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Inter',sans-serif;background:var(--bg);color:var(--text);min-height:100vh}
a{color:var(--accent);text-decoration:none}
a:hover{opacity:.8}

/* NAV */
nav{display:flex;align-items:center;justify-content:space-between;
    padding:0 2rem;height:64px;background:var(--surface);
    border-bottom:1px solid var(--border);position:sticky;top:0;z-index:100;
    backdrop-filter:blur(10px)}
.nav-brand{font-size:1.25rem;font-weight:700;background:linear-gradient(135deg,var(--accent),var(--accent2));
           -webkit-background-clip:text;-webkit-text-fill-color:transparent}
.nav-links a{margin-left:1.5rem;color:var(--muted);font-size:.9rem;font-weight:500;
             transition:color .2s}
.nav-links a:hover{color:var(--text)}

/* LAYOUT */
.container{max-width:1100px;margin:0 auto;padding:2rem 1.5rem}
.page-title{font-size:1.75rem;font-weight:700;margin-bottom:1.75rem;
            display:flex;align-items:center;gap:.75rem}
.page-title span{font-size:1.5rem}

/* CARDS */
.card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);
      padding:1.5rem;margin-bottom:1.25rem}
.card-title{font-size:1rem;font-weight:600;color:var(--muted);
            text-transform:uppercase;letter-spacing:.05em;margin-bottom:1rem}

/* GRID */
.grid-3{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem;margin-bottom:1.5rem}
.stat-card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);
           padding:1.25rem;display:flex;flex-direction:column;gap:.4rem}
.stat-label{font-size:.8rem;color:var(--muted);font-weight:500;text-transform:uppercase;letter-spacing:.05em}
.stat-value{font-size:1.4rem;font-weight:700;color:var(--text)}
.stat-value.green{color:var(--accent2)}
.stat-value.red{color:var(--red)}

/* BADGE */
.badge{display:inline-block;padding:.2rem .6rem;border-radius:20px;font-size:.75rem;font-weight:600}
.badge-green{background:rgba(0,212,170,.15);color:var(--accent2)}
.badge-red{background:rgba(255,77,109,.15);color:var(--red)}
.badge-blue{background:rgba(108,99,255,.15);color:var(--accent)}

/* TABLE */
table{width:100%;border-collapse:collapse}
th{text-align:left;padding:.75rem 1rem;font-size:.8rem;color:var(--muted);
   text-transform:uppercase;letter-spacing:.05em;border-bottom:1px solid var(--border)}
td{padding:.9rem 1rem;border-bottom:1px solid var(--border);font-size:.9rem}
tr:last-child td{border-bottom:none}
tr:hover td{background:rgba(255,255,255,.02)}
.mono{font-family:'JetBrains Mono',monospace;font-size:.85rem}

/* BUTTONS */
.btn{display:inline-flex;align-items:center;gap:.4rem;padding:.55rem 1.1rem;
     border:none;border-radius:8px;font-size:.875rem;font-weight:600;cursor:pointer;
     transition:all .2s;text-decoration:none}
.btn-primary{background:var(--accent);color:#fff}
.btn-primary:hover{background:#5a52d5;opacity:1}
.btn-success{background:var(--accent2);color:#0d1117}
.btn-success:hover{background:#00b894;opacity:1}
.btn-danger{background:var(--red);color:#fff}
.btn-danger:hover{background:#e63d5a;opacity:1}
.btn-ghost{background:var(--border);color:var(--text)}
.btn-ghost:hover{background:#3a4558;opacity:1}
.btn-sm{padding:.35rem .75rem;font-size:.8rem}

/* FORMS */
.form-group{margin-bottom:1rem}
label{display:block;margin-bottom:.4rem;font-size:.875rem;font-weight:500;color:var(--muted)}
input[type=text],input[type=password]{width:100%;padding:.7rem 1rem;
  background:var(--surface);border:1px solid var(--border);border-radius:8px;
  color:var(--text);font-size:.9rem;font-family:inherit;outline:none;transition:border-color .2s}
input:focus{border-color:var(--accent)}

/* ALERT */
.alert{padding:.875rem 1.25rem;border-radius:8px;margin-bottom:1rem;font-size:.9rem}
.alert-success{background:rgba(0,212,170,.1);border:1px solid rgba(0,212,170,.3);color:var(--accent2)}
.alert-error{background:rgba(255,77,109,.1);border:1px solid rgba(255,77,109,.3);color:var(--red)}

/* QR */
.qr-wrap{text-align:center;padding:1rem}
.qr-wrap canvas,.qr-wrap img{border-radius:12px;border:4px solid var(--border)}

/* CODE */
pre{background:var(--surface);border:1px solid var(--border);border-radius:8px;
    padding:1rem;overflow-x:auto;font-family:'JetBrains Mono',monospace;
    font-size:.8rem;line-height:1.6;color:var(--accent2);white-space:pre-wrap}

/* LOGIN */
.login-wrap{display:flex;align-items:center;justify-content:center;min-height:100vh}
.login-card{background:var(--card);border:1px solid var(--border);border-radius:16px;
            padding:2.5rem;width:100%;max-width:380px;box-shadow:0 20px 60px rgba(0,0,0,.5)}
.login-logo{text-align:center;font-size:2.5rem;margin-bottom:.5rem}
.login-title{text-align:center;font-size:1.4rem;font-weight:700;margin-bottom:.25rem}
.login-sub{text-align:center;font-size:.85rem;color:var(--muted);margin-bottom:2rem}

/* BTN GROUP */
.btn-group{display:flex;gap:.5rem;flex-wrap:wrap}

/* STATUS PRE */
.wg-status{font-family:'JetBrains Mono',monospace;font-size:.8rem;
           background:var(--surface);border:1px solid var(--border);
           border-radius:8px;padding:1.25rem;color:var(--accent2);
           white-space:pre-wrap;max-height:400px;overflow-y:auto}

@media(max-width:600px){
  .grid-3{grid-template-columns:1fr}
  nav{padding:0 1rem}
  .nav-links a{margin-left:.75rem}
}
</style>
</head>
<body>
${nav}
<div class="container">${body}</div>
</body>
</html>`;
}

// ══════════════════════════════════════════════════════════════
// ROUTES
// ══════════════════════════════════════════════════════════════

// ── Setup (первый запуск) ────────────────────────────────────
app.get('/setup', (req, res) => {
  if (isSetupDone()) return res.redirect('/login');
  const flash = req.query.err
    ? `<div class="alert alert-error">${decodeURIComponent(req.query.err)}</div>` : '';
  res.send(html('Настройка', `
    <div class="login-wrap">
      <div class="login-card">
        <div class="login-logo">🔐</div>
        <div class="login-title">Первая настройка</div>
        <div class="login-sub">Придумайте пароль для входа в панель управления</div>
        ${flash}
        <form method="POST" action="/setup">
          <div class="form-group">
            <label>Пароль (мин. 6 символов)</label>
            <input type="password" name="password" autofocus placeholder="Введите пароль" id="pass1">
          </div>
          <div class="form-group">
            <label>Подтвердите пароль</label>
            <input type="password" name="confirm" placeholder="Повторите пароль" id="pass2">
          </div>
          <button class="btn btn-primary" style="width:100%;justify-content:center;margin-top:.5rem">
            Установить пароль и войти →
          </button>
        </form>
      </div>
    </div>`, false));
});

app.post('/setup', (req, res) => {
  if (isSetupDone()) return res.redirect('/login');
  const pass    = (req.body.password || '').trim();
  const confirm = (req.body.confirm  || '').trim();
  if (pass.length < 6)
    return res.redirect('/setup?err=' + encodeURIComponent('Пароль должен быть минимум 6 символов'));
  if (pass !== confirm)
    return res.redirect('/setup?err=' + encodeURIComponent('Пароли не совпадают'));
  fs.writeFileSync(PASS_FILE, pass, { mode: 0o600 });
  req.session.loggedIn = true;
  res.redirect('/?msg=' + encodeURIComponent('Пароль установлен! Добро пожаловать'));
});

// ── Логин ───────────────────────────────────────────────────
app.get('/login', (req, res) => {
  if (!isSetupDone()) return res.redirect('/setup');
  if (req.session.loggedIn) return res.redirect('/');
  const flash = req.query.err
    ? `<div class="alert alert-error">Неверный пароль</div>` : '';
  res.send(html('Вход', `
    <div class="login-wrap">
      <div class="login-card">
        <div class="login-logo">⚡</div>
        <div class="login-title">WireGuard Panel</div>
        <div class="login-sub">Введите пароль для доступа</div>
        ${flash}
        <form method="POST" action="/login">
          <div class="form-group">
            <label>Пароль</label>
            <input type="password" name="password" autofocus placeholder="••••••••">
          </div>
          <button class="btn btn-primary" style="width:100%;justify-content:center">
            Войти →
          </button>
        </form>
      </div>
    </div>`, false));
});

app.post('/login', (req, res) => {
  if (req.body.password === getPassword()) {
    req.session.loggedIn = true;
    res.redirect('/');
  } else {
    res.redirect('/login?err=1');
  }
});

app.get('/logout', (req, res) => {
  req.session.destroy(() => res.redirect('/login'));
});

// ── Dashboard ───────────────────────────────────────────────
app.get('/', auth, (req, res) => {
  const st = getServerStatus();
  const clients = getClients();
  const wgBadge = st.wgUp
    ? `<span class="badge badge-green">● Активен</span>`
    : `<span class="badge badge-red">● Остановлен</span>`;

  res.send(html('Dashboard', `
    <div class="page-title"><span>📊</span> Dashboard</div>
    <div class="grid-3">
      <div class="stat-card">
        <div class="stat-label">WireGuard</div>
        <div class="stat-value ${st.wgUp ? 'green' : 'red'}">${st.wgUp ? 'Online' : 'Offline'}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Клиенты</div>
        <div class="stat-value">${clients.length}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Пиры (активных)</div>
        <div class="stat-value">${st.peers || '0'}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Uptime</div>
        <div class="stat-value" style="font-size:1rem">${st.uptime}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Нагрузка</div>
        <div class="stat-value" style="font-size:1rem">${st.load}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Память</div>
        <div class="stat-value" style="font-size:1rem">${st.mem}</div>
      </div>
    </div>

    <div class="card">
      <div class="card-title">Быстрые действия</div>
      <div class="btn-group">
        <a href="/clients/add" class="btn btn-primary">+ Добавить клиента</a>
        <a href="/clients" class="btn btn-ghost">👥 Все клиенты</a>
        <a href="/status" class="btn btn-ghost">📡 Статус WireGuard</a>
        <form method="POST" action="/wg/restart" style="display:inline">
          <button class="btn btn-ghost">🔄 Перезапустить WG</button>
        </form>
      </div>
    </div>

    <div class="card">
      <div class="card-title">Информация о сервере</div>
      <table>
        <tr><td style="color:var(--muted);width:200px">IP сервера</td><td class="mono">${SERVER_IP}</td></tr>
        <tr><td style="color:var(--muted)">WireGuard порт</td><td class="mono">${WG_PORT}/udp</td></tr>
        <tr><td style="color:var(--muted)">Публичный ключ</td><td class="mono" style="word-break:break-all">${SERVER_PUB}</td></tr>
        <tr><td style="color:var(--muted)">Статус</td><td>${wgBadge}</td></tr>
        <tr><td style="color:var(--muted)">DNS</td><td class="mono">${DNS}</td></tr>
      </table>
    </div>
  `));
});

// ── Список клиентов ─────────────────────────────────────────
app.get('/clients', auth, (req, res) => {
  const clients = getClients();
  const flash = req.query.msg
    ? `<div class="alert alert-success">${decodeURIComponent(req.query.msg)}</div>` : '';
  const errFlash = req.query.err
    ? `<div class="alert alert-error">${decodeURIComponent(req.query.err)}</div>` : '';

  const rows = clients.length
    ? clients.map(c => `
      <tr>
        <td><strong>${c.name}</strong></td>
        <td class="mono">${c.ip}</td>
        <td>
          <div class="btn-group">
            <a href="/clients/${encodeURIComponent(c.name)}/qr" class="btn btn-sm btn-success">QR</a>
            <a href="/clients/${encodeURIComponent(c.name)}/download" class="btn btn-sm btn-primary">↓ Конфиг</a>
            <a href="/clients/${encodeURIComponent(c.name)}/view" class="btn btn-sm btn-ghost">Просмотр</a>
            <form method="POST" action="/clients/${encodeURIComponent(c.name)}/delete" style="display:inline"
              onsubmit="return confirm('Удалить клиента ${c.name}?')">
              <button class="btn btn-sm btn-danger">✕</button>
            </form>
          </div>
        </td>
      </tr>`).join('')
    : `<tr><td colspan="3" style="text-align:center;color:var(--muted);padding:2rem">
        Нет клиентов. <a href="/clients/add">Добавить первого →</a>
       </td></tr>`;

  res.send(html('Клиенты', `
    <div class="page-title"><span>👥</span> Клиенты VPN</div>
    ${flash}${errFlash}
    <div style="margin-bottom:1rem">
      <a href="/clients/add" class="btn btn-primary">+ Добавить клиента</a>
    </div>
    <div class="card" style="padding:0;overflow:hidden">
      <table>
        <thead><tr>
          <th>Имя</th><th>IP адрес</th><th>Действия</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>
  `));
});

// ── Добавить клиента — форма ─────────────────────────────────
app.get('/clients/add', auth, (req, res) => {
  res.send(html('Добавить клиента', `
    <div class="page-title"><span>➕</span> Новый клиент</div>
    <div class="card" style="max-width:480px">
      <form method="POST" action="/clients/add">
        <div class="form-group">
          <label>Имя клиента</label>
          <input type="text" name="name" placeholder="например: phone, laptop, office"
            pattern="[a-zA-Z0-9_-]+" title="Только буквы, цифры, дефис, подчёркивание" required autofocus>
        </div>
        <div class="btn-group">
          <button class="btn btn-primary">Создать клиента</button>
          <a href="/clients" class="btn btn-ghost">Отмена</a>
        </div>
      </form>
    </div>
  `));
});

// ── Добавить клиента — обработка ────────────────────────────
app.post('/clients/add', auth, (req, res) => {
  let name = (req.body.name || '').trim().replace(/[^a-zA-Z0-9_-]/g, '');
  if (!name) return res.redirect('/clients?err=' + encodeURIComponent('Некорректное имя'));

  const clientConf = path.join(WG_DIR, 'clients', `${name}.conf`);
  if (fs.existsSync(clientConf))
    return res.redirect('/clients?err=' + encodeURIComponent(`Клиент "${name}" уже существует`));

  // Генерация ключей клиента
  const privKey = shell('wg genkey');
  const pubKey  = shell(`echo "${privKey}" | wg pubkey`);
  const psk     = shell('wg genpsk');
  const clientIP = nextClientIP();

  // Конфиг клиента
  const clientConfig = `[Interface]
PrivateKey = ${privKey}
Address = ${clientIP}/32
DNS = ${DNS}

[Peer]
PublicKey = ${SERVER_PUB}
PresharedKey = ${psk}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${SERVER_IP}:${WG_PORT}
PersistentKeepalive = 25
`;
  fs.writeFileSync(clientConf, clientConfig, { mode: 0o600 });

  // Добавление в конфиг сервера
  const peerBlock = `\n[Peer]\n# ${name}\nPublicKey = ${pubKey}\nPresharedKey = ${psk}\nAllowedIPs = ${clientIP}/32\n`;
  fs.appendFileSync(path.join(WG_DIR, `${WG_IFACE}.conf`), peerBlock);

  // Добавить пир без перезапуска WireGuard
  shell(`wg set ${WG_IFACE} peer ${pubKey} preshared-key <(echo "${psk}") allowed-ips ${clientIP}/32 2>/dev/null || true`);

  res.redirect(`/clients/${encodeURIComponent(name)}/qr?msg=` + encodeURIComponent(`Клиент "${name}" создан`));
});

// ── QR-код клиента ───────────────────────────────────────────
app.get('/clients/:name/qr', auth, async (req, res) => {
  const name = req.params.name;
  const clientConf = path.join(WG_DIR, 'clients', `${name}.conf`);
  if (!fs.existsSync(clientConf))
    return res.redirect('/clients?err=' + encodeURIComponent('Клиент не найден'));

  const conf = fs.readFileSync(clientConf, 'utf8');
  const flash = req.query.msg
    ? `<div class="alert alert-success">${decodeURIComponent(req.query.msg)}</div>` : '';

  let qrImg = '';
  try {
    qrImg = await QRCode.toDataURL(conf, {
      width: 280,
      margin: 2,
      color: { dark: '#1c2130', light: '#e2e8f0' }
    });
  } catch (e) {}

  res.send(html(`QR — ${name}`, `
    <div class="page-title"><span>📱</span> QR-код: ${name}</div>
    ${flash}
    <div class="card" style="max-width:400px;margin:0 auto;text-align:center">
      <div class="card-title" style="text-align:center">Сканируйте в приложении WireGuard</div>
      ${qrImg ? `<div class="qr-wrap"><img src="${qrImg}" alt="QR" style="width:280px;height:280px"></div>` : '<p style="color:var(--red)">Ошибка генерации QR</p>'}
      <div style="margin-top:1.25rem" class="btn-group" style="justify-content:center">
        <a href="/clients/${encodeURIComponent(name)}/download" class="btn btn-primary">↓ Скачать конфиг</a>
        <a href="/clients/${encodeURIComponent(name)}/view" class="btn btn-ghost">Просмотр</a>
        <a href="/clients" class="btn btn-ghost">← Назад</a>
      </div>
    </div>
  `));
});

// ── Просмотр конфига ────────────────────────────────────────
app.get('/clients/:name/view', auth, (req, res) => {
  const name = req.params.name;
  const clientConf = path.join(WG_DIR, 'clients', `${name}.conf`);
  if (!fs.existsSync(clientConf))
    return res.redirect('/clients?err=' + encodeURIComponent('Клиент не найден'));

  const conf = fs.readFileSync(clientConf, 'utf8');
  res.send(html(`Конфиг — ${name}`, `
    <div class="page-title"><span>📄</span> Конфиг: ${name}</div>
    <div class="card">
      <div class="card-title">wireguard.conf</div>
      <pre>${conf.replace(/</g,'&lt;').replace(/>/g,'&gt;')}</pre>
      <div class="btn-group" style="margin-top:1rem">
        <a href="/clients/${encodeURIComponent(name)}/download" class="btn btn-primary">↓ Скачать</a>
        <a href="/clients/${encodeURIComponent(name)}/qr" class="btn btn-success">QR</a>
        <a href="/clients" class="btn btn-ghost">← Назад</a>
      </div>
    </div>
  `));
});

// ── Скачать конфиг ──────────────────────────────────────────
app.get('/clients/:name/download', auth, (req, res) => {
  const name = req.params.name;
  const clientConf = path.join(WG_DIR, 'clients', `${name}.conf`);
  if (!fs.existsSync(clientConf))
    return res.status(404).send('Not found');

  res.setHeader('Content-Type', 'application/octet-stream');
  res.setHeader('Content-Disposition', `attachment; filename="${name}_wg.conf"`);
  res.sendFile(clientConf);
});

// ── Удалить клиента ─────────────────────────────────────────
app.post('/clients/:name/delete', auth, (req, res) => {
  const name = req.params.name;
  const clientConf = path.join(WG_DIR, 'clients', `${name}.conf`);
  if (!fs.existsSync(clientConf))
    return res.redirect('/clients?err=' + encodeURIComponent('Клиент не найден'));

  const conf = fs.readFileSync(clientConf, 'utf8');
  const pubMatch = conf.match(/PublicKey\s*=\s*(\S+)/i);

  // Удалить из wg0
  if (pubMatch) {
    shell(`wg set ${WG_IFACE} peer ${pubMatch[1]} remove 2>/dev/null || true`);
  }

  // Удалить блок из конфига сервера
  let serverConf = fs.readFileSync(path.join(WG_DIR, `${WG_IFACE}.conf`), 'utf8');
  const peerRegex = new RegExp(`\\n\\[Peer\\]\\n# ${name}\\n[\\s\\S]*?(?=\\n\\[Peer\\]|$)`, 'g');
  serverConf = serverConf.replace(peerRegex, '');
  fs.writeFileSync(path.join(WG_DIR, `${WG_IFACE}.conf`), serverConf);

  fs.unlinkSync(clientConf);
  res.redirect('/clients?msg=' + encodeURIComponent(`Клиент "${name}" удалён`));
});

// ── Статус WireGuard ─────────────────────────────────────────
app.get('/status', auth, (req, res) => {
  const wgStatus = getWgStatus();
  res.send(html('Статус', `
    <div class="page-title"><span>📡</span> Статус WireGuard</div>
    <div class="card">
      <div class="card-title">wg show ${WG_IFACE}</div>
      <div class="wg-status">${wgStatus || 'Нет данных'}</div>
    </div>
    <div class="btn-group">
      <form method="POST" action="/wg/restart">
        <button class="btn btn-ghost">🔄 Перезапустить WireGuard</button>
      </form>
      <a href="/" class="btn btn-ghost">← Dashboard</a>
    </div>
  `));
});

// ── Управление WireGuard ─────────────────────────────────────
app.post('/wg/restart', auth, (req, res) => {
  shell(`systemctl restart wg-quick@${WG_IFACE}`);
  res.redirect('/?msg=restarted');
});

// ── Запуск ───────────────────────────────────────────────────
app.listen(WEB_PORT, '0.0.0.0', () => {
  console.log(`[WG Panel] Запущен на http://0.0.0.0:${WEB_PORT}`);
  console.log(`[WG Panel] SERVER_IP=${SERVER_IP}`);
});
SERVERJS

# — Установка зависимостей npm ─────────────────────────────
info "Установка npm-зависимостей..."
npm install --production --silent
success "npm-пакеты установлены"

# ─── 10. Systemd-сервис для веб-панели ──────────────────────
info "Создание systemd сервиса..."
cat > /etc/systemd/system/wg-panel.service <<EOF
[Unit]
Description=WireGuard Web Panel
After=network.target wg-quick@${WG_IFACE}.service

[Service]
Type=simple
WorkingDirectory=${PANEL_DIR}
ExecStart=/usr/bin/node ${PANEL_DIR}/server.js
Restart=on-failure
RestartSec=5
Environment="WEB_PORT=${WEB_PORT}"
Environment="SERVER_IP=${SERVER_IP}"
Environment="WG_PORT=${PANEL_PORT}"
Environment="WG_DNS=${DNS}"
Environment="WG_NET=${WG_NET}"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wg-panel >/dev/null 2>&1
systemctl restart wg-panel
sleep 2

# ─── Проверка статуса ───────────────────────────────────────
WG_ST=$(systemctl is-active "wg-quick@${WG_IFACE}" 2>/dev/null)
PANEL_ST=$(systemctl is-active wg-panel 2>/dev/null)

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║        УСТАНОВКА ЗАВЕРШЕНА               ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Веб-панель:${NC}      http://${SERVER_IP}:${WEB_PORT}"
echo -e "  ${BOLD}WireGuard:${NC}       ${WG_ST}"
echo -e "  ${BOLD}Панель:${NC}          ${PANEL_ST}"
echo ""
echo -e "  ${CYAN}Логи панели:${NC}  journalctl -u wg-panel -f"
echo -e "  ${CYAN}Логи WG:${NC}      journalctl -u wg-quick@${WG_IFACE} -f"
echo ""
echo -e "  ${YELLOW}Откройте в браузере:${NC} http://${SERVER_IP}:${WEB_PORT}"
echo -e "  ${GREEN}При первом входе установите свой пароль${NC}"
echo ""
