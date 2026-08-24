# 移植决策记录（PORTING.md）

这份文档记录**每个不显然的选择为什么是这样**。要改这个 feed 之前值得先读一遍——
下面大部分决定都是撞过墙之后倒推出来的，从代码本身看不出来。

对应上游版本：Hermes Agent 0.20.5，commit
`30d4555085ec684ff140d5841b5456b5d2291a72`（2026-08-23）。

## 0. 两条硬规则

一切都是从这两条推出来的：

1. **不改上游一行源码。** 没有 `patches/` 目录，也不应该有。
2. **升级必须便宜。** 跟一个新版本的成本必须是「跑一个脚本 + 改两行版本号」。

规则 1 是规则 2 的前提。补丁是会腐烂的：上游动一次 `setup.py` 的结构，补丁就要重
写一次，而这件事会发生在你最没空的时候。所以只要有可能，就用上游自己提供的机制。

## 1. 不改源码是怎么做到的

Hermes 已经被 nix 和 Homebrew 打包过，这意味着上游**已经**为「不在源码树里运行」
准备了接口。我们不是在钻空子，是在用官方契约：

| 上游变量 | 作用 | 我们的值 |
| --- | --- | --- |
| `HERMES_NIX_BUILD=1` | 解开 `setup.py` 里的打包守卫 | 构建期 |
| `HERMES_BUNDLED_SKILLS/PLUGINS/LOCALES` | 资源目录（否则回退到源码树布局） | `/usr/share/hermes-agent/*` |
| `HERMES_OPTIONAL_MCPS` / `HERMES_OPTIONAL_SKILLS` | 可选资源 | 同上 |
| `HERMES_HOME` | 状态根目录，上游明确支持指到 `~/.hermes` 之外 | `/srv/hermes` |
| `HERMES_PYTHON` / `HERMES_BIN` / `HERMES_REVISION` | 自举与版本上报（没有 `.git`） | 固定值 |
| `HERMES_DASHBOARD_SESSION_TOKEN` | `/api/ws` 的凭据 | init 生成的 token |
| `HERMES_DISABLE_LAZY_INSTALLS=1` | 禁掉运行期 pip | 恒开 |
| `HERMES_SKIP_NODE_BOOTSTRAP=1` | 没装 node 时别去联网装 nvm/fnm | 条件设置 |

全部由 `/usr/bin/hermes` 这个 wrapper 注入。**wrapper 就是整个移植的核心机制**，
Makefile 只是把文件放到位。

故意**不设**的两个：`HERMES_WEB_DIST` 和 `HERMES_TUI_DIR`。我们不打包 React 仪表盘
和 Node TUI，`hermes serve` 本身就是 headless 的（它自己设 `HERMES_SERVE_HEADLESS=1`
并跳过 SPA 挂载），所以「不设」是正确的信号，不是遗漏。

`web_dist` 不打包这件事直接由规则 2 决定：它需要 node/npm 预构建。一旦引入，每次
升级都要跑一遍前端构建，而 LuCI 界面本来就要做，做两套 UI 没有意义。

### 第三个故意不设的：`HERMES_MANAGED`

看起来它就是为我们准备的：设 `HERMES_MANAGED=opkg` 会让 `detect_install_method()`
直接返回这个名字，`hermes --version` 里那句 `Install method: unknown` 会变得好看，
而且所有惰性安装、自更新的入口都会给出「由包管理器管理」的正确拒绝信息。

但它同时会关掉 `save_env_value()`——`hermes_cli/config.py` 里这个函数第一行就是
`if is_managed(): managed_error(...); return`，也就是**任何环境变量都写不进去**。
`hermes login` 存不了凭据，Hermes 侧一切靠 `.env` 持久化的东西全部失效；顺带被门禁
的还有 `hermes update`、`gateway setup/service install`、`setup wizard`、
`dashboard register`、`gateway enroll`、`plugins install`。

