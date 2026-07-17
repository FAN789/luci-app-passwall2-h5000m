#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO="${ROOT}/repo/packages.adb"
KEY="${ROOT}/h5000m-plugins.pem"
EXPECTED_BOARD="hiveton,h5000m"
EXPECTED_REVISION="r35346-e9aa5bea9f"
EXPECTED_KERNEL="6.18.38"
EXPECTED_KERNEL_ABI="93edd57b5daa2a685ba2b251f368f171"
EXPECTED_KERNEL_PACKAGE="kernel=${EXPECTED_KERNEL}~${EXPECTED_KERNEL_ABI}-r1"
DHCP_CONFIG="/etc/config/dhcp"
DHCP_BACKUP="/tmp/h5000m-passwall2-dhcp.$$.bak"

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

[ "$(uname -r)" = "${EXPECTED_KERNEL}" ] || {
	echo "Kernel mismatch: $(uname -r); expected ${EXPECTED_KERNEL}." >&2
	exit 1
}

apk info -e "${EXPECTED_KERNEL_PACKAGE}" >/dev/null 2>&1 || {
	echo "Kernel ABI mismatch; expected ${EXPECTED_KERNEL_PACKAGE}." >&2
	exit 1
}

[ -f "${REPO}" ] || {
	echo "Missing offline repository: ${REPO}" >&2
	exit 1
}

mkdir -p /etc/apk/keys
chmod 0755 /etc/apk/keys
if [ -f /etc/apk/keys/h5000m-plugins.pem ]; then
	cmp -s "${KEY}" /etc/apk/keys/h5000m-plugins.pem || {
		echo "Installed H5000M package key does not match this release." >&2
		exit 1
	}
else
	cp "${KEY}" /etc/apk/keys/h5000m-plugins.pem
	chmod 0644 /etc/apk/keys/h5000m-plugins.pem
fi

dhcp_hash="missing"
if [ -f "${DHCP_CONFIG}" ]; then
	cp -p "${DHCP_CONFIG}" "${DHCP_BACKUP}"
	dhcp_hash="$(sha256sum "${DHCP_CONFIG}" | awk '{print $1}')"
fi

rollback_dnsmasq() {
	echo "PassWall2 prerequisite verification failed; restoring compact dnsmasq." >&2
	/etc/init.d/passwall2 stop >/dev/null 2>&1 || true
	/etc/init.d/dnsmasq stop >/dev/null 2>&1 || true
	apk del dnsmasq-full >/dev/null 2>&1 || true
	apk add --repositories-file /dev/null --repository "${REPO}" dnsmasq >/dev/null 2>&1 || true
	if [ -f "${DHCP_BACKUP}" ]; then
		cp -p "${DHCP_BACKUP}" "${DHCP_CONFIG}"
	fi
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
}

apk add --repositories-file /dev/null --repository "${REPO}" \
	dnsmasq-full \
	kmod-nft-socket \
	kmod-nft-tproxy \
	luci-app-passwall2 \
	luci-i18n-passwall2-zh-cn \
	xray-core \
	sing-box \
	tcping \
	v2ray-geoip \
	v2ray-geosite \
	v2ray-plugin \
	geoview

install_valid=1
apk info -e dnsmasq-full >/dev/null 2>&1 || install_valid=0
apk list --installed 'dnsmasq*' 2>/dev/null | grep -q '^dnsmasq-[0-9]' && install_valid=0
dnsmasq --version 2>/dev/null | awk '
	/Compile time options:/ {
		for (i = 1; i <= NF; i++)
			if ($i == "nftset")
				found = 1
	}
	END { exit found ? 0 : 1 }
' || install_valid=0
modprobe nft_socket >/dev/null 2>&1 || install_valid=0
modprobe nft_tproxy >/dev/null 2>&1 || install_valid=0
test -e /sys/module/nft_socket || install_valid=0
test -e /sys/module/nft_tproxy || install_valid=0

if [ -f "${DHCP_CONFIG}" ]; then
	new_dhcp_hash="$(sha256sum "${DHCP_CONFIG}" | awk '{print $1}')"
	[ "${new_dhcp_hash}" = "${dhcp_hash}" ] || install_valid=0
fi

if [ "${install_valid}" != "1" ]; then
	rollback_dnsmasq
	rm -f "${DHCP_BACKUP}"
	exit 1
fi

/etc/init.d/dnsmasq restart >/dev/null 2>&1 || {
	rollback_dnsmasq
	rm -f "${DHCP_BACKUP}"
	exit 1
}

rm -f "${DHCP_BACKUP}"

rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "PassWall2 installation completed with dnsmasq-full and matching nftables kernel modules."
echo "PassWall2 remains disabled until configured in LuCI."
