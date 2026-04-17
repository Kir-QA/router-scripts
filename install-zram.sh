#!/bin/sh
# install-zram.sh
# Install and configure zram swap on OpenWrt.
# Uses lz4 compression (fast, low CPU on ARM) with 128 MB swap size.
# Critical for routers with ≤256 MB RAM running xray — prevents OOM kills.
#
# Usage:
#   wget -O /tmp/install-zram.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/install-zram.sh
#   sh /tmp/install-zram.sh

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

say()  { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
die()  { printf '%b\n' "${RED}[X]${NC} $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
[ -f /etc/openwrt_release ] || die "not OpenWrt"

ZRAM_SIZE_MB=128
ZRAM_ALGO="lz4"

RAM_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
RAM_MB=$((RAM_KB / 1024))
say "RAM: ${RAM_MB} MB"

# auto-size: half of RAM, capped at 128 MB
if [ "$RAM_MB" -le 128 ]; then
    ZRAM_SIZE_MB=$((RAM_MB / 2))
    say "small RAM detected — zram size reduced to ${ZRAM_SIZE_MB} MB"
fi

# ---------- check if already active ----------
if grep -qs zram /proc/swaps; then
    say "zram swap already active:"
    grep zram /proc/swaps
    echo
    printf "Reconfigure? [y/N]: "
    read -r ans
    case "$ans" in y|Y|yes|YES) ;; *) echo "keeping current config"; exit 0 ;; esac
    say "stopping current zram swap"
    /etc/init.d/zram stop >/dev/null 2>&1 || true
fi

# ---------- install packages ----------
say "updating opkg"
opkg update >/tmp/opkg-zram.log 2>&1 || warn "opkg update had issues (continuing)"

PKGS="kmod-zram zram-swap swap-utils"

# lz4 needs kernel module
if [ "$ZRAM_ALGO" = "lz4" ]; then
    PKGS="$PKGS kmod-lib-lz4"
fi

say "installing: $PKGS"
# shellcheck disable=SC2086
opkg install $PKGS >>/tmp/opkg-zram.log 2>&1 || die "package install failed — see /tmp/opkg-zram.log"

# ---------- configure via uci ----------
say "configuring: algo=$ZRAM_ALGO, size=${ZRAM_SIZE_MB} MB"
uci set system.@system[0].zram_comp_algo="$ZRAM_ALGO"
uci set system.@system[0].zram_size_mb="$ZRAM_SIZE_MB"
uci commit system

# ---------- start ----------
say "starting zram swap"
/etc/init.d/zram start 2>/dev/null

sleep 1

# ---------- verify ----------
if grep -qs zram /proc/swaps; then
    say "zram swap active:"
    cat /proc/swaps
    echo

    algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
    disksize=$(awk '{printf "%.0f", $1/1024/1024}' /sys/block/zram0/disksize 2>/dev/null)
    say "algorithm: $algo"
    say "disk size: ${disksize} MB"

    echo
    say "memory after zram:"
    free
else
    die "zram swap not active — check /tmp/opkg-zram.log"
fi

echo
say "done. zram is persistent across reboots via /etc/init.d/zram."
