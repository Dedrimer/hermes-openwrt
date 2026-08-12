# 移植记录（PORTING.md）

本文记录把 hermes-agent v0.20.0（tag `v2026.8.3`，commit
`3c27eb6234bf91b8ceee9e9071591b31e9b148cb`）移植到 OpenWrt 的决策、发现与偏差。
信息基于 2026-08 时点的上游代码与 openwrt/packages 两条分支（openwrt-24.10 /
openwrt-25.12）核对。

## 1. 目标与取舍

| 项 | 决策 | 原因 |
| --- | --- | --- |
| 分发 | OpenWrt 原生包（opkg/apk），非 Docker/pip/uv/Nix | 上游的分发方式都不适用于 OpenWrt |
| 构建系统 | 同一 feed Makefile，24.10 → `.ipk`，25.12 → `.apk` | 双分支构建系统天然产出双格式 |
| Python | 24.10 = 3.11.14，25.12 = 3.13.9（都在 hermes 的 `>=3.11,<3.14` 内） | python3-version.mk 自动适配 |
| 守护 | procd + uci，`HERMES_HOME=/etc/hermes` | 原生习惯，崩溃自动重启（respawn 3600 5 5） |
| LuCI | luci2 JS 视图 + rpcd ucode RPC 插件 | 24.10 与 25.12 都是 luci2 架构，单套文件兼容 |
| Rust 扩展 | pydantic-core/jiter 用预编译 musllinux wheel | 免去 buildroot Rust 工具链（交叉编译复杂度高、CI 慢） |
| 范围 | MVP = CLI + gateway + dashboard + LuCI；消息平台 extras 后续 | 控制首轮交付复杂度 |

## 2. 命名规则（重要）

**OpenWrt 24.10 起官方 packages feed 的 python 包统一用 `python-` 前缀**
（24.10 前是 `python3-`）。本 feed 内三种来源的包名：

| 来源 | 包名 | 例子 |
| --- | --- | --- |
| 官方 feed 复用 | `python-*` | `python-yaml`、`python-requests`、`python-certifi`、`pillow`（特殊，无前缀） |
| 本 feed vendored | `python3-*` | `python3-httpx`、`python3-pydantic`、`python3-openai` |
| python3 主包 stdlib 拆分包 | `python3-*` | `python3-sqlite3`、`python3-multiprocessing`（由 python3 主包 `files/python3-package-*.mk` 定义） |

- 修改任何 DEPENDS 时不要跨来源混用前缀
- 校验命令：`python scripts/gen-package-makefiles.py`（verify_depends 会提示
  requires_dist 与声明不一致）

## 3. 依赖策略

hermes 对直接依赖全部 **精确 pin**（`==X.Y.Z`）。策略：

1. **官方 feed 有的 → 复用**（版本可能偏差，见 §4 偏差表；pip 不做版本强制，
   OpenWrt 安装时同样不做）
2. **官方 feed 没有的 → vendored**（33 个包，见
   `docs/package-versions.json` 与 `packages/lang/python/`），版本对齐 hermes
   pin；传递依赖取打包时点的 PyPI 最新稳定版
3. **平台标记不匹配的自动跳过**：`concurrent-log-handler`/`pywin32`/`pywinpty`
   （win32 only）、`nemo-relay`（wheel-only + 平台标记，上游代码有兜底）、
   `pynacl`/`aiohttp`（仅消息平台 extras）
4. **tzdata** 特殊处理：hermes 只在 win32 声明，但 OpenWrt 缺
   `/usr/share/zoneinfo`，zoneinfo 需要 tzdata → 无条件 vendored
5. **stdlib 子包**：gateway 运行需要 `sqlite3`、`multiprocessing` 模块 →
   `+python3-sqlite3 +python3-multiprocessing`

### 修正记录（重要）

