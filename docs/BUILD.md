# 构建指南（BUILD.md）

本 feed 没有独立的构建系统——它是给 OpenWrt SDK 用的包源。`make
package/<name>/compile` 会通过 `STAMP_BUILT_DEPENDS` 递归构建全部运行期依赖，
所以一次命令就能产出整个依赖树。

## 环境要求

- Linux（或 WSL2），内存建议 ≥ 8 GB，磁盘 ≥ 30 GB
- 依赖：`build-essential clang flex bison gawk g++ gcc-multilib gettext git
  libncurses-dev libssl-dev python3 python3-setuptools rsync unzip zlib1g-dev file`
  （Ubuntu 包名）

## 一、24.10 SDK → .ipk

```sh
VER=24.10.0   # 或最新 24.10.x patch
SDK=openwrt-sdk-${VER}-x86-64_gcc-13.3.0_musl.Linux-x86_64.tar.xz
wget https://downloads.openwrt.org/releases/${VER}/targets/x86/64/${SDK}
tar -xJf ${SDK}
cd openwrt-sdk-*

# 1) 官方 feeds（python 包复用与 luci 需要）
./scripts/feeds update packages luci
./scripts/feeds install -a

# 2) 链接本 feed
./scripts/feeds src-link hermes-openwrt /path/to/hermes-openwrt/packages
./scripts/feeds install -a

make defconfig

# 3) 构建（产物在 bin/packages/x86_64/hermes-openwrt/ 等目录）
make package/hermes-agent/compile V=s
make package/luci-app-hermes-agent/compile V=s
```

构建其他架构（例如 mediatek/filogic）：换成对应的 SDK tarball
（`.../targets/mediatek/filogic/` 下的 `openwrt-sdk-*-mediatek-filogic_*-musl.*.tar.xz`）。

## 二、25.12 SDK → .apk

流程完全相同，只是 SDK 换 25.12：
`https://downloads.openwrt.org/releases/25.12.0/targets/x86/64/` 下的
`openwrt-sdk-*`。构建系统自动产出 `.apk`（apk-tools 2.x 格式），
`bin/packages/` 下还会生成 `APKINDEX.tar.gz`。

## 三、构建行为与常见问题

### Python 版本自动适配

`packages/lang/python/python3-version.mk` 按以下顺序解析 Python 版本：

1. 若 SDK 的 packages feed 存在（`feeds/*/lang/python/python3-version.mk`），
   使用其 pin（24.10 → 3.11.14，25.12 → 3.13.9）——无需任何参数；
2. 否则回退到 3.11.14（24.10 默认），此时可在命令行覆盖：
   `make package/hermes-agent/compile PYTHON3_VERSION_MINOR=13`

### 命名规则（24.10 起官方 feed 使用 python- 前缀）

| 来源 | 前缀 | 示例 |
| --- | --- | --- |
| 官方 packages feed（复用） | `python-` | `python-yaml`、`python-requests`、`pillow`（特殊，无前缀） |
| 本 feed vendored | `python3-` | `python3-httpx`、`python3-pydantic` |
| python3 主包 stdlib 拆分包 | `python3-` | `python3-sqlite3`、`python3-multiprocessing` |

修改依赖时不要混用前缀（详见 docs/PORTING.md）。

### pydantic-core / jiter（Rust 扩展）

使用预编译 **musllinux wheel**（解压即用，无 glibc 依赖），Makefile 中按
`{Python 版本, CPU}` 条件选择 `PKG_SOURCE`。支持 aarch64 / x86_64 / armv7l；
其他架构会得到 `$(error)` 提示（jiter 无 armv7l wheel，仅 aarch64 / x86_64）。
不需要在构建机上装 Rust。

### 网络

- 源码下载：`github.com`（hermes-agent git 源）、`files.pythonhosted.org`（PyPI）
- 若在内网/受限网络构建，可先 `make package/<pkg>/download` 预取全部源码到 `dl/`
- `PKG_MIRROR_HASH` 留空时首次构建会提示补值（git 源 hash 依赖下载内容）

### 常见错误

| 现象 | 原因 |
| --- | --- |
| `No such file or directory: .../lang/python/python3-package.mk` | 未 `feeds src-link` 本 feed，或 include 相对路径错位 |
| `unknown package 'python3-yaml'` | DEPENDS 用了旧 python3- 前缀的官方包名（应为 python-yaml） |
| `python3-pydantic-core: no wheel for Python X / ARCH=Y` | 该 {Python, CPU} 组合没有 musllinux wheel（见 PORTING.md） |
| 构建卡在 host rust | 本 feed 不用 Rust 工具链；若见到 rust 构建，是依赖树上混入了上游包（如 python-setuptools-rust） |

## 四、CI（GitHub Actions）

`.github/workflows/build-ipk.yml` / `build-apk.yml` 自动解析最新 patch 版
SDK，矩阵覆盖 `x86/64` 与 `mediatek/filogic`，构建完成后上传整个
`bin/packages/` 树作为 artifact（保留 7 天）。

- 触发：push / PR 到 main、手动 `workflow_dispatch`
- 时长：约 1–2 小时（主要是 host python3 与各包编译）
- 产物即插即用：scp 到路由器后 `opkg install *.ipk` / `apk add *.apk`
