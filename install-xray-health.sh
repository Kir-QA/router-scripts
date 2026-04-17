#!/bin/sh
# install-xray-health.sh
# Installs xray health monitor: daemon + LED indicator + LuCI overview widget.
#
# What it does:
#   - /usr/share/passwall/xray-health.sh   — daemon (30s loop), writes /tmp/xray-health.json
#   - /etc/init.d/xray-health              — procd init (enabled on boot)
#   - /www/luci-static/resources/view/status/include/15_xray.js — LuCI overview widget
#   - /usr/share/rpcd/acl.d/xray-health.json — rpcd ACL so LuCI can read the JSON
#
# LED scheme (amber:net):
#   xray running, no OOM  → LED off
#   xray running, OOM > 0 → LED on (steady)
#   xray dead              → LED blinks (200ms on/off)
#
# Usage:
#   wget -O /tmp/install-xray-health.sh https://raw.githubusercontent.com/Kir-QA/router-scripts/main/install-xray-health.sh
#   sh /tmp/install-xray-health.sh

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

say()  { printf '%b\n' "${GREEN}[+]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
die()  { printf '%b\n' "${RED}[X]${NC} $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
[ -f /etc/openwrt_release ] || die "not OpenWrt"

# ---------- 1. xray-health.sh daemon ----------
say "installing /usr/share/passwall/xray-health.sh"
mkdir -p /usr/share/passwall
cat > /usr/share/passwall/xray-health.sh <<'DAEMON'
#!/bin/sh
HEALTH_FILE="/tmp/xray-health.json"
LED_PATH="/sys/class/leds/amber:net"
INTERVAL=30

led_off() {
    echo none  > "$LED_PATH/trigger"   2>/dev/null
    echo 0     > "$LED_PATH/brightness" 2>/dev/null
}
led_on() {
    echo none  > "$LED_PATH/trigger"   2>/dev/null
    echo 1     > "$LED_PATH/brightness" 2>/dev/null
}
led_blink() {
    echo timer > "$LED_PATH/trigger"   2>/dev/null
    echo 200   > "$LED_PATH/delay_on"  2>/dev/null
    echo 200   > "$LED_PATH/delay_off" 2>/dev/null
}

while true; do
    now=$(date +%s)
    pid=$(pgrep -f "passwall/bin/xray" 2>/dev/null | head -1)

    if [ -n "$pid" ]; then
        running="true"
        uptime_sys=$(awk '{printf "%d", $1}' /proc/uptime)
        start_tick=$(awk '{print $22}' /proc/$pid/stat 2>/dev/null)
        if [ -n "$start_tick" ]; then
            start_sec=$((start_tick / 100))
            up_sec=$((uptime_sys - start_sec))
            [ "$up_sec" -lt 0 ] && up_sec=0
        else
            up_sec=0
        fi
        rss_pages=$(awk '{print $24}' /proc/$pid/stat 2>/dev/null)
        rss_kb=$(( ${rss_pages:-0} * 4 ))
    else
        running="false"; pid=""; up_sec=0; rss_kb=0
    fi

    oom_kills=$(dmesg 2>/dev/null | grep -c "Out of memory.*xray")

    restarts=0
    for f in /tmp/etc/passwall/script_rstats/*.count; do
        [ -f "$f" ] || continue
        read cnt < "$f" 2>/dev/null
        restarts=$((restarts + ${cnt:-0}))
    done

    mem_avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)

    tmp="${HEALTH_FILE}.$$"
    cat > "$tmp" <<-ENDJSON
{"running":$running,"pid":${pid:-0},"uptime_sec":$up_sec,"oom_kills":$oom_kills,"restarts":$restarts,"mem_rss_kb":$rss_kb,"mem_avail_kb":${mem_avail:-0},"last_check":$now}
ENDJSON
    mv -f "$tmp" "$HEALTH_FILE"

    if [ "$running" = "false" ]; then
        led_blink
    elif [ "$oom_kills" -gt 0 ]; then
        led_on
    else
        led_off
    fi

    sleep $INTERVAL
done
DAEMON
chmod +x /usr/share/passwall/xray-health.sh

# ---------- 2. procd init script ----------
say "installing /etc/init.d/xray-health"
cat > /etc/init.d/xray-health <<'INIT'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/share/passwall/xray-health.sh
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 0
    procd_set_param stderr 1
    procd_close_instance
}
INIT
chmod +x /etc/init.d/xray-health

# ---------- 3. LuCI overview widget ----------
say "installing /www/luci-static/resources/view/status/include/15_xray.js"
mkdir -p /www/luci-static/resources/view/status/include
cat > /www/luci-static/resources/view/status/include/15_xray.js <<'LUCI'
'use strict';
'require baseclass';
'require fs';

return baseclass.extend({
	title: _('Xray Health'),

	load: function() {
		return L.resolveDefault(fs.read('/tmp/xray-health.json'), '{}');
	},

	render: function(jsonStr) {
		var data;
		try { data = JSON.parse(jsonStr); } catch(e) { data = {}; }

		var running   = data.running || false;
		var pid       = data.pid || 0;
		var uptimeSec = data.uptime_sec || 0;
		var oomKills  = data.oom_kills || 0;
		var restarts  = data.restarts || 0;
		var rssKb     = data.mem_rss_kb || 0;
		var availKb   = data.mem_avail_kb || 0;
		var lastCheck = data.last_check || 0;

		var uptimeStr = '-';
		if (running && uptimeSec > 0) {
			var h = Math.floor(uptimeSec / 3600);
			var m = Math.floor((uptimeSec % 3600) / 60);
			var s = uptimeSec % 60;
			uptimeStr = '%dh %dm %ds'.format(h, m, s);
		}

		var fmtKb = function(kb) {
			if (kb <= 0) return '-';
			return kb >= 1024 ? '%.1f MB'.format(kb / 1024) : '%d KB'.format(kb);
		};

		var statusHtml = running
			? '<span style="color:#2dce89;font-weight:bold">&#x25cf; Running</span>'
			: '<span style="color:#fb6340;font-weight:bold">&#x25cf; NOT RUNNING</span>';

		var oomHtml = oomKills === 0
			? '<span style="color:#2dce89">0</span>'
			: oomKills <= 2
				? '<span style="color:#fb9a05;font-weight:bold">' + oomKills + '</span>'
				: '<span style="color:#fb6340;font-weight:bold">' + oomKills + '</span>';

		var restartHtml = restarts === 0
			? '<span style="color:#2dce89">0</span>'
			: '<span style="color:#fb9a05;font-weight:bold">' + restarts + '</span>';

		var staleWarning = '';
		if (lastCheck > 0) {
			var age = Math.floor(Date.now() / 1000) - lastCheck;
			if (age > 90) staleWarning = ' <span style="color:#fb6340">(stale: %ds ago)</span>'.format(age);
		}

		var fields = [
			_('Status'),        statusHtml + staleWarning,
			_('PID'),           running ? String(pid) : '-',
			_('Uptime'),        uptimeStr,
			_('OOM Kills'),     oomHtml,
			_('Restarts'),      restartHtml,
			_('RSS'),           fmtKb(rssKb),
			_('Mem Available'), fmtKb(availKb)
		];

		var table = E('table', { 'class': 'table' });
		for (var i = 0; i < fields.length; i += 2) {
			var row = E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
				E('td', { 'class': 'td left' })
			]);
			row.lastChild.innerHTML = (fields[i+1] != null) ? fields[i+1] : '?';
			table.appendChild(row);
		}
		return table;
	}
});
LUCI

# ---------- 4. rpcd ACL ----------
say "installing /usr/share/rpcd/acl.d/xray-health.json"
cat > /usr/share/rpcd/acl.d/xray-health.json <<'ACL'
{
	"luci-mod-status-index": {
		"description": "Allow reading xray health status",
		"read": {
			"file": {
				"/tmp/xray-health.json": ["read"]
			}
		}
	}
}
ACL

# ---------- 5. restart rpcd, enable + start daemon ----------
say "restarting rpcd (for ACL)"
/etc/init.d/rpcd restart >/dev/null 2>&1 || warn "rpcd restart failed"

say "enabling xray-health on boot"
/etc/init.d/xray-health enable 2>/dev/null

# stop old instance if any
/etc/init.d/xray-health stop >/dev/null 2>&1 || true
say "starting xray-health daemon"
/etc/init.d/xray-health start 2>/dev/null

sleep 3
if [ -f /tmp/xray-health.json ]; then
    say "health JSON created:"
    cat /tmp/xray-health.json
    echo
else
    warn "/tmp/xray-health.json not found — check /etc/init.d/xray-health status"
fi

say "done."
say "LuCI overview: http://$(uci get network.lan.ipaddr 2>/dev/null || echo 192.168.1.1)/"
warn "LED amber:net: off=ok, steady=OOM happened, blink=xray dead"
