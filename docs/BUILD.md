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

# feed 名只能是 [A-Za-z0-9_]，见下面「feed 名里不能有连字符」
test -f feeds.conf || cp feeds.conf.default feeds.conf
grep -q '^src-link hermes ' feeds.conf ||
	echo "src-link hermes /path/to/hermes-openwrt/packages" >> feeds.conf

./scripts/feeds update -a
./scripts/feeds install -a

# 关键一步：裁掉 SDK 自带的全量包选择，并 make defconfig（理由见下一节）
sh /path/to/hermes-openwrt/scripts/sdk-trim-config.sh .
```

### feed 名里不能有连字符

`scripts/feeds` 解析 `feeds.conf` 的正则是：

```perl
m!^src-([\w\-]+)((?:\s+--\w+(?:=\S+)?)*)\s+(\w+)(?:\s+(\S.*))?$!
```

**类型**可以带连字符（`[\w\-]+`，所以有 `src-git-full`），**feed 名却是 `(\w+)`**。
写成 `hermes-openwrt` 会直接 `Syntax error in feeds.conf, line 1` 并 `die`（exit 25），
而且报错只说行号不说原因。这在 CI 上真的发生过。所以名字用 `hermes`——顺带一提，
feed 名就是产物目录名，所以本地和 CI 的 `bin/packages/<arch>/hermes/` 是同一个路径。

另外两点同样要紧：

- **没有 `feeds src-link` 这个子命令**（全集是 list / install / search / uninstall /
  update / clean）。写了也只会把 usage 打进日志然后往下走，看起来像成功了。挂本地
  目录的正确做法就是往 `feeds.conf` 里写一行 `src-link <名> <绝对路径>`。
- **SDK 里只有 `feeds.conf.default`，没有 `feeds.conf`**，而 `scripts/feeds` 一旦发现
  `feeds.conf` 就只认它。所以直接 `>> feeds.conf` 会造出一个只有我们这一条的配置，
  base/packages/luci 全部消失（`./scripts/feeds list -n` 只剩 `hermes`），之后
  `luci-base` 无从安装。必须先从 `.default` 拷一份。

脚本跑完会打印前后对比。已经 `make defconfig` 过一次的 SDK 上是这样：

```
  before     packages:6683   kmod:1084   firmware:188  u-boot:35
  after      packages:64     kmod:0      firmware:0    u-boot:0
```

刚解开、还没有 `.config` 的 SDK 上 `before` 那行会是 `(no .config yet)`，`after`
一样是 64 / 0 / 0 / 0（在 24.10/x86_64 上逐字比对过：和构建机上那个用了很久的 SDK
选出来的 64 个包**完全一致**）。

`after` 那 64 个包就是我们两个包的依赖闭包（python3 全家、luci-base、
rpcd-mod-ucode、libopenssl…），一个不多。脚本自己会 `make defconfig` 并校验我们
两个包确实 `=m`，所以不需要再手工追加 `CONFIG_PACKAGE_…=m`。重复跑是幂等的。

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
删掉，下一次 `make defconfig` 都会原样恢复。

**但只改 `Config-build.in` 也不够**，而且不够的地方有两处。

第一处：feed 里的包在 `tmp/.config-package.in` 里**另有一份带 prompt 的声明**，而带
prompt 的符号 kconfig 是尊重 `.config` 里的旧值的——SDK 出厂的 `.config` 里它们全是
`=m`。（两份声明谁的 `default` 生效取决于解析顺序：`Config.in` 先 `source
"Config-build.in"` 再 `source "tmp/.config-package.in"`，同一符号第一条匹配的
`default` 胜出，所以 base 包由前者决定。）

第二处，也是**排查最久的一处**：那 10905 个带 prompt 的符号写的是

```
	config PACKAGE_block-mount
		tristate "block-mount..........."
		default y if DEFAULT_block-mount
		default m if ALL||ALL_NONSHARED
		select PACKAGE_libblobmsg-json
		...
```

而 `ALL` / `ALL_KMODS` / `ALL_NONSHARED` 这三个开关，在 SDK **自己的 `Config.in`**
里（不是生成的 `Config-build.in`）还有第二份声明，**是带 prompt 的**：

```
	config ALL
		bool "Select all userspace packages by default"
		default y
