#!/bin/sh
#
# Runtime smoke test: install the built packages into a real OpenWrt rootfs and
# exercise them. Run from the repository root:
#
#     scripts/smoke/run.sh <sdk-dir> [work-dir]
#
# check-artifacts.sh proves the promised files are inside the packages. This
# proves they *work*: that the musllinux wheels load under OpenWrt's own musl,
# that rpcd registers the ucode plugin, and that the gateway and the bridge
# actually complete their websocket handshake. Those are the failures that a
# package inspection cannot see, and they are the expensive ones -- they only
# ever show up on the router.
#
# The rootfs image comes from the same release the SDK was built from (read out
# of the SDK's own CONFIG_VERSION_REPO), so the libc, Python minor version and
# apk/opkg generation all match what the packages were compiled against.
#
# Only x86_64 SDKs can be smoke tested here: the sandbox runs the target's real
# binaries on the build machine, and an aarch64 rootfs will not execute. The
# aarch64 legs are covered by the build matrix and check-artifacts.sh.
#
# Why bubblewrap and not `unshare -rm` + chroot: an unprivileged user namespace
# on this kernel cannot bind-mount /proc, /sys or /dev (EPERM for a fresh proc
# mount, EINVAL for the binds), even after `mount --make-rprivate /`. bwrap does
# exactly that setup for a living. It needs no root, and nothing outside the
# work directory is writable from inside.

set -eu

sdk=${1:?usage: scripts/smoke/run.sh <sdk-dir> [work-dir]}
work=${2:-${TMPDIR:-/tmp}/hermes-smoke}

here=$(cd "$(dirname "$0")" && pwd)

[ -f "$sdk/.config" ] || { echo "not an SDK (no .config): $sdk" >&2; exit 1; }
command -v bwrap >/dev/null 2>&1 || {
	echo "bwrap not found; install bubblewrap (Debian/Ubuntu: apt install bubblewrap)" >&2
	exit 1
}

cfg() { sed -n "s/^CONFIG_$1=\"\\(.*\\)\"\$/\\1/p" "$sdk/.config"; }

repo=$(cfg VERSION_REPO)
board=$(cfg TARGET_BOARD)
subtarget=$(cfg TARGET_SUBTARGET)
arch=$(cfg TARGET_ARCH_PACKAGES)

[ -n "$repo" ] && [ -n "$board" ] && [ -n "$subtarget" ] || {
	echo "could not read the target out of $sdk/.config" >&2
	exit 1
}

case "$arch" in
	x86_64) : ;;
	*)
		echo "smoke test needs an x86_64 SDK; this one is $arch." >&2
		echo "The target's real binaries run on this machine, so a foreign" >&2
		echo "architecture cannot be executed here." >&2
		exit 1
		;;
esac

base=$repo/targets/$board/$subtarget
rootfs=$work/rootfs
pkgs=$work/pkgs

echo "== target"
echo "  sdk:    $sdk"
echo "  target: $board/$subtarget ($arch)"
echo "  base:   $base"

# --- the packages under test -------------------------------------------------
#
# The glob deliberately allows both separators: .apk names files
# <name>-<ver>-r<rel>.apk, .ipk uses <name>_<ver>-r<rel>_<arch>.ipk. Hard-coding
# one of them is a mistake this repository has already made once.
rm -rf "$pkgs"
mkdir -p "$pkgs"

n=0
for f in $(find "$sdk/bin" -type f \
	\( -name 'hermes-agent[-_][0-9]*' -o -name 'luci-app-hermes-agent[-_][0-9]*' \) 2>/dev/null)
do
	cp "$f" "$pkgs/" && n=$((n + 1))
done

echo "== packages"
[ "$n" -ge 1 ] || {
	echo "  nothing built yet in $sdk/bin -- run the two compile targets first" >&2
	exit 1
}
( cd "$pkgs" && ls -1sh )

# --- the rootfs --------------------------------------------------------------
#
# Always unpacked fresh. A reused rootfs is the classic way a verification
# harness lies to you: a file an older build installed is still there, so a
# Makefile that stopped installing it still passes. The tarball itself is cached,
# so this costs seconds.
echo "== rootfs"
mkdir -p "$work"
name=$(cd "$work" && ls 2>/dev/null | grep -E '^openwrt-.*-rootfs\.tar\.gz$' | head -n1 || true)

if [ -z "$name" ]; then
	# Listed rather than guessed: the file is openwrt-<ver>-x86-64-rootfs.tar.gz,
	# with the target's dashes, not the SDK's underscores, and the naming has
	# changed between releases before.
	name=$(curl -fsSL "$base/" | grep -oE 'openwrt-[^"<]*-rootfs\.tar\.gz' | head -n1)
	[ -n "$name" ] || { echo "no rootfs tarball listed at $base/" >&2; exit 1; }
	echo "  fetching $name"
	curl -fsSL "$base/$name" -o "$work/$name"
fi

rm -rf "$rootfs"
mkdir -p "$rootfs"
echo "  unpacking $name"
# Device nodes and ownership cannot be restored unprivileged; bwrap supplies its
# own /dev, and everything runs as uid 0 inside, so those errors are expected.
tar -xzf "$work/$name" -C "$rootfs" 2>"$work/untar.log" || true
[ -x "$rootfs/bin/busybox" ] || { echo "unpack failed, see $work/untar.log" >&2; exit 1; }

# OpenWrt ships /etc/resolv.conf as a symlink to /tmp/resolv.conf, which netifd
# would write at boot. Nothing boots here, so the link is bound to the host's
# resolver -- apk needs to resolve downloads.openwrt.org for the dependency
# closure (python3, luci-base, rpcd-mod-ucode ...).
echo "== sandbox"
exec bwrap \
	--unshare-user --uid 0 --gid 0 \
	--unshare-pid --unshare-ipc --unshare-uts --hostname openwrt-smoke \
	--bind "$rootfs" / \
	--dev /dev --proc /proc \
	--ro-bind /etc/resolv.conf /tmp/resolv.conf \
	--ro-bind "$pkgs" /pkgs \
	--ro-bind "$here/inner.sh" /inner.sh \
	--ro-bind "$here/../ucode-globals.py" /ucode-globals.py \
	--chdir / \
	--setenv PATH /usr/sbin:/usr/bin:/sbin:/bin \
	/bin/sh /inner.sh
