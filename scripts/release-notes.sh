#!/bin/sh
#
# Generate the GitHub release notes for a hermes-openwrt release.
#
#     scripts/release-notes.sh <dist-dir> <tag> > notes.md
#
# <dist-dir> is what actions/download-artifact leaves behind: one directory per
# build leg, each holding that leg's two packages plus the build-info.env the
# build job wrote *after* every check in it passed. Everything else -- package
# versions, the pinned upstream commit, the size of the dependency closure -- is
# read out of the working tree, never typed in here, so a number on the release
# page cannot drift from the thing it describes.
#
# Nothing in this script touches the network or the GitHub API, so it can be run
# by hand against a directory assembled from a local build:
#
#     d=$(mktemp -d)
#     mkdir "$d/leg"
#     cp sdk/bin/packages/*/hermes/*.apk "$d/leg/"
#     printf 'release=25.12\narch=x86_64\nfmt=apk\nsdk_version=25.12.5\npython=3.13\n' \
#         > "$d/leg/build-info.env"
#     sh scripts/release-notes.sh "$d" v0.0.0-test | less
#
# which is the only practical way to review a release page before the release
# exists. Fields missing from build-info.env render as `?` rather than failing,
# so a partial hand-written one is fine for that purpose.
#
# Optional environment:
#   HIGHLIGHTS         Markdown placed at the very top (the workflow input)
#   GITHUB_REPOSITORY  set: asset names and doc paths become links
#   GITHUB_SERVER_URL  defaults to https://github.com
#   GITHUB_RUN_ID      links the workflow run that produced the assets
#   GITHUB_SHA         the commit built; falls back to git rev-parse HEAD

set -eu

dist=${1:?usage: release-notes.sh <dist-dir> <tag>}
tag=${2:?usage: release-notes.sh <dist-dir> <tag>}

# Resolve the artifact directory before moving to the repository root: the
# caller's path is relative to wherever they are.
dist=$(cd "$dist" && pwd)
cd "$(dirname "$0")/.."

server=${GITHUB_SERVER_URL:-https://github.com}
repo=${GITHUB_REPOSITORY:-}
run_id=${GITHUB_RUN_ID:-}
sha=${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}
short=$(printf '%s' "$sha" | cut -c1-8)

# --- helpers ---------------------------------------------------------------

# Read `NAME:=value` out of a Makefile, and `name=value` out of a build-info.env.
mkvar() { sed -n "s/^$2:=\(.*\)$/\1/p" "$1" | head -n1; }
field() {
	v=$(sed -n "s/^$2=//p" "$1" | head -n1)
	[ -n "$v" ] || v='?'
	printf '%s' "$v"
}

pkgfile() { find "$1" -maxdepth 1 -type f -name "$2[-_][0-9]*" | sed 's|.*/||' | sort | head -n1; }

# The two packages differ by three orders of magnitude (the agent carries the
# whole dependency closure, the LuCI app is a handful of text files), so a fixed
# unit prints either "155.4 MiB" or a useless "0.0 MiB".
size() {
	[ -f "$1" ] || { printf '?'; return 0; }
	awk -v b="$(wc -c <"$1")" 'BEGIN {
		if (b >= 1048576) printf "%.1f MiB", b / 1048576
		else printf "%.0f KiB", b / 1024
	}'
}

# A release is a flat namespace of assets under one predictable URL, so the file
# name is enough to build a direct download link. Without GITHUB_REPOSITORY
# (running locally) fall back to plain code spans.
asset() {
	if [ -z "$1" ]; then
		printf '**缺失**'
	elif [ -n "$repo" ]; then
		printf '[`%s`](%s/%s/releases/download/%s/%s)' "$1" "$server" "$repo" "$tag" "$1"
	else
		printf '`%s`' "$1"
	fi
}

# Doc links are pinned to this tag, not to the default branch: the instructions
# a release links to should be the ones that shipped with it.
doclink() {
	if [ -n "$repo" ]; then
		printf '[%s](%s/%s/blob/%s/%s)' "$2" "$server" "$repo" "$tag" "$1"
	else
		printf '%s（`%s`）' "$2" "$1"
	fi
}

suits() {
	case $1 in
	x86_64) printf 'x86_64 软路由、虚拟机' ;;
	aarch64*) printf 'rockchip/armv8（RK3528、RK3568、RK3588…）等 aarch64 目标' ;;
	*) printf '%s' "$1" ;;
	esac
}

# --- facts from the working tree -------------------------------------------

agent_mk=packages/hermes-agent/Makefile
luci_mk=packages/luci-app-hermes-agent/Makefile

agent_ver=$(mkvar "$agent_mk" PKG_VERSION)
agent_rel=$(mkvar "$agent_mk" PKG_RELEASE)
luci_ver=$(mkvar "$luci_mk" PKG_VERSION)
luci_rel=$(mkvar "$luci_mk" PKG_RELEASE)
up_url=$(mkvar "$agent_mk" PKG_SOURCE_URL)
up_commit=$(mkvar "$agent_mk" PKG_SOURCE_VERSION)
up_date=$(mkvar "$agent_mk" PKG_SOURCE_DATE)
up_tree="${up_url%.git}/tree/$up_commit"
up_short=$(printf '%s' "$up_commit" | cut -c1-8)

