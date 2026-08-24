# 安装与配置（INSTALL.md）

## 一、装什么

只有两个包：

| 包 | 必需？ | 依赖 |
| --- | --- | --- |
| `hermes-agent` | 是 | `python3`、`ca-bundle` |
| `luci-app-hermes-agent` | 想用网页界面就装 | `luci-base`、`rpcd-mod-ucode`、`hermes-agent` |

Python 依赖闭包在 `hermes-agent` 包内部（私有 site-packages），**没有**一堆
`python3-xxx` 包要装。两个包自己约 164 MB，加上 python3 等依赖闭包，实测在
OpenWrt 25.12.5 x86_64 上整机占用从 23 MB 涨到 226 MB——**准备 300 MB 以上的可写
空间**，小 flash 设备请先做 extroot 或挂 USB。

依赖里的 `python3`、`luci-base`、`rpcd-mod-ucode` 都来自官方源，所以路由器能上网
时先 `update` 一次，剩下的交给包管理器解析：

```sh
# 传上去
scp hermes-agent* luci-app-hermes-agent* root@192.168.1.1:/tmp/

# --- OpenWrt 24.10（opkg / .ipk）---
opkg update
opkg install /tmp/hermes-agent_*.ipk /tmp/luci-app-hermes-agent_*.ipk

# --- OpenWrt 25.12（apk / .apk）---
apk update
apk add --allow-untrusted /tmp/hermes-agent-*.apk /tmp/luci-app-hermes-agent-*.apk
```

`--allow-untrusted` 是因为本地文件没有仓库签名。如果路由器上不了网，就把这两个包
和 `python3`、`ca-bundle`、`luci-base`、`rpcd-mod-ucode` 一起离线带过去。

装完服务是**关着**的——Hermes 没有 API key 什么也做不了，装完就起只会得到一个
崩溃重启循环。

## 二、先配一个 provider

界面：**Services → Hermes Agent → Settings**，填对应的 key，保存。命令行等价：

```sh
cat >> /srv/hermes/.env <<'EOF'
OPENAI_API_KEY=sk-...
EOF
chmod 600 /srv/hermes/.env
```

LuCI 里列出的 key：`OPENAI_API_KEY`、`ANTHROPIC_API_KEY`、`OPENROUTER_API_KEY`、
`NOUS_API_KEY`、`DEEPSEEK_API_KEY`、`GEMINI_API_KEY`。别的环境变量直接写进 `.env`
即可，LuCI 保存时会保留它不认识的行。

界面里 key 是**只写**的：已配置的 key 只显示"已配置"，值不会回传浏览器，所以字段
永远是空的——留空表示不改，要删得勾"Remove this key"。

模型和 provider 本身在 `/srv/hermes/config.yaml`（Settings 页可全文编辑）。

## 三、开起来

```sh
uci set hermes-agent.serve.enabled=1
uci commit hermes-agent
/etc/init.d/hermes-agent restart
/etc/init.d/hermes-chatd restart      # 装了 LuCI 应用的话
```

或者直接在 Overview 页点 Start——两个服务一起管。

`/etc/config/hermes-agent` 只有服务级设置：

```
config service 'serve'
	option enabled  '0'
	option host     '127.0.0.1'
	option port     '9119'
	option log_level 'info'
	option workdir  '/srv/hermes/workspace'
```

`host` 只接受回环地址。填别的 init 脚本会直接拒绝启动并写一条 syslog——这是故意
的：网关在回环上是免鉴权的，放到 LAN 上等于把一个能执行 shell 的 agent 网关裸奔。
想从别的机器用，请走 LuCI（HTTPS + LuCI 会话），不要动这一项。

`workdir` 是 agent 做文件操作的目录，在意 flash 寿命就指到外置存储。

## 四、界面

**Services → Hermes Agent**：

| 页面 | 内容 |
| --- | --- |
| Overview | 服务/桥状态、版本、监听地址、数据目录、剩余空间、启停按钮，底部带日志尾巴 |
| Chat | 在 LuCI 里直接对话：流式输出、思考过程、工具调用、审批与追问 |
| Settings | UCI 选项、provider key、`config.yaml` 全文编辑 |

日志没有单独一页，在 Overview 底部。

## 五、排障

先看这两条，绝大多数问题在这里就现形：

```sh
logread -e hermes
/etc/init.d/hermes-agent status
```

| 现象 | 原因与处理 |
| --- | --- |
| 服务起不来，日志 `refusing to bind …` | `host` 不是回环地址，改回 `127.0.0.1` |
| 日志 `config.yaml is missing` | `/srv/hermes/config.yaml` 被删了，重装 `hermes-agent` 会补默认模板 |
| Chat 页显示未连接 | 桥没起：`/etc/init.d/hermes-chatd restart`；桥也跟随 `serve.enabled`，网关关着它不会起 |
| Chat 页一直转圈，网关日志有 `invalid token` | `/var/run/hermes-agent.token` 与桥持有的不一致（手删过 token 文件）；`/etc/init.d/hermes-chatd restart` |
| 菜单里没有 Hermes | LuCI 缓存：`rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache/` |
| 页面空白 / 按钮无反应 | rpcd 没加载 ubus 插件：`/etc/init.d/rpcd restart`，然后 `ubus list luci.hermes-agent` 应有输出 |
| 401 / provider 报错 | `.env` 里 key 拼写或权限（必须 0600 且属 root） |
| OOM | 依赖闭包常驻内存不小，256 MB 的设备会很紧张 |

手工验证链路（从内到外，哪一层断了很清楚）：

```sh
hermes --version                                   # 包装好了
curl -s 127.0.0.1:9119 >/dev/null && echo gateway  # 网关活着
ls -l /var/run/hermes-chat/                        # 桥的 IPC 目录（0700）
ubus call luci.hermes-agent status                 # rpcd 插件通
```

## 六、升级与卸载

sysupgrade 只保留 `/srv/hermes/config.yaml` 和 `/srv/hermes/.env`（见
`/lib/upgrade/keep.d/hermes-agent`）。会话数据库刻意不保留，它能长到几百 MB，
没道理进固件备份——需要的话自己备份 `/srv/hermes`。

```sh
opkg remove luci-app-hermes-agent hermes-agent    # 24.10
apk del luci-app-hermes-agent hermes-agent        # 25.12

rm -rf /srv/hermes                                 # 数据与 API key，卸载不会删
```
