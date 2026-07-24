#!/bin/bash
# SPDX-License-Identifier: MIT
# Overlay + chroot tweaks on top of tarball from mk-base-ubuntu.sh, then mk-image.sh
# Runs on host (sudo) or in Docker as root (see docker/build-rootfs.sh; UBUNTU_DOCKER_TARGETS=all).
#
# Usage:
#   ./mk-ubuntu-rootfs.sh <arm64|armhf>
# Env:
#   UBUNTU_BASE_TAR   path to ubuntu-base-lite-*-*.tar.gz (default: newest matching)
#   HOST_UID / HOST_GID   when running as root in Docker, chown ubuntu-rootfs.ext4 to host user
set -euo pipefail

runroot() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

TARGET_ROOTFS_DIR="binary"
TARGET="lite"

ARCH="${1:-}"
case "${ARCH}" in
arm64 | armhf) ;;
*)
	echo "Usage: $0 <arm64|armhf>"
	exit 1
	;;
esac

BASE_TAR="${UBUNTU_BASE_TAR:-$(ls -t "${SCRIPT_DIR}"/ubuntu-base-${TARGET}-${ARCH}-*.tar.gz 2>/dev/null | head -1)}"
if [ -z "${BASE_TAR}" ] || [ ! -f "${BASE_TAR}" ]; then
	echo "No base tarball. Run: UBUNTU_RELEASE=24.04 ./mk-base-ubuntu.sh ${ARCH}"
	exit 1
fi

echo -e "\033[47;36m Using ${BASE_TAR} \033[0m"

HOST_ARCH="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
NEED_QEMU=0
if [ "${ARCH}" != "${HOST_ARCH}" ]; then
	NEED_QEMU=1
fi

finish() {
	runroot umount "${SCRIPT_DIR}/${TARGET_ROOTFS_DIR}/dev" 2>/dev/null || true
	exit 1
}
trap finish ERR

runroot rm -rf "${TARGET_ROOTFS_DIR}"
runroot tar -xpf "${BASE_TAR}"

shopt -s nullglob
_headers=( "${SCRIPT_DIR}/../linux-headers"* )
shopt -u nullglob
if [ "${#_headers[@]}" -gt 0 ] && [ -e "${_headers[0]}" ]; then
	Image_Deb=$(basename "${_headers[0]}")
	runroot mkdir -p "${TARGET_ROOTFS_DIR}/boot/kerneldeb"
	runroot touch "${TARGET_ROOTFS_DIR}/boot/build-host"
	runroot cp -vrpf "${SCRIPT_DIR}/../${Image_Deb}" "${TARGET_ROOTFS_DIR}/boot/kerneldeb/"
	img="${Image_Deb/headers/image}"
	if [ -n "${img}" ] && [ -e "${SCRIPT_DIR}/../${img}" ]; then
		runroot cp -vrpf "${SCRIPT_DIR}/../${img}" "${TARGET_ROOTFS_DIR}/boot/kerneldeb/"
	fi
fi

runroot cp -rpf "${SCRIPT_DIR}/overlay/"* "${TARGET_ROOTFS_DIR}/"

# Optional custom login banner (plain text or ASCII art).
if [ -n "${OPENTINA_MOTD_BANNER_FILE:-}" ] && [ -f "${OPENTINA_MOTD_BANNER_FILE}" ]; then
	runroot install -D -m 0644 "${OPENTINA_MOTD_BANNER_FILE}" \
		"${TARGET_ROOTFS_DIR}/etc/opentina-motd-banner"
fi

if [ "${NEED_QEMU}" = 1 ]; then
	QEMU_BIN=""
	if [ "${ARCH}" = "arm64" ]; then
		QEMU_BIN="/usr/bin/qemu-aarch64-static"
	elif [ "${ARCH}" = "armhf" ]; then
		QEMU_BIN="/usr/bin/qemu-arm-static"
	fi
	if [ -z "${QEMU_BIN}" ] || [ ! -f "${QEMU_BIN}" ]; then
		echo "Cross-arch chroot needs ${QEMU_BIN:-qemu-user-static}."
		exit 1
	fi
	runroot cp -b "${QEMU_BIN}" "${TARGET_ROOTFS_DIR}/usr/bin/"