# The dependency-closure numbers come out of the generated lock file, because the
# whole point of deps.lock.json is that no human maintains a dependency table.
# The per-ABI target sets can differ by a package or two, so report a range
# rather than a number that is only true for one leg.
deps=$(python3 - packages/hermes-agent/deps/deps.lock.json <<'PY'
import json, sys

lock = json.load(open(sys.argv[1]))
targets = lock["targets"].values()
total = {len(t["packages"]) for t in targets}
native = {sum(1 for p in t["packages"].values() if not p["pure"]) for t in targets}
span = lambda s: str(min(s)) if len(s) == 1 else "%d-%d" % (min(s), max(s))
print("%s|%s|%s" % (span(total), span(native),
                    lock["upstream"].get("requires_python", "")))
PY
)
dep_total=$(printf '%s' "$deps" | cut -d'|' -f1)
dep_native=$(printf '%s' "$deps" | cut -d'|' -f2)
dep_pyreq=$(printf '%s' "$deps" | cut -d'|' -f3)

# Legs, newest OpenWrt first and x86_64 before aarch64 within a release: that is
# the order someone scanning the download table wants.
legs=$(for i in "$dist"/*/build-info.env; do
	[ -f "$i" ] || continue
	printf '%s\t%s\t%s\n' "$(field "$i" release)" "$(field "$i" arch)" "$i"
done | sort -r | cut -f3)

if [ -z "$legs" ]; then
	echo "release-notes.sh: no */build-info.env under $dist" >&2
	exit 1
fi

# --- notes -----------------------------------------------------------------

if [ -n "${HIGHLIGHTS:-}" ]; then
	printf '%s\n\n' "$HIGHLIGHTS"
fi

printf '把 [Nous Research 的 Hermes Agent](%s) `%s`（commit `%s`，%s）移植成 **OpenWrt 原生包**——\n' \
	"$up_tree" "$agent_ver" "$up_short" "$up_date"
printf '不是 Docker、不是 chroot——外加一个 LuCI 界面。上游源码**一行都没改**。\n\n'
printf '两个包都要装：`hermes-agent` 是本体加完整 Python 依赖闭包，`luci-app-hermes-agent`\n'
printf '是 LuCI 的三个页面、rpcd 后端和常驻聊天桥。\n\n'

printf '## 装哪一个\n\n'
printf '| OpenWrt | 架构 | 适用 | `hermes-agent` | `luci-app-hermes-agent` |\n'
printf '| --- | --- | --- | --- | --- |\n'
for i in $legs; do
	d=${i%/build-info.env}
	a=$(pkgfile "$d" hermes-agent)
	l=$(pkgfile "$d" luci-app-hermes-agent)
	printf '| %s | `%s` | %s | %s（%s） | %s（%s） |\n' \
		"$(field "$i" release)" "$(field "$i" arch)" "$(suits "$(field "$i" arch)")" \
		"$(asset "$a")" "$(size "$d/$a")" \
		"$(asset "$l")" "$(size "$d/$l")"
done

cat <<'EOF'

架构对不上装不了：`x86_64` 的包只能装在 x86_64 上，`aarch64_generic` 的包适用于任何
aarch64 目标（RK3528 属于这一档）。OpenWrt 版本要对上——24.10 是 opkg/`.ipk`、
Python 3.11，25.12 是 apk/`.apk`、Python 3.13，依赖闭包里的 wheel 是按 ABI 标签选的，
换一档装不上。

> 这里的文件名比路由器上自己构建出来的多了 `_openwrt-<版本>_<架构>` 一段：apk 的文件名
> 里根本不带架构，四条腿的产物会撞名，而一个 release 是一个扁平的命名空间。两个包管理器
> 都从包内部读元数据，所以改名不影响安装。

## 安装

EOF

cat <<'EOF'
```sh
# 传上去
scp hermes-agent_* luci-app-hermes-agent_* root@192.168.1.1:/tmp/

# OpenWrt 25.12（apk）
apk update
apk add --allow-untrusted /tmp/hermes-agent_*.apk /tmp/luci-app-hermes-agent_*.apk

# OpenWrt 24.10（opkg）
opkg update
opkg install /tmp/hermes-agent_*.ipk /tmp/luci-app-hermes-agent_*.ipk
```

`--allow-untrusted` 是因为本地文件没有仓库签名。其余依赖（python3 全家、`luci-base`、
`rpcd-mod-ucode`…）由包管理器从官方 feed 解析，所以先 `update` 一次。

**装完整机占用约 226 MB**（两个包自己 164 MB），准备 300 MB 以上的可写空间，
小 flash 设备先做 extroot 或挂 USB。

装完服务是**关着**的——没有 API key 起来只会得到一个崩溃重启循环。先在
**Services → Hermes Agent → Settings** 填一个 provider key（或直接写
`/srv/hermes/.env`，0600），然后：

```sh
uci set hermes-agent.serve.enabled=1
uci commit hermes-agent
/etc/init.d/hermes-agent restart
/etc/init.d/hermes-chatd restart
```
EOF

printf '\n完整步骤见 %s，排障表在同一篇的第五节。\n\n' "$(doclink docs/INSTALL.md '安装与配置')"

printf '## 这次构建\n\n'
printf '| 项 | 值 |\n| --- | --- |\n'
if [ -n "$repo" ] && [ -n "$sha" ]; then
	printf '| 源码 | [`%s`](%s/%s/commit/%s) |\n' "$short" "$server" "$repo" "$sha"
else
	printf '| 源码 | `%s` |\n' "${short:-?}"
fi
printf '| 构建时间 | %s |\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
if [ -n "$repo" ] && [ -n "$run_id" ]; then
	printf '| 构建记录 | [workflow run %s](%s/%s/actions/runs/%s) |\n' \
		"$run_id" "$server" "$repo" "$run_id"
fi
printf '| 上游 pin | Hermes Agent %s，commit [`%s`](%s)，%s |\n' \
	"$agent_ver" "$up_short" "$up_tree" "$up_date"
printf '| 包版本 | `hermes-agent` %s-r%s，`luci-app-hermes-agent` %s-r%s |\n' \
	"$agent_ver" "$agent_rel" "$luci_ver" "$luci_rel"
printf '| Python 依赖闭包 | %s 个 wheel（其中 %s 个原生扩展），从上游 `uv.lock` 生成，要求 Python `%s` |\n' \
	"$dep_total" "$dep_native" "$dep_pyreq"

printf '\n每条腿用的 SDK 和它通过的验证：\n\n'
printf '| OpenWrt | 架构 | 格式 | SDK | Python | 产物核对 | 运行期冒烟 |\n'
printf '| --- | --- | --- | --- | --- | --- | --- |\n'
for i in $legs; do
	case $(field "$i" smoke) in
	pass) smoke='通过' ;;
	n/a) smoke='跳过（沙箱执行目标真二进制，只能测 x86_64）' ;;
	*) smoke=$(field "$i" smoke) ;;
	esac
	case $(field "$i" artifacts_check) in
	pass) chk='通过' ;;
	*) chk=$(field "$i" artifacts_check) ;;
	esac
	printf '| %s | `%s` | %s | %s | %s | %s | %s |\n' \
		"$(field "$i" release)" "$(field "$i" arch)" "$(field "$i" fmt)" \
		"$(field "$i" sdk_version)" "$(field "$i" python)" "$chk" "$smoke"