- **httpx2/httpcore2/truststore 已删除**：早期调研误判 "openai 2.24.0 依赖
  httpx2"。经 openai 2.24.0 wheel 反编译验证（`import httpx`，无 httpx2），
  hermes 源码与 uv.lock 也均无引用 → openai 走旧 `httpx 0.28.x` 树
  （python3-httpx 0.28.1 / python3-httpcore 1.0.9）
- **httpcore2 的 SSL 后端是 truststore 而非 certifi**（2.x 线）；旧线 httpx
  用 certifi

## 4. 版本偏差表

hermes pin（pyproject.toml，2026-08-03）vs 实际安装版本：

### 4.1 vendored（本 feed，精确对齐或取最新）

全部 vendored 包的版本记录在 `docs/package-versions.json`（由
`scripts/fetch-pypi-meta.py` 生成）。hermes 直接 pin 的 vendored 包均**精确
匹配**：openai 2.24.0、httpx 0.28.1、pydantic 2.13.4、pydantic-core 2.46.4、
rich 14.3.3、fire 0.7.1、tenacity 9.1.4、pyjwt 2.13.0、croniter 6.0.0、
pathspec 1.1.1、prompt-toolkit 3.0.52、tzdata 2025.3、pysocks 1.7.1。

### 4.2 官方 feed 复用（存在偏差，运行时需留意）

| hermes pin | 24.10 feed | 25.12 feed | 风险 |
| --- | --- | --- | --- |
| certifi 2026.5.20 | 2025.8.3 | 2026.1.4 | 旧证书包；TLS 失败时 `opkg update` 后重装 certifi |
| python-dotenv 1.2.2 | 1.0.1 | 1.0.1 | 低 |
| pyyaml 6.0.3 | 6.0.3 ✓ | 6.0.3 ✓ | 无 |
| ruamel.yaml 0.18.17 | 0.18.16 | 0.18.16 | 低 |
| requests 2.33.0（CVE-2026-25645 修复版） | 2.32.3 | 2.32.5 | ⚠️ 低于修复版；如受影响建议关注上游更新 |
| jinja2 3.1.6 | 3.1.4 | 3.1.6 ✓ | 低 |
| Markdown 3.10.2 | 3.7 | 3.10 | 低 |
| packaging 26.0 | 25.0 | 25.0 | 低 |
| urllib3 ≥2.7.0,<3（GHSA 修复底线） | 2.5.0 | 2.6.3 | ⚠️ 低于底线；hermes 多处依赖 |
| psutil 7.2.2 | 5.9.5 | 5.9.5 | ⚠️ 跨大版本（API 基本兼容） |
| websockets 15.0.1 | 11.0.3 | 11.0.3 | ⚠️ 跨大版本（服务端握手 API 有差异） |
| cryptography 48.0.1（CVE 修复） | 41.0.7 | 46.0.6 | ⚠️ 低于 hermes 底线（PyJWT crypto/WeCom 路径） |
| Pillow 12.3.0 | 10.2.0 | 12.1.1 | 低（仅图像工具） |

策略：先复用，运行期报错再个别 vendor（把该包加入本 feed 并改主包 DEPENDS）。

## 5. Rust 扩展（pydantic-core / jiter）

- 使用 **musllinux_1_1 wheel**（musl 编译，与 OpenWrt 的 musl libc 兼容，
  无 glibc 依赖），`PKG_UNPACK:=unzip` 解压后直接复制进 site-packages
- 覆盖矩阵：cp39–cp313 × {aarch64, x86_64, armv7l}（pydantic-core）；
  cp39–cp313 × {aarch64, x86_64}（jiter，无 armv7l wheel）
- 不支持的 {Python, ARCH} 组合在构建期 `$(error)` 失败（含明确提示），
  不会静默产出坏包
- 若未来需要 armv7l 的 jiter：唯一途径是 buildroot Rust 交叉编译
  （仿上游 python-orjson，feed 里 `lang/rust/rust-values.mk` 已备参考副本）

## 6. setup.py 构建守卫

