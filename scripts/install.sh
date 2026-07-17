#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO="${ROOT}/repo/packages.adb"
KEY="${ROOT}/h5000m-plugins.pem"
EXPECTED_BOARD="hiveton,h5000m"
EXPECTED_REVISION="r35346-e9aa5bea9f"

board="$(ubus call system board 2>/dev/null | jsonfilter -e '@.board_name' 2>/dev/null || true)"
revision="$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.revision' 2>/dev/null || true)"

[ "${board}" = "${EXPECTED_BOARD}" ] || {
	echo "Unsupported device: ${board:-unknown}; expected ${EXPECTED_BOARD}." >&2
	exit 1
}

if [ "${revision}" != "${EXPECTED_REVISION}" ] && [ "${H5000M_PASSWALL2_FORCE:-0}" != "1" ]; then
	echo "Firmware revision mismatch: ${revision:-unknown}; expected ${EXPECTED_REVISION}." >&2
	echo "Set H5000M_PASSWALL2_FORCE=1 only after checking ABI compatibility." >&2
	exit 1
fi

[ -f "${REPO}" ] || {
	echo "Missing offline repository: ${REPO}" >&2
	exit 1
}

install -d -m 0755 /etc/apk/keys
if [ -f /etc/apk/keys/h5000m-plugins.pem ]; then
	cmp -s "${KEY}" /etc/apk/keys/h5000m-plugins.pem || {
		echo "Installed H5000M package key does not match this release." >&2
		exit 1
	}
else
	install -m 0644 "${KEY}" /etc/apk/keys/h5000m-plugins.pem
fi

apk add --repositories-file /dev/null --repository "${REPO}" \
	luci-app-passwall2 \
	luci-i18n-passwall2-zh-cn \
	xray-core \
	sing-box \
	tcping \
	v2ray-geoip \
	v2ray-geosite \
	v2ray-plugin \
	geoview

rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "PassWall2 installation completed. It remains disabled until configured in LuCI."
