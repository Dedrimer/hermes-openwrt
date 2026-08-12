# hermes-openwrt

将 [Nous Research 的 Hermes Agent](https://github.com/nousresearch/hermes-agent)
（v0.20.0，MIT，Python ≥3.11,<3.14）移植为 **OpenWrt 原生包**（非 Docker）：

- 同一份 feed Makefile 在 **OpenWrt 24.10** 构建系统产出 **`.ipk`**（opkg），在 **OpenWrt 25.12** 构建系统产出 **`.apk`**（apk-tools 2.x）——双格式由双分支构建系统天然支持，无需维护两套代码
- 守护进程走 **procd**，数据目录 `HERMES_HOME=/etc/hermes`（uci 可配两个实例：`gateway` 与可选 `dashboard`）
- **LuCI 管理界面**（luci2 JS 视图 + rpcd ucode RPC 后端）：状态 / 设置 / 日志
- 提供 `hermes` CLI、`hermes-agent`、`hermes-acp` 三个入口

> 注意：本项目是 **feed 源码 + CI 工作流**，本身不是二进制发布。需要把仓库推送到
> GitHub 启用 Actions（或本地 SDK 构建，见 docs/BUILD.md）才能得到 ipk/apk 产物。

## 功能范围（MVP）

| 功能 | 状态 |
| --- | --- |
| `hermes` CLI（全部子命令） | ✅ 完整打包 |
| `hermes gateway run` 守护（procd，自动重启） | ✅ uci 控制 |
| `hermes serve` headless 面板（默认 9119 端口） | ✅ uci 控制 |
| LuCI：状态页（实例/版本/磁盘 + 启停按钮） | ✅ |
| LuCI：设置页（uci + API Keys + config.yaml） | ✅ |
| LuCI：日志页（logread 过滤） | ✅ |
| 消息平台（Telegram/Matrix/Slack 等 extras） | ⏳ 后续（见 docs/PORTING.md） |

## 目录结构

```
hermes-openwrt/
├── packages/                        # feed 根（src-link 目标）
│   ├── hermes-agent/                # 主包：Makefile + 补丁 + procd init + uci 配置
│   ├── luci-app-hermes-agent/       # LuCI 应用（JS 视图 + ucode RPC + menu/acl）
│   └── lang/
│       ├── python/                  # vendored 的 33 个 python3-* 依赖包 + 构建系统 mk
│       └── rust/                    # rust-values.mk（上游同文件参考副本）
├── scripts/                         # 元数据抓取 / Makefile 生成器（维护用）
├── docs/
│   ├── BUILD.md                     # 本地 SDK 构建方法
│   ├── INSTALL.md                   # 安装与配置（opkg / apk）
│   └── PORTING.md                   # 移植决策、命名规则、版本偏差表
└── .github/workflows/
    ├── build-ipk.yml                # 24.10 SDK → .ipk（x86/64 + mediatek/filogic）
    └── build-apk.yml                # 25.12 SDK → .apk（同上矩阵）
```

## 快速开始

### 方式一：GitHub Actions（推荐）

1. 把本仓库推到 GitHub
2. 打开 **Actions** 页签 → 选择 `build-ipk (OpenWrt 24.10)` 或 `build-apk (OpenWrt 25.12)` → **Run workflow**
3. 构建完成后（约 1–2 小时）在 workflow 的 artifact 里下载 `ipk-24.10-*` / `apk-25.12-*`（包含 hermes-agent、luci-app-hermes-agent 及其全部依赖）
4. 把整个 `bin/packages/` 树 scp 到路由器，`opkg install` / `apk add` 安装（详见 docs/INSTALL.md）

### 方式二：本地 SDK

见 docs/BUILD.md。

## 安装后（30 秒上手）

```sh
# 启用 gateway 与 dashboard 两个实例并启动
uci set hermes-agent.gateway.enabled=1
uci set hermes-agent.dashboard.enabled=1
uci commit hermes-agent
/etc/init.d/hermes-agent restart

hermes --version                 # 验证 CLI
/etc/init.d/hermes-agent status  # procd 状态
```

- Web 面板：http://<路由器IP>:9119/（非回环绑定需 `--insecure` 语义，见 uci `dashboard.insecure`）
- LuCI：**Services → Hermes Agent**（状态 / 设置 / 日志）
- 数据目录 `/etc/hermes/`：`config.yaml`、`.env`（API keys）、`profiles/`、`logs/`
- 首次运行需要配置 LLM provider：在 LuCI 设置页填 API Key，或直接编辑
  `/etc/hermes/config.yaml` 与 `/etc/hermes/.env`

## 重要说明与风险

- **体积**：Python 全栈安装后约 30–60 MB，建议 extroot/USB 或 flash 充裕的设备
- **版本偏差**：hermes 对依赖是精确 pin；OpenWrt 官方 feed 的版本可能更旧/更新，
  运行期如有不兼容再逐个 vendor（现状记录在 docs/PORTING.md 偏差表）
- **pydantic-core / jiter**：Rust 扩展，使用预编译 musllinux wheel（aarch64 /
  x86_64 / armv7l），无需在 OpenWrt 里跑 Rust 工具链
- **构建验证**：本机开发环境（Windows）无 OpenWrt 工具链，编译验证依赖 CI；
  首次 CI 跑通后产物即为正式 ipk/apk
- 上游的 `pip`/`uv`/Docker/Nix 分发方式不适用于 OpenWrt，`setup.py` 的
  构建守卫通过补丁绕过（见 packages/hermes-agent/patches/）

## 许可证

- hermes-agent：MIT（上游）
- LuCI 应用：Apache-2.0（参照 luci 惯例）
- feed 内 make 文件与脚本：GPL-2.0（OpenWrt 惯例）
