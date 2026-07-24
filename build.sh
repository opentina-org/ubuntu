#!/bin/bash
# SPDX-License-Identifier: MIT
# Unified entry: Ubuntu 22.04 / 24.04 lite (arm64 / armhf) base + overlay + ext4 image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

interactive_menu() {
	local c
	while true; do
		cat <<'EOF'

== Ubuntu rootfs (22.04 / 24.04 lite) ==
 0) Exit
 1) mk-base-ubuntu  24.04 + arm64  (download ubuntu-base + chroot)
 2) mk-base-ubuntu  24.04 + armhf
 3) mk-base-ubuntu  22.04 + arm64
 4) mk-base-ubuntu  22.04 + armhf
 5) mk-ubuntu-rootfs + mk-image      (arm64, needs tarball from 1/3)
 6) mk-ubuntu-rootfs + mk-image      (armhf)
 7) clean (binary/, ubuntu-rootfs.ext4)
 8) Docker: 24.04 + arm64 → lite tar.gz + ubuntu-rootfs.ext4 (needs Docker)
EOF
		read -r -p "Select [0-8]: " c
		case "${c}" in
		0) exit 0 ;;
		1) UBUNTU_RELEASE=24.04 ./mk-base-ubuntu.sh arm64 ;;
		2) UBUNTU_RELEASE=24.04 ./mk-base-ubuntu.sh armhf ;;
		3) UBUNTU_RELEASE=22.04 ./mk-base-ubuntu.sh arm64 ;;
		4) UBUNTU_RELEASE=22.04 ./mk-base-ubuntu.sh armhf ;;
		5) ./mk-ubuntu-rootfs.sh arm64 ;;
		6) ./mk-ubuntu-rootfs.sh armhf ;;
		7)
			if [ "$(id -u)" -eq 0 ]; then
				rm -rf binary ubuntu-rootfs.ext4 && echo "cleaned"
			else
				sudo rm -rf binary ubuntu-rootfs.ext4 && echo "cleaned"
			fi
			;;
		8) ./docker/build-rootfs.sh 24.04 ;;
		*) echo "invalid" ;;
		esac
	done
}

main() {
	case "${1:-}" in
	"" | menu)
		interactive_menu
		;;
	base)
		REL="${2:-24.04}"
		ARC="${3:-arm64}"
		UBUNTU_RELEASE="${REL}" ./mk-base-ubuntu.sh "${ARC}"
		;;
	rootfs)
		exec ./mk-ubuntu-rootfs.sh "${2:-arm64}"
		;;
	clean)
		if [ "$(id -u)" -eq 0 ]; then
			rm -rf binary ubuntu-rootfs.ext4
		else
			sudo rm -rf binary ubuntu-rootfs.ext4
		fi
		;;
	docker)
		REL="${2:-24.04}"
		exec ./docker/build-rootfs.sh "${REL}"
		;;
	*)
		echo "Usage: $0 [menu|base <22.04|24.04> <arm64|armhf>|rootfs <arm64|armhf>|clean|docker [22.04|24.04]]"
		exit 1
		;;
	esac
}

main "$@"
