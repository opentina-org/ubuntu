#!/bin/bash -e
# SPDX-License-Identifier: MIT

runroot() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}

TARGET_ROOTFS_DIR=./binary
ROOTFSIMAGE=ubuntu-rootfs.ext4

echo Making rootfs!

if [ -e ${ROOTFSIMAGE} ]; then
	runroot rm -f ${ROOTFSIMAGE}
fi

dd if=/dev/zero of=${ROOTFSIMAGE} bs=1M count=0 seek=6000

echo Format rootfs to ext4 and populate from ${TARGET_ROOTFS_DIR}
# mkfs.ext4 -d needs no loop mount, which fails in qemu-emulated containers.
runroot mkfs.ext4 -F -d ${TARGET_ROOTFS_DIR} ${ROOTFSIMAGE}

echo Rootfs Image: ${ROOTFSIMAGE}

runroot e2fsck -p -f ${ROOTFSIMAGE}
runroot resize2fs -M ${ROOTFSIMAGE}

_owner_uid="${HOST_UID:-$(id -u)}"
_owner_gid="${HOST_GID:-$(id -g)}"
if [ "$(id -u)" -eq 0 ] && [ -n "${HOST_UID:-}" ]; then
	chown "${_owner_uid}:${_owner_gid}" "${ROOTFSIMAGE}" 2>/dev/null || true
elif [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
	sudo chown "${_owner_uid}:${_owner_gid}" "${ROOTFSIMAGE}" 2>/dev/null || true
fi