```

也就是说这三个符号根本不是 promptless 的，改 `Config-build.in` 里那三段**完全无效**，
必须在 `.config` 里关掉。这个 bug 藏了很久，因为一个用过一段时间的 SDK 的 `.config`
里通常已经有 `# CONFIG_ALL is not set` 了（早年某次 menuconfig 留下的），裁剪脚本
看起来一直好好的；而**全新解开的 SDK**——CI 上永远是这种——`ALL` 默认 `y`，裁完还剩
9832 个包和 186 个内核模块，正好落进下面「只裁 kmod 比不裁更糟」那个坑。

所以三件事都要做，缺一个都像是脚本没生效：

1. `Config-build.in`：所有 `PACKAGE_*` 的 `default y|m` 改成 `default n`
   （留 `Config-build.in.pristine` 备份，`--restore` 可回滚）；
2. `.config`：删掉所有 `CONFIG_PACKAGE_*` 行（其余的 target / arch / toolchain
   设置必须原样保留），只写回我们两个包；
3. `.config`：写上三行 `# CONFIG_ALL is not set` / `# CONFIG_ALL_KMODS is not set` /
   `# CONFIG_ALL_NONSHARED is not set`。

`scripts/sdk-trim-config.sh` 做的就是这三步 + `make defconfig`，并在最后**硬断言**
kmod / firmware / u-boot 三项计数都是 0（以前只是 warning，于是它在每一次「绿色」的
CI 里都老老实实警告过，而 CI 照样把内核模块全编了一遍）。它在没有 `.config` 的全新
SDK 上也能跑：`.config` 缺的部分 kconfig 会从 `Config-build.in` 的 default 里补齐。

#### 只裁 kmod 比不裁更糟

这是本项目踩过的最贵的一个坑：只做上面第 1 步会得到一个**部分选中**的 kmod 集合，
而 `Config-build.in` 里**一条 `select` 都没有**（0 条，对比
`tmp/.config-package.in` 里的 24268 条），kconfig 因此完全无法推导内核模块的依赖闭包。
于是 `comgt-ncm` 选中了 `kmod-usb-serial-option`，没人选中它需要的
`kmod-usb-serial-wwan`，四十分钟后 `package/kernel/linux` 在打包阶段炸掉：

```
Package kmod-usb-serial-option is missing dependencies for the following libraries:
usb_wwan.ko
make[2]: *** [modules/usb.mk:1019: …/kmod-usb-serial-option_6.6.144-r1_x86_64.ipk] Error 1
ERROR: package/kernel/linux failed to build.
```

自洽的状态只有两个：kmod 全选（上游一致，但慢），或者 kmod 一个都不选。脚本走后者，
并在 `make defconfig` 之后断言 kmod / firmware / u-boot 三项计数都是 0，**不为 0 就
直接退出非零**——比四十分钟后再发现便宜得多。这一条以前只是打印 warning，代价是它在
CI 里警告了无数次而没人看见，构建照旧把内核模块全编了一遍。

## 三、构建

```sh
make package/hermes-agent/compile V=s -j"$(nproc)"
make package/luci-app-hermes-agent/compile V=s -j"$(nproc)"
```

产物：

| OpenWrt | 路径 | 文件名 |
| --- | --- | --- |
| 25.12 | `bin/packages/<arch>/hermes/` | `hermes-agent-<ver>-r<rel>.apk` |
| 24.10 | `bin/packages/<arch>/hermes/` | `hermes-agent_<ver>-r<rel>_<arch>.ipk` |

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

装了 PyYAML 时它还会体检 `.github/workflows/*.yml`：解析 YAML、把每个 `run:` 块里的
`${{ … }}` 替换成一个惰性词之后交给 `bash -n`、并核对 workflow 里引用的每个
`scripts/*.sh|py` 都存在。这三样都是「一小时后才炸」的那类错误——GitHub 对解析不了的
workflow 是**静默忽略**的（不运行、不报错、Actions 页里也看不出来），`run:` 里少一个
`fi` 要等那一步真的跑到，而一个改了名的脚本会在四条腿都绿了之后、在发版的最后一个
job 里才炸。

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

### QEMU 安装测试（真内核、真 procd、真 LuCI 会话）

冒烟测试没有内核、没有 procd、没有 uhttpd，也没有 rpcd 的 ACL。这一层把这些补上：

```sh
sh scripts/vm/run.sh ~/hermes-build/sdk/sdk-25.12-x86_64
```

