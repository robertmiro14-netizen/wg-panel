# ⚡ WireGuard VPN + Web Panel

Автоматический установщик WireGuard VPN с веб-панелью управления для Ubuntu 20.04 / 22.04 / 24.04.

## ✨ Возможности

- 🔐 **Первый запуск** — установка пароля прямо в браузере
- 👥 **Управление клиентами** — создание и удаление пользователей VPN
- 📱 **QR-код** — сканируйте в приложении WireGuard (iOS/Android)
- 📥 **Скачать конфиг** — готовый `.conf` файл для любого устройства
- 📊 **Dashboard** — статус сервера, нагрузка, память, uptime
- 📡 **Статус WireGuard** — вывод `wg show` в реальном времени
- 🔄 **Перезапуск** WireGuard одной кнопкой

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
> - Установит WireGuard и все зависимости
> - Установит Node.js 20 LTS (если нужно)
> - Создаст ключи сервера
> - Запустит WireGuard и веб-панель как systemd-сервисы
> - Настроит UFW (порты 51820/udp и 8080/tcp)

### 3. Откройте панель в браузере

После установки откройте:

```
http://YOUR_SERVER_IP:8080
```

При **первом входе** вам предложат установить пароль — введите любой (минимум 6 символов).

---

## 📱 Как добавить клиента (пользователя VPN)

1. Войдите в панель → **Клиенты** → **+ Добавить клиента**
2. Введите имя (например: `phone`, `laptop`, `office`)
3. Нажмите **Создать клиента**
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
| Веб-панель порт | `8080/tcp` |
| Подсеть VPN | `10.8.0.0/24` |
| DNS | `1.1.1.1, 8.8.8.8` |
| Панель расположена | `/opt/wg-panel/` |
| Конфиги клиентов | `/etc/wireguard/clients/` |

---

## 🛠️ Управление сервисами

```bash
# Статус
systemctl status wg-panel
systemctl status wg-quick@wg0

# Логи в реальном времени
journalctl -u wg-panel -f
journalctl -u wg-quick@wg0 -f

# Перезапуск
systemctl restart wg-panel
systemctl restart wg-quick@wg0
```

---

## 🔄 Сброс пароля

Если забыли пароль — просто удалите файл пароля и перезайдите в браузер:

```bash
rm /opt/wg-panel/.password
systemctl restart wg-panel
```

Откройте панель — снова появится форма установки пароля.

---

## 🖥️ Скриншоты

| Первая настройка | Dashboard | Клиенты | QR-код |
|:---:|:---:|:---:|:---:|
| Установка пароля | Статистика сервера | Список пользователей | Сканирование в WG |

---

## 📋 Требования

- Ubuntu **20.04 / 22.04 / 24.04**
- Доступ **root** (или sudo)
- Открытые порты: **51820/udp** и **8080/tcp**
- Минимум **512 MB RAM**