代价远大于收益，所以不设，`Install method` 就停在 `unknown`。另外那个
`<install tree>/.install_method` 标记文件也不是出路：它只接受
{apt, docker, nix, nixos, home-manager, git, unknown} 六个值，`opkg` 根本表达不了。

### OpenWrt 的 python3 缺一个标准库模块

`files/shims/webbrowser.py`。这不是给 Hermes 打补丁，是**补标准库**：OpenWrt 把
CPython 标准库拆成二十来个子包，而 `webbrowser.py` 一个包都没有收
（`apk search python3` 里没有 `python3-webbrowser` 这种东西）。上游在
`hermes_cli/auth.py` 和 `hermes_cli/portal_cli.py` 里是**模块顶层** `import webbrowser`，
而 `main()` 构造参数解析器时会导入这两个模块——于是**每一条子命令**都会在开始之前死掉：

```
File ".../hermes_cli/portal_cli.py", line 24, in <module>
    import webbrowser
ModuleNotFoundError: No module named 'webbrowser'
```

`hermes --version` 是唯一的例外（它在建 parser 之前就短路返回了），所以这个 bug
能一路躲过构建、`check-artifacts.sh` 和 `hermes --version`，只有真正跑一条子命令
才现形——它是被 §10 的运行期冒烟测试抓出来的，这也是那套测试存在的理由。

shim 只实现被用到的 `open()`（11 处）和 `get()`（2 处），行为就照标准库文档里
「没有可用浏览器」那一档：`open()` 返回 `False`，`get()` 抛 `Error`。调用方本来就
处理这两种情况——打印 URL 让人自己去别的机器打开，在一台没有显示器的路由器上正好
是对的。

放在 `$PREFIX/shims/` 而不是 site-packages 里，wrapper 把它接在 `PYTHONPATH`
**最后**：这样它永远盖不住真正的依赖，而且一眼能看出「这不是依赖，这是 OpenWrt
的标准库缺口」。全量缺口列表（3.13 上 10 个）里，Hermes 另外引用到的只有 `msvcrt`
和 `winreg`，两个都只出现在缩进过的 Windows 分支里，永远不会执行，所以不用管。

## 2. 依赖：从 33 个包到 0 个包

**旧方案（已废弃）**：把每个 Python 依赖做成一个 `python3-*` OpenWrt 包，官方 feed
里有的复用、没有的 vendored——最后写了 33 个手工维护的 Makefile，还附带一张
「上游 pin 版本 vs feed 实际版本」的偏差表，十几行里有六七行标着 ⚠️（`websockets`
差了 4 个大版本、`psutil` 差了 2 个、`cryptography` 低于上游的 CVE 修复底线）。

这个方案违反规则 2 到了荒谬的程度：上游改一个 pin，这边要人肉核对 33 个文件；而且
它交付的东西**根本不是上游测过的依赖组合**。

**现方案**：整个依赖闭包由 `scripts/sync-deps.py` 从上游自己的 `uv.lock` 解析，生成
`deps/wheels-<abi>-<arch>.mk`，里面是带 sha256 的 `$(call Download,...)`。仓库里
没有任何手工维护的依赖表，版本与上游锁文件逐字一致。

```sh
python3 scripts/sync-deps.py --ref v0.21.0          # 重新生成
python3 scripts/sync-deps.py --ref <commit> --check  # CI：校验没人手改过生成物
```

代价是这些包不与系统共享（装两份 pyyaml），换来的是「上游测过的组合」和「升级
成本趋近于零」。在一个装了 Hermes 就没别的 Python 应用的路由器上，这个交换很划算。

### 为什么用 wheel + `installer`，而不是拷源码树

拷源码树进 site-packages 是最省事的做法，但会在运行期炸：上游多处调用
`importlib.metadata.version()`（`gateway/platforms/api_server.py`、
`tools/lazy_deps.py` 等），没有 `.dist-info/RECORD` 就抛 `PackageNotFoundError`。
所以走 `python -m installer`，它写真正的元数据。`check-artifacts.sh` 因此专门断言
`.dist-info` 目录数量 > 10——这是那次调试留下的哨兵。