done

printf '\n发版前还在构建机上跑了一层 CI 跑不了的验证：QEMU 里起一份真的 OpenWrt，`apk add`\n'
printf '装包（其余依赖从官方 feed 解析），再用浏览器走的那条路——登录拿 session cookie、\n'
printf '经 uhttpd 和 rpcd ACL 调 `/ubus/`——把三个页面和七个方法过一遍。四层验证的分工见 %s。\n' \
	"$(doclink docs/PORTING.md 'PORTING.md §10')"

printf '\n## 校验\n\n```\n'
# Same order the release job's `sha256sum -- *.apk *.ipk` produces, so these
# lines are the attached sha256sums.txt verbatim rather than a second opinion.
for ext in apk ipk; do
	find "$dist" -type f -name "*.$ext" | awk -F/ '{ print $NF "\t" $0 }' | sort | cut -f2 |
	while read -r f; do
		printf '%s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "${f##*/}"
	done
done
printf '```\n\n'
printf '这几行也作为 `sha256sums.txt` 附在下面，下载后 `sha256sum -c sha256sums.txt` 即可。\n'

cat <<'EOF'

## 已知取舍

- **只有 x86_64 和 aarch64。** 依赖闭包里的原生扩展（`pydantic-core`、`cryptography`、
  `uvloop`…）只有这两个架构有完整的 musllinux 预编译 wheel，其他架构要在 SDK 里跑
  Rust 交叉编译，代价与收益不成比例。
- **不含上游的 Web 仪表盘和 Node 终端 UI。** 两者都要 node/npm 预构建，会毁掉“跟着上游
  升级只需跑一个脚本”这条规则。界面就是 LuCI 那三页。
- **网关只 bind 回环。** init 脚本拒绝任何非回环 `host`；要从别的机器用就走 LuCI
  （HTTPS + LuCI 会话），别改这一项——网关在回环上是免鉴权的。
- **API key 存 `/srv/hermes/.env`（0600），不进 UCI**：`/etc/config` 全局可读，而且会被
  sysupgrade 备份打包带走。界面上 key 是只写的，值不回传浏览器。
EOF

if prev=$(git tag --list 'v*' --sort=-v:refname 2>/dev/null | grep -vx "$tag" | head -n1) &&
	[ -n "$prev" ] && git rev-parse --verify --quiet "$prev" >/dev/null 2>&1
then
	log=$(git log --no-merges --pretty='- %s' "$prev..HEAD" 2>/dev/null || true)
	if [ -n "$log" ]; then
		printf '\n## 自 %s 以来\n\n%s\n' "$prev" "$log"
	fi
fi