fi

echo -e "\033[47;36m chroot finalization \033[0m"
runroot mount -o bind /dev "${TARGET_ROOTFS_DIR}/dev"

cat <<'EOF' | runroot chroot "${TARGET_ROOTFS_DIR}" bash -se
set -e
for hd in /home/*; do
	[ -d "$hd" ] || continue
	u=$(basename "$hd")
	chown -h -R "${u}:${u}" "/home/${u}" || true
done

mount -t proc proc /proc
mount -t sysfs sys /sys

export LC_ALL=C.UTF-8
apt-get update
apt-get upgrade -y

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper 2>/dev/null || true
chmod +x /etc/rc.local 2>/dev/null || true

export APT_INSTALL="apt-get install -fy --allow-downgrades"

${APT_INSTALL} u-boot-tools logrotate

if ls /boot/kerneldeb/*.deb >/dev/null 2>&1; then
	apt-get install -fy --allow-downgrades /boot/kerneldeb/*.deb || true
fi

systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true
rm -f /lib/systemd/system/wpa_supplicant@.service 2>/dev/null || true

systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily.service 2>/dev/null || true
systemctl disable apt-daily-upgrade.service 2>/dev/null || true
systemctl disable networkd-dispatcher.service 2>/dev/null || true

systemctl mask alsa-restore.service 2>/dev/null || true
systemctl mask modprobe@drm.service 2>/dev/null || true
systemctl mask modprobe@configfs.service 2>/dev/null || true
systemctl mask modprobe@fuse.service 2>/dev/null || true
systemctl mask modprobe@efi_pstore.service 2>/dev/null || true

sed -i 's/^ProtectHostname=yes/# ProtectHostname=yes/' /usr/lib/systemd/system/systemd-udevd.service 2>/dev/null || true

if [ -e "/usr/lib/arm-linux-gnueabihf/dri" ]; then
	cd /usr/lib/arm-linux-gnueabihf/dri/
	cp kms_swrast_dri.so swrast_dri.so / 2>/dev/null || true
	rm -f /usr/lib/arm-linux-gnueabihf/dri/*.so 2>/dev/null || true
	mv /*.so /usr/lib/arm-linux-gnueabihf/dri/ 2>/dev/null || true
elif [ -e "/usr/lib/aarch64-linux-gnu/dri" ]; then
	cd /usr/lib/aarch64-linux-gnu/dri/
	cp kms_swrast_dri.so swrast_dri.so / 2>/dev/null || true
	rm -f /usr/lib/aarch64-linux-gnu/dri/*.so 2>/dev/null || true
	mv /*.so /usr/lib/aarch64-linux-gnu/dri/ 2>/dev/null || true
	rm -f /etc/profile.d/qt.sh 2>/dev/null || true
fi

rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/ 2>/dev/null || true
rm -rf /boot/* 2>/dev/null || true

umount /proc
umount /sys
EOF

runroot umount "${TARGET_ROOTFS_DIR}/dev"
trap - ERR

IMAGE_VERSION="${TARGET}" ./mk-image.sh

_owner_uid="${HOST_UID:-$(id -u)}"
_owner_gid="${HOST_GID:-$(id -g)}"
if [ "$(id -u)" -eq 0 ] && [ -n "${HOST_UID:-}" ] && [ -f "${SCRIPT_DIR}/ubuntu-rootfs.ext4" ]; then
	chown "${_owner_uid}:${_owner_gid}" "${SCRIPT_DIR}/ubuntu-rootfs.ext4" 2>/dev/null || true
elif [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && [ -f "${SCRIPT_DIR}/ubuntu-rootfs.ext4" ]; then
	sudo chown "${_owner_uid}:${_owner_gid}" "${SCRIPT_DIR}/ubuntu-rootfs.ext4" 2>/dev/null || true
fi
