# 构建指南（BUILD.md）

这个 feed 没有自己的构建系统，它是给 OpenWrt SDK 用的包源。`make
package/<name>/compile` 会顺着 `DEPENDS` 递归把运行期依赖一起建出来，所以一条命令
就能得到完整产物。

## 环境要求

- Linux（或 WSL2），内存 ≥ 8 GB，磁盘 ≥ 30 GB（四个 SDK 全放会到 60 GB）
- Ubuntu/Debian 包名：

  ```
  build-essential clang flex bison gawk g++ gcc-multilib gettext git
  libncurses-dev libssl-dev python3 python3-setuptools rsync unzip
  zlib1g-dev file zstd swig python3-pyelftools
  ```

  最后两个（`swig`、`python3-pyelftools`）与本 feed 无关，是 `uboot-rockchip` 的
  prereq 要求的——见下面「SDK 会替你选中整个世界」。25.12 的 SDK 用 `.tar.zst`
  打包，所以 `zstd` 也要装。

不需要 Rust 工具链：所有 Rust/C 扩展都以预编译 musllinux wheel 形式进来。

## 一、取 SDK

四种目标组合，各取一次即可：

```sh
# 25.12 / x86_64（.apk）
BASE=https://downloads.openwrt.org/releases/25.12.5/targets/x86/64
# 25.12 / rockchip armv8（.apk）
BASE=https://downloads.openwrt.org/releases/25.12.5/targets/rockchip/armv8
# 24.10 / x86_64（.ipk）
BASE=https://downloads.openwrt.org/releases/24.10.8/targets/x86/64
# 24.10 / rockchip armv8（.ipk）
BASE=https://downloads.openwrt.org/releases/24.10.8/targets/rockchip/armv8

url=$(curl -fsSL "$BASE/" | grep -oE 'openwrt-sdk-[^"<]*\.tar\.(xz|zst)' | head -n1)
curl -fsSLO "$BASE/$url"
mkdir sdk && tar -xaf "$url" --strip-components=1 -C sdk
```

包格式不用选：24.10 的构建系统产出 `.ipk`，25.12 产出 `.apk`，同一份 Makefile
两边都能过。

RK3528 属于 `rockchip/armv8`（`aarch64_generic`），用上面第二/第四条。

## 二、挂上 feed 并只选中我们的包

```sh
cd sdk
./scripts/feeds update -a
./scripts/feeds src-link hermes-openwrt /path/to/hermes-openwrt/packages
./scripts/feeds update hermes-openwrt
./scripts/feeds install -a

# 关键一步：裁掉 SDK 自带的全量包选择，并 make defconfig（理由见下一节）
sh /path/to/hermes-openwrt/scripts/sdk-trim-config.sh .
```

脚本跑完会打印前后对比，24.10/rockchip 上是这样：

```
  before     packages:6683   kmod:1084   firmware:188  u-boot:35
  after      packages:64     kmod:0      firmware:0    u-boot:0
```

`after` 那 64 个包就是我们两个包的依赖闭包（python3 全家、luci-base、
rpcd-mod-ucode、libopenssl…），一个不多。脚本自己会 `make defconfig` 并校验我们
两个包确实 `=m`，所以不需要再手工追加 `CONFIG_PACKAGE_…=m`。

### SDK 会替你选中整个世界

一个 SDK 的默认选择里包含**所有** feed 的**所有**包：6683 个包、1084 个内核模块、
188 个 firmware，在 rockchip 上还有 35 个 u-boot 变体。三个后果：

- `make package/hermes-agent/compile` 会把 kmod 和 `linux-firmware` 当作附带
  产物一起编，每个目标白烧近一小时；
- `make` 在干活之前会对**所有已选中的包**跑一遍 `prereq`，而
  `uboot-rockchip` 的 prereq 要求宿主机有 `swig` 和 `python3-pyelftools`。
  缺任何一个，整个 feed 构建会在开始之前就失败，为的是一个没人要的 bootloader：

  ```
  Checking 'python3-pyelftools'... failed.
  Checking 'swig'... failed.
  u-boot: Please install the Python3 elftools module
  ERROR: package/feeds/base/uboot-rockchip failed to build (build variant: nanopc-t4-rk3399).
  ```

- 只裁一半更糟，见本节最后。

**光改 `.config` 是没用的**，这一点值得记住，因为它会浪费掉一整个下午：SDK 里的
`Config-build.in` 把每个包符号声明成**没有 prompt** 的形式：

```
config PACKAGE_kmod-aoe
	tristate
	default m
```