### 为什么是 PYTHONPATH 而不是 venv

用户最初选的是「单包自带 venv」。实现时改成私有 site-packages + `PYTHONPATH`，
隔离效果完全一样（`PYTHONNOUSERSITE=1` 补上最后一个缺口），但省掉了 venv 需要的
解释器副本和一堆指向构建目录的绝对路径。`importlib.metadata` 在 `PYTHONPATH` 上
一样能找到 `.dist-info`，所以上一节的问题不会回来。

### 构建期的两个坑

- `--skip-dependency-check`：上游在 `build-system.requires` 里精确 pin
  `setuptools==83.0.0`。SDK 的 host setuptools 驱动的是同一个
  `setuptools.build_meta` 后端，而构建中途去 PyPI 抓一个 unpinned wheel 会同时
  破坏离线构建和可重现构建。
- `deps/*.mk` 必须在 `package.mk` **之后** include：每个 `$(call Download,...)`
  会把自己挂到 `DOWNLOAD_RDEP`（即 `$(STAMP_PREPARED)`）上，顺序错了 wheel 不会被
  下载。

## 3. 为什么只有 x86_64 和 aarch64

依赖闭包 60 个包里有 13 个不是纯 Python（`deps.lock.json` 里 `pure: false`）：
`cffi`、`cryptography`、`httptools`、`jiter`、`markupsafe`、`nemo-relay`、`pillow`、
`psutil`、`pydantic-core`、`pyyaml`、`ruamel-yaml-clib`、`uvloop`、`watchfiles`。
只有这两个架构有完整的 musllinux 预编译 wheel。其他架构要么在 SDK 里跑 Rust 交叉
编译（复杂度和 CI 时间都不成比例），要么缺包。所以 `DEPENDS` 里直接写
`@(x86_64||aarch64)`——在 menuconfig 里就看不见，比构建到一半失败友好。

Alpine 上构建的 wheel，部分 `.so` 的 `DT_NEEDED` 指向 `libc.musl-<arch>.so.1`。
OpenWrt 的同一份 musl 叫 `libc.so`，所以包里带一个
`/usr/lib/hermes-agent/compat/libc.musl-<arch>.so.1 → /lib/libc.so` 的软链，只在
wrapper 设的 `LD_LIBRARY_PATH` 里可见，不污染系统库命名空间。

> 实测记录：整个闭包的原生库依赖只差这**两个** soname（另一个是同一问题的另一
> 架构名）。另外，用 `patchelf` 改这些 `.so` 会让 `readelf` 后续读不出正确结果，
> 别走这条路——软链是干净的解法。

## 4. 为什么 `config.yaml` 在 `/srv/hermes` 而不是 `/etc`

因为 Hermes 会自己重写它，用的是**原子替换**（写临时文件再 rename）。放 `/etc` 下
再软链过去，第一次保存就把软链换成普通文件了。放 `/etc` 直接存也不行——它是
Hermes 的可写状态，不是管理员的配置。

所以分工是：`/etc/config/hermes-agent`（UCI，conffile）只放服务级设置
（enabled/host/port/log_level/workdir），Hermes 自己的一切在 `HERMES_HOME`。
两个配置文件通过 `/lib/upgrade/keep.d/hermes-agent` 在 sysupgrade 时保留，会话
数据库刻意不保留——它能长到几百 MB，进固件备份毫无道理。

API key 在 `/srv/hermes/.env`（0600），**不进 UCI**：`/etc/config` 全局可读，而且
会被 sysupgrade 备份打包带走。

## 5. 聊天通道：一次被证据推翻的设计

最初选的是 CGI 桥（用户也确认了这个方向）。它走不通，理由在 uhttpd 源码里：

