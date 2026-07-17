#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR="${1:-${OPENWRT_SDK_DIR:-}}"
PACKAGE_BUILD_DIR="${2:-${OPENWRT_PACKAGE_BUILD_DIR:-}}"
BASE_ROOTFS="${3:-${H5000M_BASE_ROOTFS:-}}"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/.work}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
SIGNING_DIR="${H5000M_APK_SIGNING_DIR:-${HOME}/.config/h5000m-apk}"
EXPECTED_REVISION="$(tr -d '[:space:]' < "${ROOT_DIR}/config/openwrt.revision")"
RELEASE_VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
PACKAGE_LIST="${ROOT_DIR}/config/release-packages.txt"
ARCH="aarch64_cortex-a53"

usage() {
	cat >&2 <<EOF
Usage: $0 OPENWRT_SDK_DIR OPENWRT_PACKAGE_BUILD_DIR BASE_ROOTFS_SQUASHFS

The SDK and rootfs must match ${EXPECTED_REVISION}. The package build directory
must contain bin/packages/${ARCH} with compiled PassWall2 userland APKs.
EOF
	exit 1
}

[ -d "${SDK_DIR}" ] && [ -d "${PACKAGE_BUILD_DIR}" ] && [ -f "${BASE_ROOTFS}" ] || usage
[ -f "${PACKAGE_LIST}" ] || usage

for key in private-key.pem public-key.pem; do
	[ -f "${SIGNING_DIR}/${key}" ] || {
		echo "Missing signing key: ${SIGNING_DIR}/${key}" >&2
		exit 1
	}
done

actual_revision="$(sed -n 's/^REVISION:=//p' "${SDK_DIR}/include/version.mk" | head -1)"
[ "${actual_revision}" = "${EXPECTED_REVISION}" ] || {
	echo "SDK revision ${actual_revision:-unknown} does not match ${EXPECTED_REVISION}." >&2
	exit 1
}

APK="${SDK_DIR}/staging_dir/host/bin/apk"
[ -x "${APK}" ] || {
	echo "Missing host apk tool: ${APK}" >&2
	exit 1
}
command -v unsquashfs >/dev/null 2>&1 || {
	echo "unsquashfs is required for base-firmware validation." >&2
	exit 1
}

rm -rf "${WORK_DIR}" "${DIST_DIR}"
mkdir -p "${WORK_DIR}/keys" "${DIST_DIR}"

BUNDLE="${DIST_DIR}/H5000M-PassWall2-${RELEASE_VERSION}-${EXPECTED_REVISION}"
REPO_DIR="${BUNDLE}/repo"
mkdir -p "${REPO_DIR}"

copy_one_package() {
	local package="$1" search_root matches source
	case "${package}" in
		kmod-*) search_root="${SDK_DIR}/bin/targets/mediatek/filogic/packages" ;;
		*) search_root="${PACKAGE_BUILD_DIR}/bin/packages/${ARCH}" ;;
	esac

	# OpenWrt package versions begin with a digit. This avoids treating
	# coreutils-base64 as another build of the coreutils package.
	mapfile -t matches < <(find "${search_root}" -type f -name "${package}-[0-9]*.apk" -print | sort)
	[ "${#matches[@]}" -eq 1 ] || {
		echo "Expected one APK for ${package}, found ${#matches[@]} under ${search_root}." >&2
		exit 1
	}
	source="${matches[0]}"
	cp -f "${source}" "${REPO_DIR}/"
}

while IFS= read -r package; do
	case "${package}" in ''|'#'*) continue ;; esac
	copy_one_package "${package}"
done < "${PACKAGE_LIST}"

install -m 0644 "${SIGNING_DIR}/public-key.pem" "${WORK_DIR}/keys/h5000m-plugins.pem"
for package_file in "${REPO_DIR}"/*.apk; do
	"${APK}" adbsign --allow-untrusted --reset-signatures \
		--sign-key "${SIGNING_DIR}/private-key.pem" "${package_file}" >/dev/null
	"${APK}" --keys-dir "${WORK_DIR}/keys" verify "${package_file}" >/dev/null
done

(cd "${REPO_DIR}" && "${APK}" --keys-dir "${WORK_DIR}/keys" mkndx \
	--sign-key "${SIGNING_DIR}/private-key.pem" \
	--description "H5000M PassWall2 offline repository ${RELEASE_VERSION}" \
	--output packages.adb ./*.apk)

# Extracting the real base image can fail only on /dev/console in restricted
# build containers. That device is irrelevant to APK dependency simulation.
unsquashfs -q -no-exit-code -d "${WORK_DIR}/rootfs" "${BASE_ROOTFS}"
base_revision="$(sed -n "s/^DISTRIB_REVISION=['\"]\{0,1\}\([^'\"]*\).*/\1/p" \
	"${WORK_DIR}/rootfs/etc/openwrt_release" | head -1)"
[ "${base_revision}" = "${EXPECTED_REVISION}" ] || {
	echo "Base rootfs revision ${base_revision:-unknown} does not match ${EXPECTED_REVISION}." >&2
	exit 1
}

"${APK}" --root "${WORK_DIR}/rootfs" \
	--keys-dir "${WORK_DIR}/keys" \
	--repositories-file /dev/null \
	--repository "${REPO_DIR}/packages.adb" \
	add --simulate \
	luci-app-passwall2 luci-i18n-passwall2-zh-cn \
	xray-core sing-box tcping v2ray-geoip v2ray-geosite v2ray-plugin geoview \
	> "${BUNDLE}/INSTALL-SIMULATION.txt"

install -m 0755 "${ROOT_DIR}/scripts/install.sh" "${BUNDLE}/install.sh"
install -m 0755 "${ROOT_DIR}/scripts/uninstall.sh" "${BUNDLE}/uninstall.sh"
install -m 0644 "${SIGNING_DIR}/public-key.pem" "${BUNDLE}/h5000m-plugins.pem"

{
	echo "release_version=${RELEASE_VERSION}"
	echo "openwrt_revision=${EXPECTED_REVISION}"
	echo "target=mediatek/filogic"
	echo "architecture=${ARCH}"
	echo "package_count=$(find "${REPO_DIR}" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')"
	echo "base_rootfs_validation=passed"
	echo "private_configuration_included=false"
} > "${BUNDLE}/BUILD-INFO.txt"

(cd "${BUNDLE}" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
(cd "${DIST_DIR}" && tar -czf "$(basename "${BUNDLE}").tar.gz" "$(basename "${BUNDLE}")")
sha256sum "${DIST_DIR}/$(basename "${BUNDLE}").tar.gz" > "${DIST_DIR}/$(basename "${BUNDLE}").tar.gz.sha256"

echo "Release bundle: ${DIST_DIR}/$(basename "${BUNDLE}").tar.gz"
