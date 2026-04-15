# router-scripts

Чистые установщики PassWall для OpenWrt без иранской специфики (нет перезаписи
timezone/hostname/banner, нет `iam.zip` с левого домена, нет принудительных
DNS-настроек на WAN). Добавлена русификация для PassWall v2 и уменьшенный
geosite/geoip под российские CDN.

## Что внутри

| Файл | Что делает |
|---|---|
| `passwallx.sh` | Меню-лаунчер: выбор v1 / v2+RU / компактный гео / обновления / uninstall |
| `install-passwall.sh` | Чистая установка **PassWall v1** (русского локализации у v1 в feed'е нет) |
| `install-passwall2-ru.sh` | Чистая установка **PassWall v2 + `luci-i18n-passwall2-ru`** |
| `install-geo-compact.sh` | Ставит в `/usr/share/v2ray/` уменьшенные `geosite.dat` (1.6 МБ) и `geoip.dat` (389 КБ). Проверяет sha256 против `SHA256SUMS`. Содержит `category-ru` + YANDEX, AVITO, MAILRU, VK, OZON, DZEN, SBER, KINOPOISK, WILDBERRIES, RUTUBE и т.д.; `geoip:ru` + private |
| `uninstall-passwall.sh` | Чистый снос v1/v2: стопит сервисы, удаляет пакеты, возвращает stock `dnsmasq`, восстанавливает `geosite/geoip.dat` из `.bak.*`, чистит passwall-feed'ы |
| `geosite.dat`, `geoip.dat` | Сами компактные файлы, подаются через raw.githubusercontent |
| `SHA256SUMS` | sha256 для `geosite.dat` / `geoip.dat` — используется `install-geo-compact.sh` для защиты от tampering при `--no-check-certificate` fallback'е |

## Быстрый старт

На роутере:

```sh
wget -O /tmp/passwallx.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/passwallx.sh
sh /tmp/passwallx.sh
```

Или отдельные скрипты:

```sh
# PassWall v2 + русский
wget -O /tmp/i.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/install-passwall2-ru.sh
sh /tmp/i.sh

# компактный гео (без переустановки PassWall)
wget -O /tmp/g.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/install-geo-compact.sh
sh /tmp/g.sh
```

Можно переопределить базу репо (если делаешь форк):

```sh
REPO_RAW=https://raw.githubusercontent.com/someone/fork/main sh /tmp/passwallx.sh
```

## Чем отличается от
[amirhosseinchoghaei/Passwall](https://github.com/amirhosseinchoghaei/Passwall)

- **Убрано:** смена timezone на Tehran, hostname `By-AmirHossein`, подмена
  `/etc/banner`, переопределение WAN DNS, иранские rebind-домены, шант IRAN
  (`category-ir`, `direct_ip`, `direct_host`), загрузка `iam.zip` с `amir3.space`.
- **Исправлено:**
  - `ca-bundle` + `openssl-util` ставятся до любых HTTPS-операций — `wget` к
    SourceForge не падает на свежей системе
  - Если `opkg-key add` фейлится, скрипт автоматически добавляет
    `option check_signature 0` в `/etc/opkg.conf` — feed всё равно работает
  - Fallback на `wget --no-check-certificate` для `passwall.pub`
  - Пакеты ставятся одной командой (атомарно), при ошибке — выход с `die`
  - Версия OpenWrt детектится через `DISTRIB_RELEASE` → `24.10.x → 24.10`,
    отдельная ветка для SNAPSHOT (`snapshots/packages-SNAPSHOT`)
  - Бэкап `customfeeds.conf` и `/etc/config/dhcp` перед перезаписью
- **Добавлено:**
  - `luci-i18n-passwall2-ru` (есть в SourceForge-feed'е `passwall2`)
  - Уменьшенный geosite/geoip (в 40 раз меньше оригинала) — критично для
    роутеров с 256 МБ RAM

## Требования

- OpenWrt 24.10 (release) или SNAPSHOT
- Работающий интернет на WAN (без VPN/TPROXY в момент установки)
- ≥256 МБ RAM для PassWall v2 + Xray
- Права root (SSH)

## Лицензия

MIT — делайте с этим что хотите.
