#!/bin/sh
# passwallx.sh
# Menu launcher for PassWall installers (v1 / v2-ru) + compact geo files.
# Clean port of amirhosseinchoghaei/Passwall passwallx.sh:
#   - no timezone / hostname / banner overrides
#   - no Iran-specific configs
#   - no iam.zip fetch from amir3.space
#   - v2 installer bundles Russian LuCI locale
#   - adds option to install our compact geosite/geoip.dat
#
# Usage on router:
#   wget -O /tmp/passwallx.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/passwallx.sh
#   sh /tmp/passwallx.sh
#
# Override repo base if forked (no trailing slash):
#   REPO_RAW=https://raw.githubusercontent.com/someone/fork/main sh /tmp/passwallx.sh

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/Kir-QA/router-scripts/main}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
[ -f /etc/openwrt_release ] || { echo "not OpenWrt" >&2; exit 1; }

# detect package manager (apk for SNAPSHOT/25.x, opkg for 24.10)
if command -v apk >/dev/null 2>&1; then
    PM=apk
elif command -v opkg >/dev/null 2>&1; then
    PM=opkg
else
    PM=unknown
fi

# shellcheck disable=SC1091
. /etc/openwrt_release

clear
printf '%b' "${YELLOW}"
cat <<'BANNER'
 _____                              _ _
|  __ \                            | | |
| |__) |_ _ ___ _____      ____ _ | | |
|  ___/ _` / __/ __\ \ /\ / / _` || | |
| |  | (_| \__ \__ \\ V  V / (_| || | |
|_|   \__,_|___/___/ \_/\_/ \__,_||_|_|    router-scripts (clean, RU)

BANNER
printf '%b' "${NC}"

echo "Router:  $(cat /tmp/sysinfo/model 2>/dev/null || echo unknown)"
echo "OpenWrt: $DISTRIB_RELEASE ($DISTRIB_ARCH)  pm=$PM"
echo "Repo:    $REPO_RAW"
echo

# running-state hints
[ -x /etc/init.d/passwall ]     && echo " ✓ PassWall v1 is installed"
[ -x /etc/init.d/passwall2 ]    && echo " ✓ PassWall v2 is installed"
[ -x /etc/init.d/xray-health ]  && echo " ✓ Xray health monitor is running"
grep -qs zram /proc/swaps       && echo " ✓ zram swap is active"
echo

# choose v1 installer based on package manager
if [ "$PM" = "apk" ]; then
    V1_SCRIPT="install-passwall-apk.sh"
else
    V1_SCRIPT="install-passwall.sh"
fi

printf "${YELLOW} 1.${NC} ${CYAN}Install PassWall v1${NC}  (auto: %s)\n" "$V1_SCRIPT"
printf "${YELLOW} 2.${NC} ${CYAN}Install PassWall v2 + русский язык${NC}   (recommended, requires >256 MB RAM)\n"
printf "${YELLOW} 3.${NC} ${CYAN}Install compact geosite/geoip (RU-focused)${NC}\n"
printf "${YELLOW} 4.${NC} ${YELLOW}Update PassWall v1${NC}\n"
printf "${YELLOW} 5.${NC} ${YELLOW}Update PassWall v2${NC}\n"
printf "${YELLOW} 6.${NC} ${RED}Uninstall PassWall v1/v2 + restore dnsmasq${NC}\n"
printf "${YELLOW} 7.${NC} ${CYAN}Install Xray health monitor (LuCI widget + LED)${NC}\n"
printf "${YELLOW} 8.${NC} ${CYAN}Install zram swap (lz4, 128 MB)${NC}\n"
printf "${YELLOW} 0.${NC} ${RED}Exit${NC}\n"
echo

printf " Select option: "
read -r choice

run_remote() {
    # $1 = script filename
    f="$1"
    echo "Fetching $REPO_RAW/$f"
    rm -f "/tmp/$f"
    if ! wget -q -O "/tmp/$f" "$REPO_RAW/$f"; then
        echo "wget failed"; return 1
    fi
    chmod +x "/tmp/$f"
    sh "/tmp/$f"
}

pm_install() {
    if [ "$PM" = "apk" ]; then
        apk update --allow-untrusted && apk add --allow-untrusted "$@"
    else
        opkg update && opkg install "$@"
    fi
}

case "$choice" in
    1) run_remote "$V1_SCRIPT"             ;;
    2) run_remote install-passwall2-ru.sh  ;;
    3) run_remote install-geo-compact.sh   ;;
    4) pm_install luci-app-passwall        ;;
    5) pm_install luci-app-passwall2       ;;
    6) run_remote uninstall-passwall.sh    ;;
    7) run_remote install-xray-health.sh   ;;
    8) run_remote install-zram.sh          ;;
    0) echo "bye"; exit 0                  ;;
    *) echo "invalid option"; exit 1       ;;
esac
