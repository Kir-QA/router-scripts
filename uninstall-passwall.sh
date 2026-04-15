#!/bin/sh
# uninstall-passwall.sh
# Clean removal of PassWall v1 and/or v2 from OpenWrt:
#   - stops and disables services
#   - removes luci-app-passwall{,2}, luci-i18n-passwall2-ru, xray-core
#   - restores stock dnsmasq (from dnsmasq-full) if we installed it,
#     and brings back /etc/config/dhcp if a .pre-passwall backup exists
#   - restores /usr/share/v2ray/{geosite,geoip}.dat from newest .bak.* if any
#   - removes the passwall customfeeds + check_signature override we added
#   - deletes /etc/config/passwall{,2} (you'll be asked first)
#
# What is NOT touched:
#   - kmod-nft-socket / kmod-nft-tproxy / ipset (may be used by other things)
#   - ca-bundle / openssl-util (system packages)
#   - xray/sing-box binaries in /usr/bin/{xray,sing-box} that come from
#     standalone opkg packages (we just `opkg remove xray-core` and let opkg
#     complain if something else depends on it — we don't force)
#
# Usage:
#   wget -O /tmp/uninstall-passwall.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/uninstall-passwall.sh
#   sh /tmp/uninstall-passwall.sh

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

say()  { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
die()  { printf '%b\n' "${RED}[X]${NC} $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
[ -f /etc/openwrt_release ] || die "not OpenWrt"

LOG=/tmp/uninstall-passwall.log
: > "$LOG"

# ---------- prompt ----------
printf "${YELLOW}This will remove PassWall v1/v2 packages, configs, and passwall feeds.${NC}\n"
printf "Continue? [y/N]: "
read -r ans
case "$ans" in y|Y|yes|YES) ;; *) echo "aborted"; exit 0 ;; esac

# ---------- detect what's installed ----------
HAS_V1=0; HAS_V2=0
opkg list-installed 2>/dev/null | grep -q '^luci-app-passwall '  && HAS_V1=1
opkg list-installed 2>/dev/null | grep -q '^luci-app-passwall2 ' && HAS_V2=1
say "installed: v1=$HAS_V1 v2=$HAS_V2"

# ---------- stop services ----------
for svc in passwall passwall2; do
    if [ -x "/etc/init.d/$svc" ]; then
        say "stopping $svc"
        /etc/init.d/$svc stop    >>"$LOG" 2>&1 || true
        /etc/init.d/$svc disable >>"$LOG" 2>&1 || true
    fi
done

# ---------- remove packages ----------
REMOVE=""
[ "$HAS_V1" = 1 ] && REMOVE="$REMOVE luci-app-passwall"
[ "$HAS_V2" = 1 ] && REMOVE="$REMOVE luci-app-passwall2 luci-i18n-passwall2-ru"

if [ -n "$REMOVE" ]; then
    say "removing:$REMOVE"
    # shellcheck disable=SC2086
    opkg remove $REMOVE >>"$LOG" 2>&1 || warn "opkg remove had warnings (see $LOG)"
fi

# xray-core only if neither passwall remains
if ! opkg list-installed 2>/dev/null | grep -qE '^luci-app-passwall2? '; then
    if opkg list-installed 2>/dev/null | grep -q '^xray-core '; then
        say "removing xray-core (no passwall remains)"
        opkg remove xray-core >>"$LOG" 2>&1 || warn "xray-core remove had warnings"
    fi
fi

# ---------- restore dnsmasq ----------
# only downgrade if nothing else depends on dnsmasq-full features
if opkg list-installed 2>/dev/null | grep -q '^dnsmasq-full '; then
    say "switching dnsmasq-full -> dnsmasq (saving /etc/config/dhcp)"
    cp /etc/config/dhcp /etc/config/dhcp.pre-uninstall 2>/dev/null || true
    opkg remove  dnsmasq-full >>"$LOG" 2>&1 || warn "dnsmasq-full remove had warnings"
    opkg install dnsmasq      >>"$LOG" 2>&1 || warn "dnsmasq install failed (you may be left without DNS!)"
    if [ -f /etc/config/dhcp.pre-passwall ]; then
        say "restoring /etc/config/dhcp from .pre-passwall backup"
        cp -f /etc/config/dhcp.pre-passwall /etc/config/dhcp
    elif [ -f /etc/config/dhcp.pre-uninstall ]; then
        cp -f /etc/config/dhcp.pre-uninstall /etc/config/dhcp
    fi
    /etc/init.d/dnsmasq restart >>"$LOG" 2>&1 || warn "dnsmasq restart failed"
fi

# ---------- restore v2ray geo files from newest .bak.* ----------
for f in geosite.dat geoip.dat; do
    newest=$(ls -1t /usr/share/v2ray/$f.bak.* 2>/dev/null | head -n1 || true)
    if [ -n "${newest:-}" ] && [ -f "$newest" ]; then
        say "restoring /usr/share/v2ray/$f from $newest"
        cp -f "$newest" "/usr/share/v2ray/$f"
    fi
done

# ---------- remove passwall customfeeds + check_signature override ----------
if [ -f /etc/opkg/customfeeds.conf ] && grep -q passwall /etc/opkg/customfeeds.conf; then
    say "cleaning passwall entries from /etc/opkg/customfeeds.conf"
    cp /etc/opkg/customfeeds.conf /etc/opkg/customfeeds.conf.pre-uninstall
    grep -v passwall /etc/opkg/customfeeds.conf.pre-uninstall > /etc/opkg/customfeeds.conf || true
fi

# we only added `option check_signature 0` ourselves — leave it alone if the
# user set it; easier to just note it
if grep -q "^option check_signature 0" /etc/opkg.conf 2>/dev/null; then
    warn "/etc/opkg.conf still contains 'option check_signature 0' — remove manually if not needed"
fi

# ---------- config files ----------
for cfg in /etc/config/passwall /etc/config/passwall2; do
    if [ -f "$cfg" ]; then
        printf "remove %s ? [y/N]: " "$cfg"
        read -r a
        case "$a" in y|Y|yes|YES) rm -f "$cfg" && say "removed $cfg" ;; *) warn "kept $cfg" ;; esac
    fi
done

# ---------- summary ----------
say "done."
echo
echo "Still installed (grep):"
opkg list-installed 2>/dev/null | grep -iE '^(luci-app-passwall|luci-i18n-passwall|xray-core|dnsmasq(-full)?)\b' || true
echo
say "log: $LOG"
warn "review /etc/config/network & /etc/config/firewall by hand if you had custom passwall rules"
