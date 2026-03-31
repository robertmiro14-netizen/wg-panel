'use strict';
const express  = require('express');
const session  = require('express-session');
const bcrypt   = require('bcryptjs');
const https    = require('https');
const http     = require('http');
const fs       = require('fs');
const path     = require('path');
const crypto   = require('crypto');

const PORT    = 51821;
const WG_HOST = '127.0.0.1';
const WG_PORT = 3051;
const PWFILE  = '/opt/vol-panel/.password';
const HTML    = path.join(__dirname, 'panel.html');
const CERT_KEY = '/opt/vol-panel/cert.key';
const CERT_CRT = '/opt/vol-panel/cert.crt';

const app = express();
app.set('trust proxy', 1);
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(session({
  secret: crypto.randomBytes(32).toString('hex'),
  resave: false, saveUninitialized: false,
  cookie: { httpOnly: true, secure: fs.existsSync(CERT_KEY), maxAge: 86400000 }
}));

const hasPwd = () => fs.existsSync(PWFILE);
const auth   = (req, res, next) => {
  if (!hasPwd()) return res.redirect('/setup');
  if (req.session && req.session.ok) return next();
  res.redirect('/login');
};

// ── Auth pages ────────────────────────────────────────────────
function authPage(title, formHtml, err) {
  return `<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vol WG Panel</title><style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
background:linear-gradient(135deg,#1a1a2e,#0f3460);
min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
.c{background:#fff;border-radius:16px;box-shadow:0 20px 60px rgba(0,0,0,.35);
padding:44px;width:100%;max-width:400px}
.logo{display:flex;align-items:center;gap:12px;margin-bottom:32px}
.lb{width:44px;height:44px;background:linear-gradient(135deg,#c0392b,#e74c3c);
border-radius:12px;display:flex;align-items:center;justify-content:center}
.lb svg{width:22px;height:22px;fill:none;stroke:#fff;stroke-width:2.5;stroke-linecap:round;stroke-linejoin:round}
.lt{font-size:18px;font-weight:700;color:#1a1a2e}
.lt small{font-size:11px;font-weight:400;color:#888;display:block}
h2{font-size:15px;color:#555;margin-bottom:22px;font-weight:400}
.err{background:#fef2f2;border-left:4px solid #e74c3c;color:#c0392b;
padding:10px 14px;border-radius:6px;margin-bottom:14px;font-size:13px}
.f{margin-bottom:16px}label{display:block;font-size:13px;color:#444;margin-bottom:6px;font-weight:500}
input[type=password]{width:100%;padding:11px 14px;border:1.5px solid #e0e0e0;border-radius:10px;
font-size:15px;outline:none;background:#fafafa;transition:border-color .2s,box-shadow .2s}
input[type=password]:focus{border-color:#c0392b;background:#fff;box-shadow:0 0 0 3px rgba(192,57,43,.08)}
button{width:100%;padding:12px;background:linear-gradient(135deg,#c0392b,#e74c3c);
color:#fff;border:none;border-radius:10px;font-size:15px;font-weight:600;cursor:pointer;margin-top:6px}
button:hover{opacity:.9}
</style></head><body><div class="c">
<div class="logo"><div class="lb">
<svg viewBox="0 0 24 24"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/></svg>
</div><div class="lt">Vol WG Panel<small>VPN Management</small></div></div>
<h2>${title}</h2>${err ? '<div class="err">'+err+'</div>' : ''}
<form method="POST">${formHtml}</form></div></body></html>`;
}

const setupForm = `<div class="f"><label>Пароль (мин. 6 символов)</label>
<input type="password" name="p" autofocus required></div>
<div class="f"><label>Подтвердите пароль</label>
<input type="password" name="c" required></div>
<button>Создать и войти →</button>`;

const loginForm = `<div class="f"><label>Пароль</label>
<input type="password" name="p" autofocus required></div>
<button>Войти →</button>`;

// ── Setup / Login / Logout ────────────────────────────────────
app.get('/setup', (req, res) => {
  if (hasPwd()) return res.redirect('/login');
  res.send(authPage('Создайте пароль администратора', setupForm));
});
app.post('/setup', async (req, res) => {
  if (hasPwd()) return res.redirect('/login');
  const { p, c } = req.body;
  if (!p || p.length < 6) return res.send(authPage('Создайте пароль', setupForm, 'Минимум 6 символов'));
  if (p !== c)            return res.send(authPage('Создайте пароль', setupForm, 'Пароли не совпадают'));
  fs.writeFileSync(PWFILE, await bcrypt.hash(p, 12), { mode: 0o600 });
  req.session.ok = true;
  res.redirect('/');
});
app.get('/login', (req, res) => {
  if (!hasPwd()) return res.redirect('/setup');
  if (req.session && req.session.ok) return res.redirect('/');
  res.send(authPage('Войдите в панель', loginForm));
});
app.post('/login', async (req, res) => {
  if (!hasPwd()) return res.redirect('/setup');
  try {
    const ok = await bcrypt.compare(req.body.p, fs.readFileSync(PWFILE,'utf8').trim());
    if (ok) { req.session.ok = true; return res.redirect('/'); }
  } catch(e) {}
  res.send(authPage('Войдите в панель', loginForm, 'Неверный пароль'));
});
app.get(['/logout','/api/logout'], (req,res) => req.session.destroy(() => res.redirect('/login')));

