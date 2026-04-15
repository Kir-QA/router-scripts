#!/bin/sh
# install-geo-compact.sh
# Replace /usr/share/v2ray/{geosite,geoip}.dat with our compact builds.
# Compact versions contain only the geosite categories needed for RU routing:
#   category-ru + YANDEX, AVITO, MAILRU, MAILRU-GROUP, VK, OZON, DZEN, SBER,
#   KINOPOISK, WILDBERRIES, RUTUBE (+ a few more), and geoip:ru + private.
# ~1.6 MB geosite + ~389 KB geoip (vs ~63 MB / 21 MB upstream).
#
# Smaller files = faster load, less RAM for Xray on 256 MB routers.
#
# Usage on router (needs internet to fetch from our GitHub):
#   wget -O /tmp/install-geo-compact.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/install-geo-compact.sh
#   sh /tmp/install-geo-compact.sh
#
# Override base URL if repo differs:
#   REPO_RAW=https://raw.githubusercontent.com/someone/otherrepo/main sh ...

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

say()  { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
die()  { printf '%b\n' "${RED}[X]${NC} $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/Kir-QA/router-scripts/main}"
DEST="/usr/share/v2ray"

say "target dir: $DEST"
mkdir -p "$DEST"

for f in geosite.dat geoip.dat; do
    [ -f "$DEST/$f" ] && cp -f "$DEST/$f" "$DEST/$f.bak.$(date +%s)"
done

for f in geosite.dat geoip.dat; do
    say "fetching $f from $REPO_RAW/$f"
    tmp="/tmp/.geo.$$.$f"
    if ! wget -q -O "$tmp" "$REPO_RAW/$f"; then
        warn "retrying with --no-check-certificate"
        wget --no-check-certificate -q -O "$tmp" "$REPO_RAW/$f" \
            || die "cannot download $f"
    fi
    [ -s "$tmp" ] || die "$f downloaded empty"
    mv -f "$tmp" "$DEST/$f"
    chmod 0644 "$DEST/$f"
    ls -la "$DEST/$f"
done

say "compact geo files installed"

# reload xray via passwall[2]
for svc in passwall2 passwall; do
    if [ -x "/etc/init.d/$svc" ]; then
        if pgrep -f "etc/${svc}/bin/xray" >/dev/null 2>&1; then
            say "restarting $svc so xray re-reads geo files"
            /etc/init.d/$svc reload >/dev/null 2>&1 || /etc/init.d/$svc restart >/dev/null 2>&1 || true
        fi
        break
    fi
done

say "done. verify with:  ls -la $DEST"