kconfig 对不可见符号一律忽略用户值，只取 default。所以 `.config` 里写
`CONFIG_PACKAGE_kmod-aoe=n`、写 `# CONFIG_PACKAGE_kmod-aoe is not set`、或者把整行
删掉，下一次 `make defconfig` 都会原样恢复；`CONFIG_ALL=n`、`CONFIG_ALL_KMODS=n`、
`CONFIG_ALL_NONSHARED=n` 同样无效（这三个符号在 SDK 里也是 promptless 的）。

**但只改 `Config-build.in` 也不够。** feed 里的包在 `tmp/.config-package.in` 里
**另有一份带 prompt 的声明**，而带 prompt 的符号 kconfig 是尊重 `.config` 里的旧值
的——SDK 出厂的 `.config` 里它们全是 `=m`。所以两件事都要做，缺一个都像是脚本没生效：

1. `Config-build.in`：所有 `PACKAGE_*` 以及 `ALL` / `ALL_KMODS` / `ALL_NONSHARED`
   的 `default y|m` 改成 `default n`（留 `Config-build.in.pristine` 备份，
   `--restore` 可回滚）；
2. `.config`：删掉所有 `CONFIG_PACKAGE_*` 行（其余的 target / arch / toolchain
   设置必须原样保留），只写回我们两个包。

`scripts/sdk-trim-config.sh` 做的就是这两步 + `make defconfig`。

#### 只裁 kmod 比不裁更糟

这是本项目踩过的最贵的一个坑：只做上面第 1 步会得到一个**部分选中**的 kmod 集合，
而 `Config-build.in` 里**一条 `select` 都没有**（0 条，对比
`tmp/.config-package.in` 里的 777 条），kconfig 因此完全无法推导内核模块的依赖闭包。
于是 `comgt-ncm` 选中了 `kmod-usb-serial-option`，没人选中它需要的
`kmod-usb-serial-wwan`，四十分钟后 `package/kernel/linux` 在打包阶段炸掉：

```
Package kmod-usb-serial-option is missing dependencies for the following libraries:
usb_wwan.ko
make[2]: *** [modules/usb.mk:1019: …/kmod-usb-serial-option_6.6.144-r1_x86_64.ipk] Error 1
ERROR: package/kernel/linux failed to build.
```

自洽的状态只有两个：kmod 全选（上游一致，但慢），或者 kmod 一个都不选。脚本走后者，
并在 `make defconfig` 之后断言 kmod 计数为 0，不为 0 就当场警告——比四十分钟后再
发现便宜得多。

## 三、构建

```sh
make package/hermes-agent/compile V=s -j"$(nproc)"
make package/luci-app-hermes-agent/compile V=s -j"$(nproc)"
```

产物：

| OpenWrt | 路径 | 文件名 |
| --- | --- | --- |
| 25.12 | `bin/packages/<arch>/hermes-openwrt/` | `hermes-agent-<ver>-r<rel>.apk` |
| 24.10 | `bin/packages/<arch>/hermes-openwrt/` | `hermes-agent_<ver>-r<rel>_<arch>.ipk` |

注意两种格式的分隔符不同（`-` 与 `_`）——写脚本匹配产物时别只写一种，
`scripts/check-artifacts.sh` 里的 glob 是 `hermes-agent[-_][0-9]*`。

第一次构建的大头是 host Python、target OpenSSL/Python 和依赖 wheel 的下载；
之后重编只有我们两个包，几十秒。

## 四、验证

构建前（几秒，不需要 SDK）：

```sh
sh scripts/check-sources.sh
```

它检查 shell / Python / JSON / LuCI 视图语法，并且交叉验证四件只有在真机上才会
暴露的事：菜单项指向的视图文件存在、视图调用的 ubus 方法在 `acl.d` 里放行了、
放行的方法 ucode 插件真的实现了、插件调用的每个 ucode 全局函数真的存在。
有 `ucode` 二进制时用 `ucode -c` 编译插件并在 `'use strict'` 下探测全局名字
（**不是** `ucode -T`——那是模板模式，任何输入都会 exit 0），没有时退回 node 做近似
语法检查。

构建后：

```sh
sh scripts/check-artifacts.sh /path/to/sdk
```

它把两个包解开（`.apk` 用 SDK 自带的 `staging_dir/host/bin/apk extract`，
`.ipk` 直接解 `data.tar.gz`），逐条核对 Makefile 承诺的文件是否真的在里面，
包括 `hermes-chatd` 与 init 脚本的可执行位、`.dist-info` 元数据的数量（上游多处
调 `importlib.metadata.version()`，只拷源码树会在运行期抛
`PackageNotFoundError`）、以及已删除的旧视图有没有从脏的 `PKG_BUILD_DIR` 里
复活。

