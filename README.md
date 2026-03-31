# ⚡ Vol WG Panel — WireGuard VPN

Автоматический установщик WireGuard VPN с веб-панелью управления для Ubuntu 20.04 / 22.04 / 24.04.

## ✨ Возможности

- 🔐 **Первый запуск** — установка пароля прямо в браузере (bcrypt)
- 👥 **Управление клиентами** — создание, включение/отключение, удаление
- 📱 **QR-код** — сканируйте в приложении WireGuard (iOS/Android)
- 📥 **Скачать конфиг** — готовый `.conf` файл для любого устройства
- 🔄 **Auto-refresh** — список клиентов обновляется каждые 10 секунд

## 🚀 Установка

### 1. Подключитесь к серверу

```bash
ssh root@your-server-ip
```

### 2. Скачайте и запустите скрипт

```bash
curl -O https://raw.githubusercontent.com/robertmiro14-netizen/wg-panel/main/install_wg_panel.sh
sudo bash install_wg_panel.sh
```

> Скрипт автоматически:
> - Установит Node.js 20 LTS (если нужно)
> - Установит Docker (если нужно)
> - Запустит **wg-easy** в Docker (только на localhost:3051)
> - Запустит **Vol WG Panel** как systemd-сервис (порт 51821)
> - Настроит UFW (порты 22/tcp, 51820/udp, 51821/tcp)

### 3. Откройте панель в браузере

После установки откройте:

```
http://YOUR_SERVER_IP:51821
```

При **первом входе** вам предложат установить пароль — введите любой (минимум 6 символов).

---

## 📱 Как добавить клиента (пользователя VPN)

1. Войдите в панель → нажмите **"Новый клиент"**
2. Введите имя (например: `phone`, `laptop`, `office`)
3. Нажмите **"Создать"**
4. Отсканируйте QR-код в приложении WireGuard **или** скачайте `.conf` файл

### Приложения WireGuard:
| Платформа | Ссылка |
|-----------|--------|
| iOS | [App Store](https://apps.apple.com/app/wireguard/id1441195209) |
| Android | [Google Play](https://play.google.com/store/apps/details?id=com.wireguard.android) |
| Windows | [Download](https://www.wireguard.com/install/) |
| macOS | [App Store](https://apps.apple.com/app/wireguard/id1451685025) |
| Linux | `sudo apt install wireguard` |

---

## ⚙️ Технические детали

| Параметр | Значение |
|----------|----------|
| WireGuard порт | `51820/udp` |
| Веб-панель порт | `51821/tcp` |
| wg-easy (внутренний) | `127.0.0.1:3051` |
| Подсеть VPN | `10.8.0.0/24` |
| DNS | `1.1.1.1, 8.8.8.8` |
| Панель расположена | `/opt/vol-panel/` |
| Данные WireGuard | `/opt/wg-easy/` |
| Файл пароля | `/opt/vol-panel/.password` |

---

## 🛠️ Управление сервисами

```bash
# Статус
systemctl status vol-panel
docker ps | grep wg-easy

# Логи в реальном времени
journalctl -u vol-panel -f
docker logs -f wg-easy

# Перезапуск
systemctl restart vol-panel
docker restart wg-easy
```

---

## 🔄 Сброс пароля

Если забыли пароль — просто удалите файл пароля и перезапустите сервис:

```bash
rm /opt/vol-panel/.password
systemctl restart vol-panel
```

Откройте панель — снова появится форма установки пароля.

---

## 🏗️ Архитектура

```
Браузер  ──→  :51821 (Vol WG Panel / Node.js)
                     │
                     ├── GET /          → panel.html (SPA)
                     ├── GET /api/clients → wg-easy :3051
                     ├── POST /api/clients
                     ├── DELETE /api/clients/:id
                     ├── GET /api/clients/:id/qr
                     └── GET /api/clients/:id/config

wg-easy ────→ 127.0.0.1:3051 (Docker, только localhost)
WireGuard ──→ :51820/udp
```

---

## 📋 Требования

- Ubuntu **20.04 / 22.04 / 24.04**
- Доступ **root** (или sudo)
- Открытые порты: **51820/udp** и **51821/tcp**
- Минимум **512 MB RAM**