`proc.c: uh_create_process()` 在 fork 的时候就
`uloop_timeout_set(&proc->timeout, conf.script_timeout * 1000)`，超时回调
`proc_timeout_cb()` → `uh_relay_kill()` → `SIGKILL`。关键是这个定时器
**不会因为有输出而重新装填**——默认 60 秒后无条件杀掉，不管进程正在好好地流式
输出。再加上 `/etc/config/uhttpd` 默认 `max_requests 3`，几个长连接就能把整个
LuCI 卡死。

改成常驻 daemon + 文件 IPC，但**保留了用户当初选择 CGI 时想要的每一条性质**：
只在回环、走 LuCI 会话鉴权、9119 永不出现在 LAN 上。

```
浏览器 (LuCI 会话)
   │  ubus over /cgi-bin/luci  →  ACL 逐方法放行
   ▼
rpcd ucode 插件  luci.hermes-agent
   │  文件 IPC：/var/run/hermes-chat/{req/,events,state}（0700）
   ▼
hermes-chatd（常驻，Python 3 标准库，零新依赖）
   │  ws://127.0.0.1:9119/api/ws?token=…
   ▼
hermes serve（procd 实例，bind 127.0.0.1）
```

浏览器侧 1 秒轮询增量读 `events`。网关本身会把 token delta 按 ~30fps 合批，所以
1 秒的轮询在观感上就是正常流式输出，不值得为此引入 SSE 或 websocket 代理。

桥属于 `luci-app-hermes-agent` 而不是 `hermes-agent`：它存在的唯一目的是服务网页
界面，只装 CLI 的人不需要它。

### `/api/ws` 的三道门，一行源码都没改

1. **即使在回环上也要求 `?token=`**（`_ws_auth_reason` 直接拒空 token）。上游默认
   每进程随机生成一个，只印在仪表盘 HTML 里——对我们不可达。但
   `_resolve_session_token()` 优先读 `HERMES_DASHBOARD_SESSION_TOKEN`，所以 init
   脚本自己生成 token 到 `/var/run/hermes-agent.token`（0600），wrapper 导出它。
2. **host / Origin 校验**：`Origin` 头不存在时直接放过。桥故意不发 `Origin`。
3. **peer 必须是回环**。桥就在本机。

token 每次开机重生成（`/var/run` 是 tmpfs），但 `restart` 时不重生成——否则会把
桥手里正拿着的 token 作废。

## 6. 安全边界

- 网关只 bind 回环，init 脚本拒绝任何非回环 `host` 并写 syslog，而不是启动一个
  LAN 上无鉴权、能执行 shell 的 agent 网关。
- **token 故意不用 `procd_set_param env` 传递。** 我们的 ACL 给了 `service list`
  读权限，而 verbose 的实例信息**会带上 env**——那等于把 token 发给任何已登录的
  LuCI 用户。这是个很容易犯的错，写在这里以免以后有人「顺手优化」。
- 浏览器能触达的网关方法有白名单，**两层**：ucode 插件一层（UI 实际用到的），
  `hermes-chatd` 一层（权威检查，它才是握着 socket 的那个）。同一条 JSON-RPC 通道
  上还有 `shell.exec`、`cli.exec`、`process.kill`，它们不在名单里。
- API key 在界面上是**只写**的：`settings_get` 只回报「有没有值」，从不把值送回
  浏览器，所以它不会出现在截图、代理日志或浏览器历史里。
- ucode 里所有外部命令走参数数组或 `shellquote()`，不拼字符串。

## 7. LuCI 三页，为什么不是四页

Overview（状态 + 启停 + 日志尾巴）、Chat、Settings。

日志没有单独一页：服务出问题时「状态」和「为什么」本来就是同一件事，为二十行
`logread` 多点一次菜单不值得。这也是从旧版本删掉 `logs.js` 的原因——
`check-artifacts.sh` 现在专门断言它**没有**从脏的 `PKG_BUILD_DIR` 里复活。

### ucode 的三个坑

