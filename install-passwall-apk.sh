#!/bin/sh
# install-passwall-apk.sh
# Clean PassWall v1 installer for OpenWrt SNAPSHOT (APK package manager).
# For OpenWrt 25.x and master branch where opkg has been replaced by apk.
#
# Tested: OpenWrt SNAPSHOT r34273 on Xiaomi Redmi Router AX6S (MT7622).
#
# Usage on router:
#   wget -O /tmp/install-passwall-apk.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/install-passwall-apk.sh
#   sh /tmp/install-passwall-apk.sh

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

say()  { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
die()  { printf '%b\n' "${RED}[X]${NC} $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
[ -f /etc/openwrt_release ] || die "not OpenWrt"
command -v apk >/dev/null 2>&1 || die "apk not found — this script is for OpenWrt SNAPSHOT/25.x; for 24.10 use install-passwall.sh"

# shellcheck disable=SC1091
. /etc/openwrt_release

ARCH="${DISTRIB_ARCH:-}"
[ -n "$ARCH" ] || die "cannot detect DISTRIB_ARCH"

# passwall feed URLs (SNAPSHOT only — releases path differs)
BASE="https://master.dl.sourceforge.net/project/openwrt-passwall-build/snapshots/packages/${ARCH}"

say "OpenWrt $DISTRIB_RELEASE ($ARCH)"
say "Feed base: $BASE"

# ---------- prerequisites ----------
say "updating base apk repos"
apk update >/tmp/apk-update.log 2>&1 || warn "apk update on base feeds had issues (continuing)"

say "ensuring ca-bundle + openssl-util"
apk add ca-bundle openssl-util >>/tmp/apk-update.log 2>&1 || \
    warn "ca-bundle/openssl-util install nudge; continuing"

# ---------- add passwall feeds ----------
say "writing /etc/apk/repositories.d/passwall.list (3 passwall feeds)"
[ -s /etc/apk/repositories.d/passwall.list ] && \
    cp /etc/apk/repositories.d/passwall.list /etc/apk/repositories.d/passwall.list.pre

cat > /etc/apk/repositories.d/passwall.list <<EOF
${BASE}/passwall_luci/packages.adb
${BASE}/passwall_packages/packages.adb
${BASE}/passwall2/packages.adb
EOF

# Note: passwall .apk packages are not signed for apk — must use --allow-untrusted
say "apk update --allow-untrusted (passwall feeds are untrusted)"
apk update --allow-untrusted >/tmp/apk-update.log 2>&1 || \
    die "apk update failed — see /tmp/apk-update.log"

if ! apk search --allow-untrusted luci-app-passwall 2>/dev/null | grep -q '^luci-app-passwall'; then
    die "passwall feed not reachable — check /tmp/apk-update.log"
fi

# ---------- swap dnsmasq -> dnsmasq-full ----------
say "switching to dnsmasq-full (keeping /etc/config/dhcp)"
if apk list -I 2>/dev/null | grep -q '^dnsmasq-full-'; then
    say "dnsmasq-full already installed"
else
    cp /etc/config/dhcp /etc/config/dhcp.pre-passwall 2>/dev/null || true
    apk add --allow-untrusted dnsmasq-full >>/tmp/apk-update.log 2>&1 \
        || die "dnsmasq-full install failed"
    [ -f /etc/config/dhcp.pre-passwall ] && cp -f /etc/config/dhcp.pre-passwall /etc/config/dhcp
fi

# ---------- install PassWall v1 + deps ----------
say "installing luci-app-passwall + xray-core + kernel modules"
PKGS="luci-app-passwall \
      xray-core \
      kmod-nft-socket \
      kmod-nft-tproxy \
      ipset \
      unzip \
      ca-bundle"

# kmod-nft-fullcone не всегда есть в SNAPSHOT — пропускаем если нет
# shellcheck disable=SC2086
apk add --allow-untrusted $PKGS >>/tmp/apk-update.log 2>&1 \
    || die "package install failed — see /tmp/apk-update.log"

# ---------- verify ----------
say "verifying"
[ -x /etc/init.d/passwall ]            || die "passwall init script missing"
[ -x /usr/bin/xray ] || [ -x /usr/sbin/xray ] || warn "xray binary not in PATH"

/etc/init.d/passwall enable >/dev/null 2>&1 || true
/etc/init.d/passwall start  >/dev/null 2>&1 || true

# ---------- summary ----------
say "done. Installed packages:"
apk list -I 2>/dev/null | grep -iE '^(luci-app-passwall|xray-core|chinadns-ng|dns2socks|tcping|dnsmasq-full)' | head -10

echo
say "LuCI:   http://$(uci get network.lan.ipaddr 2>/dev/null || echo 192.168.1.1)/cgi-bin/luci/admin/services/passwall"
say "Logs:   /tmp/apk-update.log,  /tmp/log/passwall.log"
echo
warn "Next: configure nodes in LuCI → Services → PassWall → Node List, then start the service."
