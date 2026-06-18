## 简介

在 **arm64 / armhf（ubuntu-ports）** 上从官方 **ubuntu-base** 构建 **Ubuntu 22.04 LTS（Jammy）** 与 **24.04 LTS（Noble）** 的 **lite（无桌面）** rootfs，合并 `overlay/` 后可生成 `ubuntu-rootfs.ext4`。

## 推荐：Docker 内构建

宿主机只需 **Docker**（不必本机装全量 qemu / 交叉 chroot 依赖）。**不需要 Docker Buildx。**

在 **x86_64** 上编 **arm64** rootfs 时，脚本会：

1. 用 **`multiarch/qemu-user-static`**（`--privileged`）在**宿主机内核**注册 `binfmt_misc`，使本机 Docker 能运行 arm64 镜像（与官方多架构做法一致；重启后若失效可再跑一次）。
2. **`docker pull` / `docker run --platform linux/arm64`** 官方 **`ubuntu:24.04`**（或 `ROOTFS_BASE_IMAGE`）对应架构变体，在容器内安装依赖后默认执行 **`mk-base-ubuntu.sh` → `mk-ubuntu-rootfs.sh`**（含 **`ubuntu-rootfs.ext4`**）。

```shell
cd ubuntu && ./docker/build-rootfs.sh 24.04
# 或：ARCH=armhf ./docker/build-rootfs.sh 24.04
```

常用环境变量：

| 变量 | 说明 |
|------|------|
| `ARCH` | 默认 `arm64`；`armhf` 时在 x86 上对应 `--platform linux/arm/v7` |
| `ROOTFS_BASE_IMAGE` | 默认 `ubuntu:24.04`（仅作构建环境；与 `UBUNTU_RELEASE` 可不同） |
| `QEMU_BINFMT_IMAGE` | 默认 `multiarch/qemu-user-static` |
| `QEMU_BINFMT_SETUP=0` | 跳过宿主机 binfmt 注册（已配置过时） |
| `DOCKER_PLATFORM` | 覆盖 `--platform` |
| `DOCKER_AUTO_PLATFORM=0` | 不自动加 `--platform` |
| `UBUNTU_DOCKER_TARGETS` | 默认 **`all`**：`mk-base-ubuntu.sh` + `mk-ubuntu-rootfs.sh`（**`ubuntu-rootfs.ext4`**）；设为 **`base`** 则只打 `ubuntu-base-lite-*.tar.gz` |

产物默认写在 **`ubuntu/`** 目录下（**`ubuntu-rootfs.ext4`** + **`ubuntu-base-lite-*.tar.gz`**），并 `chown` 为当前用户。

构建使用 **`--privileged`**（chroot / 挂载 / ext4）。**`ubuntu/docker/Dockerfile`** 仅作可选（例如在 aarch64 CI 里预装依赖）；x86 默认流程不执行 `docker build`。

## 主机依赖（本地直接跑脚本）

```shell
sudo apt-get install -y binfmt-support qemu-user-static wget tar gzip
# 可选：打包阶段 post-build 若需 dpkg 包
# sudo dpkg -i ubuntu-build-service/packages/* 2>/dev/null || true
```

## 一键入口：`build.sh`

在 `ubuntu/` 目录：

```shell
./build.sh              # 交互菜单（含 Docker 选项）
./build.sh base 24.04 arm64
./build.sh rootfs arm64
./build.sh docker 24.04
./build.sh clean
```

## 分步说明

1. **`mk-base-ubuntu.sh`**：下载 `cdimage.ubuntu.com` 的 `ubuntu-base-*-base-<arch>.tar.gz`，`chroot` 安装 lite 软件包，打出 **`ubuntu-base-lite-<arch>-<日期>.tar.gz`**（内含 `binary/` 目录，与旧流程兼容）。

   - 默认 **24.04**（Noble），点版本可通过环境变量覆盖，例如：  
     `UBUNTU_BASE_VERSION=24.04.3 UBUNTU_RELEASE=24.04 ./mk-base-ubuntu.sh arm64`
   - **22.04**（Jammy）：`UBUNTU_RELEASE=22.04 ./mk-base-ubuntu.sh arm64`  
     默认点版本 `22.04.5`，可用 `UBUNTU_BASE_VERSION` 覆盖。
   - 完整 URL 可覆盖：`UBUNTU_BASE_URL=https://.../ubuntu-base-....tar.gz ./mk-base-ubuntu.sh arm64`

2. **`mk-ubuntu-rootfs.sh`**：解压最新（或 `UBUNTU_BASE_TAR=` 指定）的 `ubuntu-base-lite-*.tar.gz`，合并 `overlay/`，`chroot` 收尾后调用 **`mk-image.sh`** 生成 **`ubuntu-rootfs.ext4`**。

## APT 源

- **`sources.list.jammy`**：22.04（USTC `ubuntu-ports`）
- **`sources.list.noble`**：24.04
- 根目录 **`sources.list`** 保留为 jammy 兼容副本；新构建以 `sources.list.<codename>` 为准。

## 登录界面与版本文案

| 位置 | 作用 |
|------|------|
| `overlay/etc/issue`、`issue.net` | 串口登录前横幅；使用 `\S` 从 `/etc/os-release` 读取版本（勿写死 22.04/24.04） |
| `overlay/etc/update-motd.d/00-header` | 登录后 MOTD 横幅（默认 OpenTina ASCII，原为第三方板卡图案） |
| `overlay/etc/update-motd.d/10-help-text` | MOTD 下方链接行 |
| `mk-base-ubuntu.sh` | `hostname` 默认为 `ubuntu-lite`（`/etc/hostname`） |

自定义 MOTD 图案：构建时设置环境变量 **`OPENTINA_MOTD_BANNER_FILE=/path/to/banner.txt`**（`mk-ubuntu-rootfs.sh` 会安装为 `/etc/opentina-motd-banner`）。

修改版本请用 **`UBUNTU_RELEASE=24.04`**（或 `22.04`）重建 **base + rootfs**；仅改 overlay 不重打 base 时，`/etc/os-release` 与 `issue` 可能不一致。

## OEM 注入（仅 buildx 路径）

构建时可以把自己的 deb 包、文件和收尾脚本打进 rootfs，不必 fork 本仓库。把环境变量 **`OPENTINA_OEM_DIR`** 指向一个目录，`docker/build-rootfs-buildx.sh` 会将它拷进构建上下文的 `.oem-staging/`，再由 `Dockerfile.rootfs` 装入镜像：

```
$OPENTINA_OEM_DIR/
  packages/            安装这里的 *.deb（apt-get install ./packages/*.deb）
  rootfs-overlay/      整个目录按原路径覆盖到 /
  post.sh              在 chroot 内执行（需可执行权限；可选）
```

依赖策略：**不加 `-f` / `--fix-broken`**。`packages/` 里 deb 的依赖必须能由 noble/jammy 主源或同目录的其它 `.deb` 满足，否则 `docker build` 直接失败，不会自动卸包凑数。缺依赖时，把依赖 deb 一并放进 `packages/`，或在板级 `config` 里用 `EXTRA_DEBS` 从主源装。

板级默认目录 `configs/<板>/oem/` 的选取规则见上一级 `../../README.md`。

## 其它

- **`ubuntu/docker/`**：推荐在 x86 上用官方多架构 + `build-rootfs.sh` 构建；`Dockerfile` 为可选 CI 镜像。
- **`ubuntu-build-service/`**：历史遗留目录，未参与当前 lite 脚本链。