1. `for (let x in array)` 拿到的是**值**不是下标，和 JavaScript 相反。插件里一律用
   显式下标循环，避免写出一个静默失效的白名单检查。
2. **全局函数是运行期解析的。** `rand()` 不是 ucode 的内建函数（它在可选的
   `ucode-mod-math` 里），但含有 `rand()` 的插件**编译完全通过**，直到真的有人点
   一次「发送」，那一行才抛 `Reference error: access to undeclared variable rand`，
   而 ubus 调用方看到的只有一句 `Unknown error`。真正的错误信息（连文件名和行号）
   在 **rpcd 的 stderr** 里，syslog 里也有——这是这个项目里最难找的一个 bug，
   因为构建、`check-artifacts.sh`、`ucode -c` 全都是绿的。
   现在 `check-sources.sh` 会把插件调用的每一个全局名字提取出来，在 `'use strict'`
   下逐个探测（非严格模式里读未声明变量只会得到 `null`，不报错，所以探测必须开严格
   模式）。队列文件名改用 `time()` + 进程内计数器 + 已校验过的请求 id，不再需要随机数。
3. **`ucode -T` 不是语法检查。** `-T` 的意思是「把输入当模板处理」，于是 `{% %}`
   之外的内容全是字面文本——喂给它一个纯垃圾文件也会原样打印并 `exit 0`。本仓库的
   静态检查一度用的就是它，等于什么都没查。编译检查是 `ucode -c -o /dev/null`。

## 8. 构建基础设施：三个吃掉一下午的坑

这几条在 [BUILD.md](BUILD.md) 里有操作说明，这里只记结论：

- **SDK 的包选择要同时改两个地方，改一个等于没改。** SDK 出厂就选中了全部 6683 个
  包（1084 个 kmod、188 个 firmware、rockchip 上 35 个 u-boot）。
  `Config-build.in` 把每个包符号声明成没有 prompt 的形式，kconfig 对不可见符号一律
  忽略用户值——所以 `.config` 里的 `=n`、`# ... is not set`、删行、`CONFIG_ALL=n`
  全都会被下一次 `make defconfig` 还原（三种方式独立验证过）。但 feed 里的包在
  `tmp/.config-package.in` 里**另有一份带 prompt 的声明**，带 prompt 的符号 kconfig
  是尊重 `.config` 旧值的，而出厂 `.config` 里它们全是 `=m`。于是正确的做法是
  「改 `Config-build.in` 的 default + 删掉 `.config` 里的 `CONFIG_PACKAGE_*` 行」
  两步一起做，`scripts/sdk-trim-config.sh` 就是这个（留 `.pristine` 备份，
  之后 6683 → 64 个包，正好是我们的依赖闭包）。
- **只裁一半比不裁更糟。** `Config-build.in` 里**一条 `select` 都没有**（0 条，
  对比 `tmp/.config-package.in` 的 777 条），所以内核模块的依赖闭包在那份声明里根本
  不存在。只把 kmod 的 default 改成 `n` 会留下一个部分选中的集合：`comgt-ncm` 选中
  `kmod-usb-serial-option`，没人选中它要的 `kmod-usb-serial-wwan`，四十分钟后
  `package/kernel/linux` 在打包阶段报 `missing dependencies … usb_wwan.ko`。
  四条腿里有三条是这么死的，剩下那条（25.12/x86_64）纯属运气。自洽状态只有全选或
  全不选，脚本走全不选并在 defconfig 之后断言 kmod 计数为 0。
- **`make` 会对所有已选中的包跑 prereq。** 于是 rockchip 上
  `uboot-rockchip` 缺 host `swig` / `python3-pyelftools` 就能让整个 feed 构建在开始
  之前失败。裁掉 u-boot 或装上那两个 host 包，二者其一（CI 里两样都做了）。

产物文件名两种格式分隔符不同（`.apk` 用 `-`，`.ipk` 用 `_`），别硬编码——旧的
apk workflow 断言 `hermes-agent_*.apk`，那个条件永远不可能成立。

