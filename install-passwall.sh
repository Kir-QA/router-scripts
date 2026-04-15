#!/bin/sh
# install-passwall.sh
# Clean PassWall v1 installer for OpenWrt (stable releases + SNAPSHOT).
# No timezone / hostname / banner / Iran-specific junk.
#
# Note: passwall_luci feed only ships Chinese locale (zh-cn); no Russian
# translation exists for PassWall v1 upstream. If you need Russian UI,
# install PassWall v2 via install-passwall2-ru.sh instead.
#
# Usage on router:
#   wget -O /tmp/install-passwall.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/install-passwall.sh
#   sh /tmp/install-passwall.sh

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

say()  { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
die()  { printf '%b\n' "${RED}[X]${NC} $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
[ -f /etc/openwrt_release ] || die "not OpenWrt"

# shellcheck disable=SC1091
. /etc/openwrt_release

ARCH="${DISTRIB_ARCH:-}"
REL_RAW="${DISTRIB_RELEASE:-}"
[ -n "$ARCH" ]    || die "cannot detect DISTRIB_ARCH (empty in /etc/openwrt_release)"
[ -n "$REL_RAW" ] || die "cannot detect DISTRIB_RELEASE (empty in /etc/openwrt_release)"

if printf '%s' "$REL_RAW" | grep -qi snapshot; then
    RELEASE="SNAPSHOT"
    SOURCE="snapshots"
else
    RELEASE="${REL_RAW%.*}"              # 24.10.6 -> 24.10
    SOURCE="releases"
fi
[ -n "$RELEASE" ] || die "computed empty RELEASE from DISTRIB_RELEASE='$REL_RAW'"

BASE="https://master.dl.sourceforge.net/project/openwrt-passwall-build/${SOURCE}/packages-${RELEASE}/${ARCH}"

say "OpenWrt $REL_RAW ($ARCH); feed: $SOURCE/packages-$RELEASE"

# ---------- prerequisites ----------
say "updating base opkg lists"
opkg update >/tmp/opkg-update.log 2>&1 || warn "opkg update on base feeds had issues (continuing)"

say "ensuring ca-bundle + openssl-util"
opkg install ca-bundle openssl-util >>/tmp/opkg-update.log 2>&1 || \
    warn "ca-bundle/openssl-util install nudge; continuing"

# ---------- add SourceForge feed ----------
say "fetching passwall.pub signing key"
rm -f /tmp/passwall.pub
if ! wget -q -O /tmp/passwall.pub "https://master.dl.sourceforge.net/project/openwrt-passwall-build/passwall.pub"; then
    warn "wget fell back to --no-check-certificate"
    wget --no-check-certificate -q -O /tmp/passwall.pub \
        "https://master.dl.sourceforge.net/project/openwrt-passwall-build/passwall.pub" \
        || die "cannot download passwall.pub"
fi
[ -s /tmp/passwall.pub ] || die "passwall.pub is empty"

opkg-key add /tmp/passwall.pub >/dev/null 2>&1 || warn "opkg-key add failed (will use check_signature '0')"

say "writing /etc/opkg/customfeeds.conf (3 passwall feeds)"
[ -s /etc/opkg/customfeeds.conf ] && cp /etc/opkg/customfeeds.conf /etc/opkg/customfeeds.conf.pre-passwall
{
    echo "src/gz passwall_luci     $BASE/passwall_luci"
    echo "src/gz passwall_packages $BASE/passwall_packages"
    echo "src/gz passwall2         $BASE/passwall2"
} > /etc/opkg/customfeeds.conf

if ! opkg-key list 2>/dev/null | grep -q passwall; then
    warn "signing key not trusted — disabling check_signature for passwall feeds"
    grep -q "^option check_signature" /etc/opkg.conf || echo "option check_signature 0" >> /etc/opkg.conf
fi

say "opkg update with passwall feeds"
opkg update >/tmp/opkg-update.log 2>&1 || die "opkg update failed — see /tmp/opkg-update.log"

if ! opkg list luci-app-passwall | grep -q '^luci-app-passwall '; then
    die "passwall feed not reachable — check /tmp/opkg-update.log"
fi

# ---------- swap dnsmasq -> dnsmasq-full ----------
say "switching to dnsmasq-full (keeping /etc/config/dhcp)"
if opkg list-installed 2>/dev/null | grep -q '^dnsmasq-full '; then
    say "dnsmasq-full already installed"
else
    cp /etc/config/dhcp /etc/config/dhcp.pre-passwall 2>/dev/null || true
    opkg remove dnsmasq  >> /tmp/opkg-update.log 2>&1 || true
    opkg install dnsmasq-full >> /tmp/opkg-update.log 2>&1 || die "dnsmasq-full install failed"
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

opkg install $PKGS >> /tmp/opkg-update.log 2>&1 || die "package install failed — see /tmp/opkg-update.log"

# ---------- verify ----------
say "verifying"
[ -x /etc/init.d/passwall ]            || die "passwall init script missing"
[ -x /usr/bin/xray ] || [ -x /usr/sbin/xray ] || warn "xray binary not in PATH"

/etc/init.d/passwall enable >/dev/null 2>&1 || true

# ---------- summary ----------
say "done. Package versions:"
opkg list-installed 2>/dev/null | grep -iE '^(luci-app-passwall|xray-core|dnsmasq-full)\b' | grep -v passwall2

echo
say "LuCI:   http://$(uci get network.lan.ipaddr 2>/dev/null || echo 192.168.1.1)/cgi-bin/luci/admin/services/passwall"
say "Logs:   /tmp/opkg-update.log"
echo
warn "Next: configure nodes in LuCI \u2192 Services \u2192 PassWall \u2192 Node List, then start the service."
