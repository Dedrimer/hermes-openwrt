# 安装与配置指南（INSTALL.md）

## 一、安装

从 CI artifact（或本地构建）下载的 `bin/packages/` 树里包含：
`hermes-agent_*.ipk/.apk`、`luci-app-hermes-agent_*`、`python3-*`、
`python-*`、`luci-base` 等全部依赖。**必须整树安装**（或使用包管理器索引），
单独安装主包会因依赖缺失失败。

```sh
# 上传到路由器（假设 192.168.1.1，已开启 ssh/scp）
scp -r bin/packages root@192.168.1.1:/tmp/pkg/

# --- OpenWrt 24.10（opkg）---
cd /tmp/pkg && opkg install ./*.ipk

# --- OpenWrt 25.12（apk）---
cd /tmp/pkg && apk add ./*
```

> 也可以把整个 `bin/packages/<arch>/<feed>/` 目录复制到
> `/usr/local/packages/` 并写 `/etc/opkg/customfeeds.conf`（或 apk 的 repository
> 配置），然后 `opkg update && opkg install hermes-agent luci-app-hermes-agent`。

### 所需磁盘空间

- 安装后约 **30–60 MB**（Python 3 + 全栈依赖）
- flash 较小的设备建议：extroot/USB 挂载，或只装 `hermes-agent` 不装 LuCI 应用
- 构建机另有 30 GB 要求（见 BUILD.md）

## 二、配置（uci）

`/etc/config/hermes-agent`（安装时自动生成，属于 conffile，升级保留）：

```
config hermes 'gateway'
	option enabled '0'
	option profile 'default'    # HERMES_PROFILE（profiles 目录位于 /etc/hermes/profiles）

config hermes 'dashboard'
	option enabled '0'
	option bind '127.0.0.1'
	option port '9119'
	option insecure '0'         # 绑定非回环地址时需要
```

常用操作：

```sh
uci set hermes-agent.gateway.enabled=1
uci set hermes-agent.dashboard.enabled=1
uci set hermes-agent.dashboard.bind=0.0.0.0
uci set hermes-agent.dashboard.insecure=1
uci commit hermes-agent

/etc/init.d/hermes-agent restart

# 实例级控制（rc.common 实例参数）
/etc/init.d/hermes-agent start gateway     # 只启动 gateway
/etc/init.d/hermes-agent stop dashboard    # 只停止 dashboard
/etc/init.d/hermes-agent running           # 是否有实例在跑
/etc/init.d/hermes-agent status            # 详情
```

> 注意：`start <instance>` 会用该实例**替换** procd 服务定义（procd 的 set 语义），
> 之后再执行无参 `start` 才会把全部 enabled 实例注册回来。日常建议用
> `restart`（无参）或 LuCI 状态页按钮。

## 三、LLM Provider 配置（第一步必做）

数据目录：`/etc/hermes/`（权限 700，root only）

1. **API Keys** —— 写到 `/etc/hermes/.env`（或 LuCI 设置页）：
   ```sh
   cat >> /etc/hermes/.env <<'EOF'
   OPENAI_API_KEY=sk-...
   ANTHROPIC_API_KEY=...
   OPENROUTER_API_KEY=...
   EOF
   chmod 600 /etc/hermes/.env
   ```
   LuCI 白名单 key：`OPENAI_API_KEY`、`ANTHROPIC_API_KEY`、
   `OPENROUTER_API_KEY`、`NOUS_API_KEY`、`GEMINI_API_KEY`、`HF_TOKEN`
   （其他环境变量请直接编辑 .env，文件其余内容在 LuCI 保存时保留）

2. **模型/平台** —— `/etc/hermes/config.yaml`（安装时由
   `cli-config.yaml.example` 生成，LuCI 设置页可全文编辑，保存前自动备份
   `config.yaml.bak`）

3. 重启服务：`/etc/init.d/hermes-agent restart`

## 四、LuCI 界面

**Services → Hermes Agent**（依赖 `luci-base`，安装 luci-app 后自动出现；
ACL 名 `luci-app-hermes-agent`）：

| 页面 | 功能 |
| --- | --- |
| Status | 两个实例的运行状态、版本、磁盘用量；Start/Stop/Restart 按钮；面板链接 |
| Settings | uci 选项（enabled/profile/bind/port/insecure）；API Keys；config.yaml 全文编辑；Restart now |
| Logs | logread 过滤查看 hermes 日志（pattern + 行数） |

## 五、Web 面板（hermes serve）

- 默认 `http://127.0.0.1:9119/`（仅本机）
- 绑定局域网：`dashboard.bind=0.0.0.0` + `dashboard.insecure=1`
  （上游安全策略：公网绑定必须配置 auth provider——在 config.yaml / .env
  中配置，或仅限受信网络）
- 面板进程同样由 procd 守护，`dashboard.enabled=0` 即关闭

## 六、日志与排障

```sh
logread -e hermes          # gateway 日志（procd 捕获 stdout/stderr）
/etc/init.d/hermes-agent running && echo up
hermes --version
hermes doctor              # 若上游提供自检命令
```

常见问题：

| 现象 | 处理 |
| --- | --- |
| `hermes: not found` | 主包未装成功（`opkg install` 报依赖错误时检查整树安装） |
| 面板 404 / 连接拒绝 | dashboard 未启用或未绑定正确地址；`logread -e hermes` 看报错 |
| API key 报 401 | .env 权限/拼写；config.yaml 中 provider 配置 |
| 内存不足 OOM | Python 全栈占内存；关闭 dashboard 实例，或换大内存设备 |
| 升级后配置丢失 | conffile 机制保留 /etc/config 与 /etc/hermes；若手动删过则恢复 |

## 七、卸载

```sh
opkg remove luci-app-hermes-agent hermes-agent   # 或 apk del ...
rm -rf /etc/hermes                               # 数据目录（含 API keys）
```
