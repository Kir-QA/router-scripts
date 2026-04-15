#!/bin/sh
# install-geo-compact.sh
# Replace /usr/share/v2ray/{geosite,geoip}.dat with our compact builds.
# Compact versions contain only the geosite categories needed for RU routing:
#   category-ru + YANDEX, AVITO, MAILRU, MAILRU-GROUP, VK, OZON, DZEN, SBER,
#   KINOPOISK, WILDBERRIES, RUTUBE (+ a few more), and geoip:ru + private.
# ~1.6 MB geosite + ~389 KB geoip (vs ~63 MB / 21 MB upstream).
#
# SHA256 of each downloaded file is verified against SHA256SUMS in the repo.
# This matters because we use --no-check-certificate as a fallback on routers
# whose CA bundle is broken — sha256 pinning protects against MITM tampering.
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

command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found (install coreutils-sha256sum or busybox)"

# fetch $1 (URL suffix) to $2 (local path), with --no-check-certificate fallback
fetch() {
    _u="$REPO_RAW/$1"; _o="$2"
    if ! wget -q -O "$_o" "$_u"; then
        warn "retrying $1 with --no-check-certificate"
        wget --no-check-certificate -q -O "$_o" "$_u" || return 1
    fi
    [ -s "$_o" ] || return 1
    return 0
}

say "target dir: $DEST"
mkdir -p "$DEST"

# ---------- fetch checksums first ----------
say "fetching SHA256SUMS"
SUMS="/tmp/.geo.$$.sums"
fetch SHA256SUMS "$SUMS" || die "cannot download SHA256SUMS"

# ---------- backup existing ----------
for f in geosite.dat geoip.dat; do
    [ -f "$DEST/$f" ] && cp -f "$DEST/$f" "$DEST/$f.bak.$(date +%s)"
done

# ---------- fetch + verify ----------
for f in geosite.dat geoip.dat; do
    expected=$(awk -v n="$f" '$2==n {print $1}' "$SUMS")
    [ -n "$expected" ] || die "no checksum for $f in SHA256SUMS"

    tmp="/tmp/.geo.$$.$f"
    say "fetching $f"
    fetch "$f" "$tmp" || die "cannot download $f"

    actual=$(sha256sum "$tmp" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        rm -f "$tmp"
        die "sha256 mismatch for $f
  expected: $expected
  actual:   $actual"
    fi
    say "sha256 ok: $f"

    mv -f "$tmp" "$DEST/$f"
    chmod 0644 "$DEST/$f"
    ls -la "$DEST/$f"
done

rm -f "$SUMS"
say "compact geo files installed and verified"

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
