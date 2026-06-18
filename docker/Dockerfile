# SPDX-License-Identifier: MIT
# Optional: pre-baked builder for aarch64 CI only. On x86_64 use build-rootfs.sh
# (official ubuntu:24.04 + multiarch/qemu-user-static on host) instead of docker build.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		wget \
		ca-certificates \
		gnupg \
		xz-utils \
		tar \
		gzip \
		util-linux \
		procps \
		bash \
		mount \
		coreutils \
		qemu-user-static \
		e2fsprogs \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /work