## 9. 没做的事

| 项 | 原因 |
| --- | --- |
| 交互式终端 UI | Node/TypeScript 应用，与规则 2 冲突 |
| 上游 Web 仪表盘（`web_dist`） | 需要 node/npm 预构建，同上 |
| 消息平台 extras（telegram/discord/…） | 是上游 extras，需要 bot 凭据；要用的人自己往 `.env` 加 |
| x86_64 / aarch64 之外的架构 | musllinux wheel 覆盖不全，见 §3 |
| 与系统共享 Python 依赖 | 见 §2，是刻意的取舍 |

## 10. 怎么验证改动没坏

三层，越往下越慢，但抓到的东西也越靠后：

```sh
sh scripts/check-sources.sh                  # 几秒，不需要 SDK
sh scripts/check-artifacts.sh <sdk-dir>      # 构建后，解包核对
sh scripts/smoke/run.sh <sdk-dir>            # 真 rootfs 里跑起来
```

第一个脚本交叉验证四件只有在真机上才会暴露的事：菜单指向的视图文件存在、视图调用
的 ubus 方法在 `acl.d` 里放行了、放行的方法 ucode 插件真的实现了、插件调用的每个
ucode 全局函数真的存在（§7 第 2 条那个 bug 的静态版本）。第二个脚本解开
两个包，逐条核对 Makefile 承诺的文件真的在里面——**少一行 `$(INSTALL_BIN)` 不会让
构建失败，只会装出一个「能装、但什么都没有」的包**，这是这个项目最容易掉进去的坑。

第三个是运行期冒烟测试：把两个 `.apk` 装进一份真的 OpenWrt x86_64 rootfs，在
bubblewrap 沙箱里用**目标自己的 musl 和 python3** 跑起来。它覆盖的是前两层原理上
看不到的东西——wheel 能不能在 OpenWrt 的 musl 下加载、rpcd 认不认这个 ucode 插件、
网关和桥的 websocket 握手到底能不能成。`webbrowser` 那个 bug（§1）就是它抓的：包
是完整的、文件一个不少、`hermes --version` 也正常，但任何一条子命令都跑不起来。

沙箱选 bwrap 不是偏好：这台构建机上非特权 `unshare -rm` 里 `/proc`、`/sys`、`/dev`
一个都挂不上（分别是 EPERM 和 EINVAL），bwrap 干的就是这件事。它只能测 x86_64，
aarch64 的两条腿靠构建矩阵和 `check-artifacts.sh` 兜。沙箱里唯一起不来的是
`logd`（要读 `/proc/kmsg`，而且它的 `setgid()` 在 bwrap 只映射一个 uid 的用户命名
空间里返回 EINVAL），所以 `logread` 永远是空的——需要看 init 脚本 `logger` 输出的
那一步改成用 PATH 顶一个 `logger` stub，而不是假装 syslog 能用。

CI（`.github/workflows/build.yml`）：一个 `lint` job 跑第一个脚本，加上 4 条腿的
构建矩阵，每条腿跑 `check-artifacts.sh`，其中两条 x86_64 的腿再跑一遍冒烟测试
（runner 上 `apt install bubblewrap` 即可，只多两三分钟）。aarch64 那两条腿跑不了
第三层，原因同上。Ubuntu 24.04 的 runner 用 AppArmor 限制了非特权用户命名空间，
所以那一步先 `sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`——不做的话
bwrap 起不来，而且报的错跟我们的包一点关系都没有。

顺带说一句：`lint` job 里那个 `apt-get install ucode` 是 best-effort，Ubuntu 通常
没有这个包，于是 CI 的第一层会退回 node 近似检查，ucode 全局探测也就跳过了。真正
执行这项检查的地方是冒烟测试——那里的 rootfs 一定有 ucode 二进制，而且探的是**已
安装**的插件。这个分工是故意的，别指望 lint job 抓到 `rand()` 那类问题。