它下载官方 kernel + `ext4-rootfs.img.gz`（版本同样从 SDK 的 `CONFIG_VERSION_REPO`
读），把镜像撑到 2 GB，用 `debugfs` 注入 root 口令、ssh 公钥和一份让 br-lan 走 DHCP
的 `rc.local`，启动 QEMU，把两个包 `cat` 进 guest 后 `apk add --allow-untrusted`
（**其余依赖从官方 feed 解析**——这正是它能证明 `DEPENDS` 写对了的原因），打开
`serve.enabled`、起服务、等网关和桥连上，最后调用 `scripts/vm/luci-check.sh`：

```sh
sh scripts/vm/luci-check.sh http://127.0.0.1:8080 hermes-vm   # 也可以单独跑
```

`luci-check.sh` 走的是浏览器那条路，不是 `ubus call`：POST 登录拿 `sysauth_*`
cookie，拿它当 ubus session id 打 `/ubus/`，验三个视图的 JS 资源、三个页面的
dispatcher、菜单项、七个方法、`settings_set` 的真实落盘与「不该动的行没动」、聊天
往返，再断言 `file.exec` 被 ACL 拒（`"result":[6]`）、`shell.exec` 被插件白名单拒、
登出后 session 立刻失效。退出码是失败项数，当前 26 项。

跑完 VM 默认**留着**，方便真的用浏览器点一遍（`VM_KEEP=0` 则跑完关机）：

| 环境变量 | 默认 | 说明 |
| --- | --- | --- |
| `QEMU` | PATH 里的 `qemu-system-x86_64` | 见下面的免 root 装法 |
| `VM_PASSWORD` | `hermes-vm` | guest 的 root 口令，LuCI 也用它 |
| `VM_SSH_PORT` / `VM_HTTP_PORT` | 2222 / 8080 | 宿主侧端口 |
| `VM_HTTP_BIND` | `127.0.0.1` | 想从别的机器开浏览器看才改成 `0.0.0.0`——guest 的 root 口令是已知的 |
| `VM_DISK` / `VM_MEM` / `VM_CPUS` | 2G / 2048 / 4 | 装完要 226 MB，2G 够 |
| `VM_KEEP` | 1 | 0 = 跑完关机 |

**不需要 root。** 这台构建机上的 qemu 是把 Arch 的 `.pkg.tar.zst` 解到
`~/hermes-build/vm/prefix` 得到的——qemu 按二进制的相对路径找 `../lib/qemu`、
`../share/qemu`，所以解包即可用；`/dev/kvm` 只要组权限（没有就退回 TCG，只是慢）。
`LD_LIBRARY_PATH` 别全局导出，否则 curl / ssh / e2fsprogs 也会去那个 prefix 里取
glib 和 openssl；包一层脚本再用 `QEMU=` 指过去：

```sh
cat > ~/hermes-build/vm/qemu-wrap.sh <<'EOF'
#!/bin/sh
P=~/hermes-build/vm/prefix
LD_LIBRARY_PATH=$P/usr/lib exec "$P/usr/bin/qemu-system-x86_64" "$@"
EOF
chmod +x ~/hermes-build/vm/qemu-wrap.sh
QEMU=~/hermes-build/vm/qemu-wrap.sh sh scripts/vm/run.sh ~/hermes-build/sdk/sdk-25.12-x86_64
```

从零到 26 项全绿约两分钟（其中 `apk add` 一分多钟）。出问题先看工作目录（默认
`/tmp/hermes-vm`）里的 `serial.log`（内核和 procd 的全部输出）与 `apk.log`；
guest 里 `logread -e hermes` 是第二站。CI 不跑这一层——它要嵌套虚拟化，
或者忍受 TCG 的速度——这是发版前手动跑的一层。

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

### runner 上的 git 都要带 token

两个 workflow 里凡是会 clone github.com 的地方，都必须走认证。**匿名** git over
HTTPS 是按来源 IP 限流的，而 runner 的出口 IP 属于整个 Actions 机群，所以在笔记本上
一次成功的 clone 到了 runner 上会直接吃 `HTTP 429`。这吃过一次亏：第一次发版死在
`lint` 里，`sync-deps.py --ref` 自己去 clone 上游被限流。踩点有两处，都已处理：

- `lint`：先从 Makefile 读出 pin 的 commit（顺手断言它是 40 位全 sha——写成 tag 或
  分支的话，明天构建出来的就是另一个东西），用 `actions/checkout` 取上游到
  `upstream/`（带本次运行的 token，只取那一个 commit），再 `--source upstream --check`。
  checkout 之后会核对 `git -C upstream rev-parse HEAD` 等于那个 pin，否则 `--check`
  只会报「生成物过期」，把人引向一个根本不存在的手改。
