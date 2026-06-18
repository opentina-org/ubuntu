#!/bin/bash
# SPDX-License-Identifier: MIT
# Download ubuntu-base (official), chroot install lite packages, pack ubuntu-base-lite-<ARCH>-<date>.tar.gz
# Runs on host (sudo) or in Docker as root (see docker/build-rootfs.sh).
#
# Usage:
#   ./mk-base-ubuntu.sh <arm64|armhf>
# Env:
#   UBUNTU_RELEASE=22.04|24.04   (default 24.04)
#   UBUNTU_BASE_VERSION          (e.g. 24.04.4, point release in tarball name; defaults per release)
#   UBUNTU_BASE_URL              (override full tarball URL if mirror layout changes)
#   HOST_UID / HOST_GID          when running as root in Docker, chown tarball to host user
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

TARGET="lite"
TARGET_ROOTFS_DIR="binary"

ARCH="${1:-}"
case "${ARCH}" in
arm64 | armhf) ;;
*)
	echo "Usage: $0 <arm64|armhf>"
	exit 1
	;;
esac

UBUNTU_RELEASE="${UBUNTU_RELEASE:-24.04}"
case "${UBUNTU_RELEASE}" in
22.04)
	CODENAME=jammy
	DEFAULT_POINT="${UBUNTU_BASE_VERSION:-22.04.5}"
	;;
24.04)
	CODENAME=noble
	DEFAULT_POINT="${UBUNTU_BASE_VERSION:-24.04.4}"
	;;
*)
	echo "Unsupported UBUNTU_RELEASE=${UBUNTU_RELEASE} (use 22.04 or 24.04)"
	exit 1
	;;
esac

TARBALL_NAME="ubuntu-base-${DEFAULT_POINT}-base-${ARCH}.tar.gz"
BASE_URL="${UBUNTU_BASE_URL:-http://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_RELEASE}/release/${TARBALL_NAME}}"

SOURCES_FILE="${SCRIPT_DIR}/sources.list.${CODENAME}"
if [ ! -f "${SOURCES_FILE}" ]; then
	echo "Missing ${SOURCES_FILE}"
	exit 1
fi

HOST_ARCH="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
NEED_QEMU=0
if [ "${ARCH}" != "${HOST_ARCH}" ]; then
	NEED_QEMU=1
fi

runroot rm -rf "${TARGET_ROOTFS_DIR}"
runroot mkdir -p "${TARGET_ROOTFS_DIR}"

if [ ! -f "${SCRIPT_DIR}/${TARBALL_NAME}" ]; then
	echo "==> wget ${BASE_URL}"
	wget -c "${BASE_URL}" -O "${SCRIPT_DIR}/${TARBALL_NAME}"
fi

echo "==> extract ${TARBALL_NAME}"
runroot tar -xzf "${SCRIPT_DIR}/${TARBALL_NAME}" -C "${TARGET_ROOTFS_DIR}/"
runroot cp -b /etc/resolv.conf "${TARGET_ROOTFS_DIR}/etc/resolv.conf"
runroot cp "${SOURCES_FILE}" "${TARGET_ROOTFS_DIR}/etc/apt/sources.list"

if [ "${NEED_QEMU}" = 1 ]; then
	QEMU_BIN=""
	if [ "${ARCH}" = "armhf" ]; then
		QEMU_BIN="/usr/bin/qemu-arm-static"
	elif [ "${ARCH}" = "arm64" ]; then
		QEMU_BIN="/usr/bin/qemu-aarch64-static"
	fi
	if [ -z "${QEMU_BIN}" ] || [ ! -f "${QEMU_BIN}" ]; then
		echo "Cross-arch chroot needs ${QEMU_BIN:-qemu-user-static} (install qemu-user-static or use ubuntu/docker/build-rootfs.sh)."
		exit 1
	fi
	runroot cp -b "${QEMU_BIN}" "${TARGET_ROOTFS_DIR}/usr/bin/"
fi