### 运行期冒烟测试（真 rootfs，不需要路由器）

```sh
sh scripts/smoke/run.sh ~/hermes-build/sdk/sdk-25.12-x86_64
```

它做的事：取和 SDK 同一个 release 的官方 x86_64 rootfs（版本从 SDK 自己的
`CONFIG_VERSION_REPO` 读，所以 libc / python 小版本 / 包管理器代次都对得上），
每次**重新解开**一份，在 bubblewrap 沙箱里 `apk add` 刚构建的两个包，然后按顺序
验证：文件与权限、musl soname 软链、`hermes --version`、`hermes --help`（这一步才
会构造完整 parser，也就是导入所有子命令）、闭包里 13 个原生扩展逐个能否加载、
`.dist-info` 数量、`ucode -c` 编译 rpcd 插件、`ubusd`+`rpcd` 起来之后
`ubus call luci.hermes-agent {status,settings_get,logs}`、init 脚本对非回环
`host` 的拒绝，最后拉起 `hermes serve` 与 `hermes-chatd` 验证 `/api/ws` 握手，
并从 ubus 侧走一遍 `chat_send` → 网关 → `chat_poll` 的完整往返。
退出码就是失败项数。

沙箱里 `logd` 起不来（要读 `/proc/kmsg`，`setgid()` 在只映射一个 uid 的用户命名空间
里返回 EINVAL），所以 `logread` 是空的：`logs` 那个 ubus 方法只验通路不验内容，
而检查 init 脚本 `logger` 输出的那一步用 PATH 顶一个 `logger` stub。
ucode 方法里抛出的异常在 ubus 调用方只显示 `Unknown error`，真正的消息在 rpcd 的
stderr 里，所以聊天那几步失败时会自动把 `/tmp/rpcd.log` 打出来。

第一次会下 ~250 MB 的 rootfs 压缩包（缓存在工作目录里，默认
`/tmp/hermes-smoke`，可用第二个参数指定），整跑一次三到五分钟。

两个前提：宿主要有 `bubblewrap`（`apt install bubblewrap`；这台机器上非特权
`unshare -rm` 挂不上 `/proc`、`/sys`、`/dev`，所以不能用 chroot 凑），并且只能测
x86_64 SDK——沙箱里跑的是目标的真二进制，aarch64 在 x86 上执行不了。

## 五、离线 / 受限网络

```sh
make package/hermes-agent/download    # 预取 git 源 + 全部 wheel 到 dl/
```

所有 wheel 都由 `deps/*.mk` 以 `$(call Download,...)` 声明并带 sha256，
`PKG_MIRROR_HASH:=skip` 只作用于 git 源。需要的域名：`github.com`、
`files.pythonhosted.org`。

## 六、CI

`.github/workflows/build.yml`：一个 `lint` job（上面那些静态检查 + 用 Makefile 里
pin 的上游 commit 重新解析依赖，核对 `deps/*.mk` 没被手改过）加一个 4 条腿的
`build` 矩阵，覆盖上面四种组合，每条腿跑同一个 `check-artifacts.sh`，产物只上传
我们两个包（不是整个 `bin/` 树）。SDK 版本在运行时解析成最新 patch 版，所以跟随
上游修复不需要改这里。

两条 x86_64 的腿在 `check-artifacts.sh` 之后还会跑一遍上面那个冒烟测试
（`apt install bubblewrap` + 一句
`sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`——Ubuntu 24.04 的 runner
用 AppArmor 限制了非特权用户命名空间，不解开的话 bwrap 起不来），多两三分钟，换来
的是唯一一层真的**执行**目标代码的验证。aarch64 那两条腿跑不了：沙箱里跑的是目标
真二进制。

## 七、多 SDK 批量构建（可选）

同时维护四个 SDK 时，两个小脚本能省很多事——挂 feed / 修 config 一份，构建一份：

```sh
./hookup.sh   sdk-25.12-x86_64      # feeds + trim + defconfig
./buildall.sh sdk-25.12-x86_64 5    # 两个包 + check-artifacts，日志落到 log/
```

四个目标可以并行跑（每个 `-j5` 左右，避免互相抢核）。构建耗时长，务必用
`nohup ... &` detach 后轮询日志，不要让远程 shell 一直挂着。