上游 `setup.py` 拒绝非 Nix/安装器环境构建（wheel/sdist 分发受控）。
OpenWrt 的 Py3Build 走 PEP 517（`python3 -m build --no-isolation --wheel`），
会触发守卫 → 补丁 `0001-openwrt-bypass-build-guard.patch` 把
`_IN_NIX_BUILD` 判定恒置为 True（仅影响打包流程，不改变运行时行为）。
升级 hermes 版本时若 setup.py 结构变化需同步更新补丁。

## 7. procd / init 设计

- `USE_PROCD=1`，两个实例：`gateway`（`hermes gateway run --replace
  --external-supervisor`，退出码 ≠ 0 时 procd respawn）与 `dashboard`
  （`hermes serve --host ... --port ... --no-open`，非回环绑定加
  `--insecure`）
- `HERMES_HOME=/etc/hermes` 通过 procd env 注入；`HERMES_PROFILE` 仅当
  uci `profile` 非 default 时设置
- **实例级启停**：rc.common 把 `$1` 传给 `start_service`/`reload_service`，
  stop 经 `procd_kill <svc> <instance>` 只杀对应实例
- `procd_set_param file /etc/config/hermes-agent`：配置变更自动触发重启
- **注意**：`start <instance>` 是 procd set 语义（整服务定义替换），日常用
  无参 `start`/`restart`；LuCI 状态页只暴露服务级操作

## 8. LuCI（luci2 架构，24.10 与 25.12 共用一套文件）

- **菜单**：`menu.d` JSON，`admin/services/hermes-agent` 父项
  （firstchild + acl depends）+ status/settings/logs 三个 `view` 子项
- **RPC 后端**：rpcd ucode 插件 `/usr/share/rpcd/ucode/luci.hermes-agent`
  （无扩展名，同 luci-base 的 `luci` 文件惯例），返回
  `{ "hermes-agent": { status, action, logs, settings_get, settings_set } }`
  ——ubus 对象名由返回值 key 决定，与文件名无关
- **ACL**：`acl.d` 文件，read/write 按 ubus 方法级授权
  （`hermes-agent` 对象 5 个方法）＋ `uci: [hermes-agent]`（设置页走标准
  form.Map 的 uci 通道）
- **安全**：ucode 内所有 shell 命令经 `shellquote()` 转义；`settings_set`
  只接受白名单 env key（其余 .env 内容原样保留）；config.yaml 写入上限
  64 KiB 并先备份 `.bak`；`action` 只接受 start/stop/restart
- **版本显示**：postinst 写 `/etc/hermes/.version`（与 PKG_VERSION 同步）
- 升级本包后 rpcd 自动 reload（postinst 清理 luci 缓存 + rpcd reload）

## 9. 未移植 / 后续工作

| 项 | 说明 |
| --- | --- |
| 消息平台 extras | telegram/discord/slack/matrix/sms/teams 等依赖重且需 bot 凭据；属 hermes 的 extras，后续按平台逐个 vendor |
| jiter armv7l | 需要 Rust 交叉编译（见 §5） |
| 官方 feed 版本偏差 | 见 §4.2 表格；运行期不兼容时逐个 vendor |
| 25.12 apk 打包细节 | apk 的脚本钩子映射沿用 opkg 的 postinst 语义（仅创建本包目录/文件）；CI 实测确认 |
| pip 依赖的运行时降级检查 | `tools/lazy_deps.py` 等路径在缺包时静默降级（上游设计），不影响核心功能 |

## 10. 数据来源与复现

- `scripts/fetch-pypi-meta.py`：PyPI JSON API → `docs/package-versions.json`
  （版本/hash/许可证/requires_dist）
- `scripts/gen-package-makefiles.py`：JSON → 33 个 `python3-*` Makefile
  （含 verify_depends 交叉校验）
- 上游核对：openwrt/packages（openwrt-24.10 / openwrt-25.12 分支）与
  openwrt/openwrt（openwrt-24.10）sparse clone，保留在 `.tmp/`（不入库）