// ── wg-easy API helper ────────────────────────────────────────
function wgReq(method, p, body) {
  return new Promise((resolve, reject) => {
    const opts = { hostname: WG_HOST, port: WG_PORT, path: p, method,
      headers: { 'Content-Type':'application/json', 'Accept':'application/json', 'Accept-Encoding':'identity' } };
    const req = http.request(opts, res => {
      let d = []; res.on('data', c => d.push(c));
      res.on('end', () => {
        const buf = Buffer.concat(d).toString();
        try { resolve({ status: res.statusCode, body: JSON.parse(buf), headers: res.headers }); }
        catch(e) { resolve({ status: res.statusCode, body: buf, headers: res.headers }); }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}
function wgRaw(p) {
  return new Promise((resolve, reject) => {
    http.get({ hostname: WG_HOST, port: WG_PORT, path: p }, res => {
      const d = []; res.on('data', c => d.push(c));
      res.on('end', () => resolve({ status: res.statusCode, buf: Buffer.concat(d), headers: res.headers }));
    }).on('error', reject);
  });
}

// ── API routes ────────────────────────────────────────────────
app.get('/api/clients', auth, async (req, res) => {
  try {
    // Try wg-easy v14 path, fallback to older path
    let r = await wgReq('GET', '/api/wireguard/client');
    if (r.status !== 200) r = await wgReq('GET', '/api/client');
    res.status(r.status).json(r.body);
  } catch(e) { res.status(502).json({ error: 'wg-easy недоступен' }); }
});
app.post('/api/clients', auth, async (req, res) => {
  try {
    let r = await wgReq('POST', '/api/wireguard/client', { name: req.body.name });
    if (r.status === 404) r = await wgReq('POST', '/api/client', { name: req.body.name });
    res.status(r.status).json(r.body);
  } catch(e) { res.status(502).json({ error: e.message }); }
});
app.delete('/api/clients/:id', auth, async (req, res) => {
  try {
    let r = await wgReq('DELETE', '/api/wireguard/client/'+req.params.id);
    if (r.status === 404) r = await wgReq('DELETE', '/api/client/'+req.params.id);
    res.status(r.status).json({ ok: true });
  } catch(e) { res.status(502).json({ error: e.message }); }
});
app.post('/api/clients/:id/enable', auth, async (req, res) => {
  try { await wgReq('POST', '/api/wireguard/client/'+req.params.id+'/enable'); res.json({ ok:true }); }
  catch(e) { res.status(502).json({ error: e.message }); }
});
app.post('/api/clients/:id/disable', auth, async (req, res) => {
  try { await wgReq('POST', '/api/wireguard/client/'+req.params.id+'/disable'); res.json({ ok:true }); }
  catch(e) { res.status(502).json({ error: e.message }); }
});
app.get('/api/clients/:id/qr', auth, async (req, res) => {
  try {
    const r = await wgRaw('/api/wireguard/client/'+req.params.id+'/qrcode.svg');
    res.status(r.status).set('Content-Type','image/svg+xml').send(r.buf);
  } catch(e) { res.status(502).send('Error'); }
});
app.get('/api/clients/:id/config', auth, async (req, res) => {
  try {
    const r = await wgRaw('/api/wireguard/client/'+req.params.id+'/configuration');
    res.status(r.status)
      .set('Content-Type','text/plain')
      .set('Content-Disposition','attachment; filename="wg-client.conf"')
      .send(r.buf);
  } catch(e) { res.status(502).send('Error'); }
});

// ── Main panel ────────────────────────────────────────────────
app.get('/', auth, (req, res) => res.sendFile(HTML));

// ── Start server (HTTPS if cert exists, else HTTP) ────────────
const proto = fs.existsSync(CERT_KEY) && fs.existsSync(CERT_CRT) ? 'https' : 'http';
if (proto === 'https') {
  https.createServer({ key: fs.readFileSync(CERT_KEY), cert: fs.readFileSync(CERT_CRT) }, app)
    .listen(PORT, () => console.log('[Vol WG Panel] https://0.0.0.0:' + PORT));
} else {
  http.createServer(app).listen(PORT, () => console.log('[Vol WG Panel] http://0.0.0.0:' + PORT));
}