- `build` ×4：`PKG_SOURCE_PROTO:=git` 意味着 **SDK 自己也要 clone 上游**，而且发生在
  工具链已经编完之后。所以编译前先
  `git config --global url.https://x-access-token:$TOKEN@github.com/.insteadOf`，
  把 github.com 的流量挪到按 token 计的额度上。wheel 走 files.pythonhosted.org，
  不受影响。

本地手工升级仍然用 `--ref`，它自己 clone；限流时会退避重试三次，最终失败的报错里直接
写着「可以改用 `--source`」。

### 发版：`.github/workflows/release.yml`（只能手动触发）

Actions → **release** → Run workflow。没有任何 push 会触发它——发版是一个决定，不是
提交的副作用。两个可选输入：

| 输入 | 默认 | 说明 |
| --- | --- | --- |
| `tag` | `v<PKG_VERSION>-r<PKG_RELEASE>` | 从两个 Makefile 读；版本必须一致，`PKG_RELEASE` 取较大的那个（现在是 `v0.20.5-r2`）。tag 或同名 release 已存在就直接失败，不覆盖已经有人下载过的产物 |
| `highlights` | 空 | 一段 Markdown，放在 release 说明最上面 |

顺序是 `prepare`（解析并占住 tag）→ `lint` → `build` 四条腿 → `release`。
tag 的合法性和重名在**花掉一小时构建之前**就检查完；`release` job `needs` 全部四条腿，
所以任何一条红了就既没有 tag 也没有 release，没有半成品要清理。构建腿里刻意**没有**
`if: always()`——`build-info.env` 只在这条腿所有检查都过了之后才写出来，它的存在就是
「这条腿全绿」的凭据。全流程只有最后一个 job 有 `contents: write`。

产物在上传前会**改名**：

```
hermes-agent_0.20.5-r1_openwrt-25.12_x86_64.apk
luci-app-hermes-agent_0.20.5-r2_openwrt-24.10_aarch64_generic.ipk
```

因为 apk 的文件名是 `<包>-<版本>-r<rel>.apk`，**里面根本不带架构**——两条 25.12 的腿
会产出内容不同、名字完全一样的文件，而一个 release 是一个扁平命名空间。两个包管理器
都从包内部读元数据，所以改名不影响安装（但 `apk add` 的 glob 要写成 `hermes-agent[-_]*`）。
`release` job 另外断言了：四条腿都在、8 个包、没有重名。

说明由 `scripts/release-notes.sh` 生成，里面的每个数字都是从产物和工作树里读出来的
（包版本读 Makefile、依赖闭包数读 `deps.lock.json`、SDK 版本和 Python 小版本读每条腿
写下的 `build-info.env`），没有一处是手抄的。想在发版前看一眼渲染效果，本地就能干跑：

```sh
d=$(mktemp -d); mkdir "$d/leg"
cp sdk/bin/packages/*/hermes/*.apk "$d/leg/"
printf 'release=25.12\narch=x86_64\nfmt=apk\nsdk_version=25.12.5\npython=3.13\nartifacts_check=pass\nsmoke=pass\n' \
	> "$d/leg/build-info.env"
sh scripts/release-notes.sh "$d" v0.0.0-test | less
```

它不联网、不碰 GitHub API，缺 `GITHUB_REPOSITORY` 时链接自动退化成纯文件名。

`release.yml` 里的构建矩阵是 `build.yml` 的一份**副本**，不是 `workflow_call`：这样
push/PR 的门禁保持原样，也不会因为改 CI 而影响一次发版。重复的只是胶水（apt 包、
下载 SDK、挂 feed），真正有知识含量的部分（`sdk-trim-config.sh`、`check-artifacts.sh`、
`smoke/run.sh`）都在 `scripts/` 里，两个 workflow 调的是同一份。哪天胶水开始漂移，
就把 `build.yml` 改成可复用 workflow，而不是手工同步两份。

## 七、多 SDK 批量构建（可选）

同时维护四个 SDK 时，两个小脚本能省很多事——挂 feed / 修 config 一份，构建一份：

```sh
./hookup.sh   sdk-25.12-x86_64      # feeds + trim + defconfig
./buildall.sh sdk-25.12-x86_64 5    # 两个包 + check-artifacts，日志落到 log/
```

四个目标可以并行跑（每个 `-j5` 左右，避免互相抢核）。构建耗时长，务必用
`nohup ... &` detach 后轮询日志，不要让远程 shell 一直挂着。
