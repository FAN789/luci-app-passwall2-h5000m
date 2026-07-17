# H5000M PassWall2

面向 Hiveton/Airpi H5000M 官方 OpenWrt 基础固件的独立 PassWall2 离线安装包。

本仓库不制作整机固件，也不保存节点、订阅、UUID、服务器地址或其他私人配置。Release 仅包含 PassWall2、中文界面、代理核心及运行所需依赖，避免因大型代理组件进入主固件而扩大启动风险。

## 版本规则

- H5000M 离线集成包使用语义版本，例如 `1.0.0`、`1.0.1`、`1.1.0`。
- PassWall2、Xray Core、sing-box 等组件保留各自的上游版本号，不再混入集成包版本。
- Release 标签使用 `v1.0.0`，成品文件使用 `H5000M-PassWall2-1.0.0-<OpenWrt 修订>.tar.gz`。

## 兼容基线

- 设备：`hiveton,h5000m`
- OpenWrt：`r35346-e9aa5bea9f`
- 目标：`mediatek/filogic`
- 架构：`aarch64_cortex-a53`
- 软件包格式：OpenWrt APK v3

安装脚本会严格检查设备和固件版本。其他 OpenWrt 版本需要重新使用对应 SDK 编译，不建议强制安装。

## 包含组件

- PassWall2 `26.7.16-r1` 与简体中文翻译
- Xray Core `26.7.11`、sing-box `1.13.14`
- TCPing、GeoView
- V2Ray GeoIP、GeoSite、v2ray-plugin
- `dnsmasq-full`（含 `nftset`）及可回滚的官方精简 `dnsmasq`
- 与官方固件 Kernel ABI 完全一致的 nftables 透明代理及 TUN 内核模块
- `kmod-nf-socket`、`kmod-nf-tproxy`、`kmod-nf-conntrack-netlink` 等完整依赖闭包

PassWall2 安装后保持未配置状态，不包含任何默认节点，也不会自动启用代理。

## 安装

1. 从 Releases 下载 `H5000M-PassWall2-*.tar.gz`。
2. 将压缩包上传到路由器 `/tmp` 并解压。
3. 在解压目录执行：

```sh
./install.sh
```

安装器使用压缩包内的签名离线仓库，不依赖 OpenWrt 在线软件源。它会校验固件版本、Kernel ABI，保留 `/etc/config/dhcp`，将主固件的精简 `dnsmasq` 替换为 `dnsmasq-full`，并验证 `nft_socket`、`nft_tproxy` 可加载。验证失败时自动恢复精简 `dnsmasq`。完成后在 LuCI 中打开“服务 / PassWall2”配置节点。

## 本地构建与验证

先在 OpenWrt 构建树中编译 `config/packages.config` 指定的用户态软件包，再用与目标基础固件完全一致的 SDK 组装发行包。内核模块只允许取自该 SDK，组装器还会在官方基础固件的真实 SquashFS 根文件系统上执行离线安装模拟：

```sh
H5000M_APK_SIGNING_DIR="$HOME/.config/h5000m-apk" \
  ./scripts/build-release.sh \
  /path/to/extracted-openwrt-sdk \
  /path/to/openwrt-build-tree \
  /path/to/official-h5000m-root.squashfs
```

发行仓库仅收录 `config/release-packages.txt` 中的依赖闭包；主固件不再承担 PassWall2 运行依赖。发行包不会混入风扇、MT5700M、出口优先级、UPnP 等其他插件。私钥只在本地编译机使用，不写入仓库，也不上传到 GitHub Actions。GitHub Actions 仅执行脚本和隐私检查。

编译 PassWall2 前需应用 `patches/001-passwall2-empty-nftset-guard.patch`，用于避免空 nftables 集合被错误写入。完整上游版本和第三方说明见 `THIRD_PARTY.md`。

## 上游项目

本项目是 H5000M 的构建和交付封装。PassWall2 本体来自 [xiaorouji/openwrt-passwall2](https://github.com/xiaorouji/openwrt-passwall2)，相关代理核心来自 OpenWrt packages feed 与 `kenzok8/small-package`。