finish() {
	"${SCRIPT_DIR}/ch-mount.sh" -u "${TARGET_ROOTFS_DIR}" 2>/dev/null || true
	echo -e "\033[47;31merror exit\033[0m"
	exit 1
}
trap finish ERR

echo -e "\033[47;36m chroot setup (${UBUNTU_RELEASE} ${CODENAME} lite) \033[0m"
"${SCRIPT_DIR}/ch-mount.sh" -m "${TARGET_ROOTFS_DIR}"

cat <<'EOF' | runroot chroot "${TARGET_ROOTFS_DIR}" bash -se
set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

apt-get -y update
apt-get -f -y upgrade

apt-get install -y --no-install-recommends \
	rsyslog sudo dialog apt-utils ntp evtest acpid

apt-get install -y --no-install-recommends \
	net-tools openssh-server ifupdown alsa-utils ntp network-manager inetutils-ping libssl-dev \
	vsftpd tcpdump i2c-tools strace vim iperf3 ethtool netplan.io toilet htop pciutils usbutils curl \
	whiptail gnupg bc gdisk parted sox libsox-fmt-all gpiod libgpiod-dev \
	u-boot-tools bsdmainutils file fdisk bluez

if ! id -u cat &>/dev/null; then
	useradd -G sudo -m -s /bin/bash cat
	passwd cat <<IEOF
temppwd
temppwd
IEOF
fi
gpasswd -a cat video 2>/dev/null || true
gpasswd -a cat audio 2>/dev/null || true
passwd root <<IEOF
root
root
IEOF

sed -i '/pam_securetty.so/s/^/# /g' /etc/pam.d/login 2>/dev/null || true
echo ubuntu-lite > /etc/hostname
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

groupadd -f --system cvi 2>/dev/null || true
groupadd -f --system gpio 2>/dev/null || true
id -u cat &>/dev/null && { adduser cat cvi 2>/dev/null || true; adduser cat gpio 2>/dev/null || true; adduser cat i2c 2>/dev/null || true; }

for service in NetworkManager systemd-networkd; do
	systemctl mask "${service}-wait-online.service" 2>/dev/null || true
done
systemctl mask wpa_supplicant-wired@ 2>/dev/null || true
systemctl mask wpa_supplicant-nl80211@ 2>/dev/null || true
systemctl mask wpa_supplicant@ 2>/dev/null || true

sed -i 's/#LogLevel=info/LogLevel=warning/' /etc/systemd/system.conf 2>/dev/null || true
sed -i 's/#LogTarget=journal-or-kmsg/LogTarget=journal/' /etc/systemd/system.conf 2>/dev/null || true

SUDOEXISTS="$(awk '$1 == "%sudo" { print $1 }' /etc/sudoers 2>/dev/null || true)"
if [ -z "${SUDOEXISTS}" ]; then
	echo "%sudo	ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi
sed -i -e '/\%sudo/ c %sudo    ALL=(ALL) NOPASSWD: ALL' /etc/sudoers

apt-get clean
rm -rf /var/lib/apt/lists/*
sync
EOF

"${SCRIPT_DIR}/ch-mount.sh" -u "${TARGET_ROOTFS_DIR}"

DATE="$(date +%Y%m%d)"
OUT="ubuntu-base-${TARGET}-${ARCH}-${DATE}.tar.gz"
echo -e "\033[47;36m pack ${OUT} \033[0m"
runroot tar -czpf "${SCRIPT_DIR}/${OUT}" -C "${SCRIPT_DIR}" "${TARGET_ROOTFS_DIR}"
_owner_uid="${HOST_UID:-$(id -u)}"
_owner_gid="${HOST_GID:-$(id -g)}"
if [ "$(id -u)" -eq 0 ] && [ -n "${HOST_UID:-}" ]; then
	chown "${_owner_uid}:${_owner_gid}" "${SCRIPT_DIR}/${OUT}" 2>/dev/null || true
elif [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
	sudo chown "${_owner_uid}:${_owner_gid}" "${SCRIPT_DIR}/${OUT}" 2>/dev/null || true
fi
echo -e "\033[47;36m done: ${SCRIPT_DIR}/${OUT} \033[0m"
