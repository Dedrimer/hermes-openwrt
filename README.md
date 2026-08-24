# hermes-openwrt

把 [Nous Research 的 Hermes Agent](https://github.com/NousResearch/hermes-agent)
移植成 **OpenWrt 原生包**（不是 Docker、不是 chroot），外加一个 LuCI 界面。

两个包：

| 包 | 内容 |
| --- | --- |
| `hermes-agent` | Hermes 本体 + 完整 Python 依赖闭包（私有 site-packages）+ procd 服务 + UCI 配置 |
| `luci-app-hermes-agent` | LuCI 三个页面 + rpcd ucode 后端 + `hermes-chatd` WebSocket 桥 |

整个仓库遵守两条硬规则，其余设计都是从它们推出来的：

1. **不改上游一行源码。** 没有 `patches/` 目录。`setup.py` 里的打包守卫用上游自己
   给发行版打包者留的 `HERMES_NIX_BUILD=1` 解开，运行期资源路径用上游 nix/Homebrew
   打包已经在用的 `HERMES_BUNDLED_*` 环境变量注入。
2. **升级必须便宜。** 所有 Python 依赖都由 `scripts/sync-deps.py` 从上游自己的
   `uv.lock` 解析生成，仓库里没有任何手工维护的依赖表。

跟一个新的 Hermes 版本，完整流程就是三行：

```sh
python3 scripts/sync-deps.py --ref v0.21.0     # 重新解析依赖，生成 deps/*.mk
# 把它打印出来的 PKG_VERSION / PKG_SOURCE_VERSION 填进 packages/hermes-agent/Makefile
make package/hermes-agent/compile               # 在 SDK 里重编
```

## 支持的目标

只有 x86_64 和 aarch64。这不是偷懒：依赖闭包里 60 个包中有 13 个是原生扩展
（`pydantic-core`、`jiter`、`cryptography`、`uvloop`、`watchfiles` 等 Rust/C 扩展），
只有这两个架构有完整的 musllinux 预编译 wheel，其他架构要在 SDK 里跑 Rust 工具链，
代价与收益完全不成比例。

| OpenWrt | 包格式 | Python | 已验证目标 |
| --- | --- | --- | --- |
| 24.10.x | `.ipk`（opkg） | 3.11 | `x86/64`、`rockchip/armv8` |
| 25.12.x | `.apk`（apk-tools v3） | 3.13 | `x86/64`、`rockchip/armv8` |

同一份 Makefile 覆盖四种组合，`.github/workflows/build.yml` 的矩阵就是这四条。
跨大版本的 Python 小版本差异（3.11 / 3.13）由 `HERMES_PY_TAG` 自动选择对应的
wheel 集合，这也是矩阵一定要同时跑两个 OpenWrt 分支的原因。

## LuCI 界面

**Services → Hermes Agent**，三页：

- **Overview**：服务状态 / 开机自启 / 桥的连接状态 / 版本 / 监听地址 / 数据目录 /
  剩余空间，加启停按钮，页面底部直接带 `logread` 尾巴。日志没有单独做一页——服务
  出问题时状态和原因本来就是一件事，为二十行日志多点一次菜单不值得。
- **Chat**：在 LuCI 里直接跟 agent 对话。流式输出、思考过程、工具调用、审批
  请求（allow once / this session / always / deny）、追问（clarify）都在这一页里渲染。
- **Settings**：UCI 服务参数、各 provider 的 API Key、`config.yaml` 直接编辑。
  Key 是**只写**的：`settings_get` 只回报"这个 key 有没有值"，从不把值送回浏览器，
  所以它不会出现在截图、代理日志或浏览器历史里。

上游自带的 Web 仪表盘（`web_dist`）**不打包**——它需要 node/npm 预构建，会把
"跟着上游升级"这条规则毁掉。LuCI 就是界面。

## 聊天是怎么接通的

Hermes 的网关只监听回环，端口从不出现在 LAN 上。浏览器与它之间隔着两层：

```
浏览器 (LuCI 会话)
   │  ubus over /cgi-bin/luci  →  ACL: luci.hermes-agent.chat_send / chat_poll
   ▼
rpcd ucode 插件  luci.hermes-agent
   │  文件 IPC：/var/run/hermes-chat/{req/,events,state}（0700）
   ▼
hermes-chatd（常驻，Python 3 标准库，无新依赖）
   │  ws://127.0.0.1:9119/api/ws?token=…
   ▼
hermes serve（procd 实例，bind 127.0.0.1）
```

**为什么不是 CGI。** 最初的设计是一个 CGI 桥，实测走不通：uhttpd 的
`proc.c:uh_create_process()` 在 fork 时就 `uloop_timeout_set(&proc->timeout,
script_timeout * 1000)`，超时回调直接 `SIGKILL`，而这个定时器**不会因为有输出而
重新装填**（默认 60 秒），再加上 `/etc/config/uhttpd` 默认 `max_requests 3`。
长连接和流式输出在 CGI 里没有出路，所以改成常驻进程 + 文件 IPC，浏览器侧用
1 秒轮询增量读取事件日志。网关本身会把 delta 按 ~30fps 合批，1 秒的轮询延迟在
观感上就是正常的流式输出。

`/api/ws` 的三道门都在不改源码的前提下过掉了：它**即使在回环上也要求** `?token=`，
而 `_resolve_session_token()` 优先读 `HERMES_DASHBOARD_SESSION_TOKEN`，所以 token 由
init 脚本每次启动时生成到 `/var/run/hermes-agent.token`（0600），`hermes-wrapper`
导出它；`Origin` 头不存在时 host 校验直接放过，所以桥故意不发 `Origin`；peer 必须
是回环，桥就在本机。

## 安全边界

- 网关只 bind 回环，init 脚本拒绝任何非回环 `host`，直接报错而不是启动一个
  LAN 上无鉴权的 agent 网关。
- token 写在 `/var/run`（tmpfs，每次开机重生成），**故意不用** `procd_set_param env`
  传递：我们的 ACL 给了 `service list` 读权限，verbose 的实例信息会带上 env，
  那等于把 token 发给任何已登录的 LuCI 用户。
- 浏览器能点到的网关方法有白名单，两层：ucode 插件一层（UI 实际用到的 11 个），
  `hermes-chatd` 一层（权威检查，它才是握着 socket 的那个）。同一条 JSON-RPC 通道上
  还有 `shell.exec`、`cli.exec`、`process.kill`，它们不在名单里。
- API Key 存 `/srv/hermes/.env`（0600），**不进 UCI**：`/etc/config` 全局可读，
  而且会被 sysupgrade 备份打包带走。

## 关键路径

| 路径 | 内容 |
| --- | --- |
| `/srv/hermes/` | `config.yaml`、`.env`、会话数据库、缓存（Hermes 自己管，`HERMES_HOME`） |
| `/usr/lib/hermes-agent/` | 私有 site-packages、console scripts、musl soname 兼容软链 |
| `/usr/share/hermes-agent/` | `skills/`、`plugins/`、`locales/`、`optional-mcps/`、默认配置模板 |
| `/etc/config/hermes-agent` | 只放服务级设置（enabled/host/port/log_level/workdir） |
| `/var/run/hermes-chat/` | 桥的 IPC 目录（0700） |
| `/usr/bin/hermes` | 一个 wrapper，按 `$0` 分发；`hermes-agent`、`hermes-acp` 是它的软链 |

`config.yaml` 放在 `/srv/hermes` 而不是 `/etc`，因为 Hermes 会用原子替换重写它，
放到 `/etc` 下再软链过去会被它自己覆盖掉。两个配置文件通过
`/lib/upgrade/keep.d/hermes-agent` 在 sysupgrade 时保留；会话数据库刻意不保留，
它能长到几百 MB，没道理进固件备份。

## 构建与安装

- 本地 SDK 构建：[docs/BUILD.md](docs/BUILD.md)
- 安装与首次配置：[docs/INSTALL.md](docs/INSTALL.md)
- 移植决策、每个非显然选择的理由：[docs/PORTING.md](docs/PORTING.md)

不需要 SDK 也能先跑静态检查（几秒，能抓出 LuCI 视图语法错、菜单指向不存在的视图、
视图调用了 ACL 没放行的 ubus 方法、ucode 插件调用了根本不存在的全局函数这四类只有
在真机上才会暴露的问题）：

```sh
sh scripts/check-sources.sh
```

构建完成后验证产物内容（少一行 `$(INSTALL_BIN)` 不会让构建失败，只会装出一个
"能装、但什么都没有"的包）：

```sh
sh scripts/check-artifacts.sh /path/to/openwrt-sdk-…
```

再往上一层是运行期冒烟测试：把刚构建的两个包装进一份真的 OpenWrt x86_64 rootfs，
在 bubblewrap 沙箱里用目标自己的 musl 和 python3 跑起来，一路验到网关与桥的
websocket 握手和 `chat_send` → 网关 → `chat_poll` 的往返（需要 `bubblewrap`，
只能测 x86_64 SDK）：

```sh
sh scripts/smoke/run.sh /path/to/openwrt-sdk-…
```

## 已知取舍

- **体积**：装完约 60–90 MB（含依赖闭包与 bundled 资源），建议 extroot / USB /
  x86 软路由。`optional-skills`（约 9 MB）默认不装，menuconfig 里可开。
- **交互式终端 UI 不包含**：那是一个 Node/TypeScript 应用，与"跟着上游快速升级"
  的目标冲突。用 LuCI 的 Chat 页。
- musllinux wheel 是在 Alpine 上构建的，部分 `.so` 的 `DT_NEEDED` 指向
  `libc.musl-<arch>.so.1`。OpenWrt 的同一份 musl 叫别的名字，所以包里带一个
  只在自己 `LD_LIBRARY_PATH` 里可见的兼容软链，不污染系统库命名空间。

## 许可证

- Hermes Agent：MIT（上游）
- LuCI 应用：Apache-2.0（LuCI 惯例）
- feed 内的 make 文件与脚本：Apache-2.0
