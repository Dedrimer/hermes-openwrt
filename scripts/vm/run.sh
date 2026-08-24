#!/bin/sh
#
# Boot a real OpenWrt in QEMU, install the built packages into it, and exercise
# the LuCI app through HTTP the way a browser does. Run from the repository root:
#
#     scripts/vm/run.sh <sdk-dir> [work-dir]
#
# scripts/smoke/run.sh already runs the target's binaries -- but in a bwrap
# sandbox, with no kernel of its own, no procd, no uhttpd and no rpcd ACL. Those
# absences are exactly where this layer earns its keep: the .env corruption bug
# in docs/PORTING.md §7 (4) passed all four earlier layers and was caught within
# minutes of a real login here, because no earlier layer had ever called
# settings_set. What this adds over the sandbox:
#
#   * a real boot: procd, the init scripts' own enable/start path, logd
#   * apk resolving the dependency closure against the real feeds, then the
#     upgrade path when the same package is reinstalled at a higher PKG_RELEASE
#   * uhttpd, the LuCI session cookie and the rpcd ACL -- see luci-check.sh
#
# Everything runs unprivileged. There is no root anywhere in this script:
#
#   * KVM needs group access to /dev/kvm, nothing more; without it QEMU falls
#     back to TCG and the boot merely gets slower.
#   * the rootfs is edited with debugfs, not by mounting it. `mount` needs root
#     (and a loop device); debugfs writes ext4 from userspace and can set the
#     uid/gid/mode of what it writes, which is the whole reason a root-owned
#     0600 /etc/shadow can be injected from an ordinary account.
#   * QEMU's user-mode network needs no tap device and no bridge.
#
# Environment:
#   QEMU=...             qemu-system-x86_64 to use (default: from PATH). A QEMU
#                        unpacked into a private prefix rather than installed --
#                        which is how the build machine has one, since this needs
#                        no root -- also wants LD_LIBRARY_PATH pointing at that
#                        prefix's lib directory; both are inherited from here.
#   VM_PASSWORD=...      root password inside the VM (default: hermes-vm)
#   VM_SSH_PORT=2222     host port forwarded to the guest's sshd
#   VM_HTTP_PORT=8080    host port forwarded to the guest's uhttpd
#   VM_HTTP_BIND=127.0.0.1
#                        who may reach LuCI. Loopback by default: the guest has
#                        a known root password and a permissive throwaway
#                        config, so set this to 0.0.0.0 only on a network you
#                        would hand that password to.
#   VM_DISK=2G           grown rootfs size (the install needs ~200 MiB free)
#   VM_MEM=2048  VM_CPUS=4
#   VM_KEEP=1            leave the VM running at the end (0 powers it off)
#
# Exit status is luci-check.sh's, i.e. the number of failed checks.

set -eu

sdk=${1:?usage: scripts/vm/run.sh <sdk-dir> [work-dir]}
work=${2:-${TMPDIR:-/tmp}/hermes-vm}

here=$(cd "$(dirname "$0")" && pwd)

qemu=${QEMU:-qemu-system-x86_64}
password=${VM_PASSWORD:-hermes-vm}
ssh_port=${VM_SSH_PORT:-2222}
http_port=${VM_HTTP_PORT:-8080}
http_bind=${VM_HTTP_BIND:-127.0.0.1}
disk=${VM_DISK:-2G}
mem=${VM_MEM:-2048}
cpus=${VM_CPUS:-4}
keep=${VM_KEEP:-1}

[ -f "$sdk/.config" ] || { echo "not an SDK (no .config): $sdk" >&2; exit 1; }

for t in "$qemu" curl truncate e2fsck resize2fs debugfs ssh ssh-keygen openssl gzip; do
	command -v "$t" >/dev/null 2>&1 || {
		echo "$t not found." >&2
		case $t in
			qemu*) echo "  QEMU=/path/to/qemu-system-x86_64 scripts/vm/run.sh ..." >&2 ;;
			e2fsck|resize2fs|debugfs) echo "  install e2fsprogs" >&2 ;;
		esac
		exit 1
	}
done

cfg() { sed -n "s/^CONFIG_$1=\"\\(.*\\)\"\$/\\1/p" "$sdk/.config"; }

repo=$(cfg VERSION_REPO)
board=$(cfg TARGET_BOARD)
subtarget=$(cfg TARGET_SUBTARGET)
arch=$(cfg TARGET_ARCH_PACKAGES)

[ -n "$repo" ] && [ -n "$board" ] && [ -n "$subtarget" ] || {
	echo "could not read the target out of $sdk/.config" >&2
	exit 1
}

# Same restriction as the smoke test, for a different reason: this boots the
# target's own kernel on the host CPU. An aarch64 image would need full-system
# emulation and a different set of image names.
case "$arch" in
	x86_64) : ;;
	*)
		echo "scripts/vm needs an x86_64 SDK; this one is $arch." >&2
		exit 1
		;;
esac

base=$repo/targets/$board/$subtarget
img=$work/rootfs.raw
key=$work/vm_key
pidfile=$work/qemu.pid
serial=$work/serial.log

echo "== target"
echo "  sdk:    $sdk"
echo "  target: $board/$subtarget ($arch)"
echo "  base:   $base"
echo "  work:   $work"

mkdir -p "$work"

# Refuse to trample a VM that is already up: its disk is this same file, and
# writing to it from a second QEMU corrupts both.
if [ -s "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
	echo "a VM from this work dir is already running (pid $(cat "$pidfile"))." >&2
	echo "  kill \$(cat $pidfile)   # to stop it" >&2
	exit 1
fi
rm -f "$pidfile" "$work/monitor.sock"

# --- the packages under test -------------------------------------------------
#
# Both separators, for the same reason as scripts/smoke/run.sh: .apk names files
# <name>-<ver>-r<rel>.apk while .ipk uses <name>_<ver>-r<rel>_<arch>.ipk.
pkgs=$work/apks
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

# --- kernel + rootfs ---------------------------------------------------------
#
# kernel.bin plus ext4-rootfs.img, not combined-ext4.img: the combined image is a
# whole disk with a partition table and syslinux, and booting it means either
# growing a partition (needs sfdisk surgery) or living with the stock 104 MiB
# rootfs, which cannot hold a 200 MiB install. Passing the kernel directly on the
# QEMU command line skips the bootloader entirely and lets the rootfs image be
# the whole disk, so `resize2fs` alone is enough to grow it.
echo "== images"
fetch() { # $1 filename pattern -> echoes the cached path
	name=$(cd "$work" && ls 2>/dev/null | grep -E "$1" | head -n1 || true)

	if [ -z "$name" ]; then
		# Listed rather than guessed: these names carry the release version and
		# have changed spelling between releases before.
		name=$(curl -fsSL "$base/" | grep -oE "openwrt-[^\"<]*${2}" | head -n1)
		[ -n "$name" ] || { echo "nothing matching $2 listed at $base/" >&2; exit 1; }
		echo "  fetching $name" >&2
		curl -fsSL "$base/$name" -o "$work/$name.part"
		mv "$work/$name.part" "$work/$name"
	fi

	echo "$work/$name"
}

kernel=$(fetch '^openwrt-.*-generic-kernel\.bin$' '-generic-kernel\.bin')
rootgz=$(fetch '^openwrt-.*-generic-ext4-rootfs\.img\.gz$' '-generic-ext4-rootfs\.img\.gz')
echo "  kernel: ${kernel##*/}"
echo "  rootfs: ${rootgz##*/}"

# Always decompressed fresh, for the reason spelled out in scripts/smoke/run.sh:
# a reused rootfs still holds what an older build installed, so a Makefile that
# stopped installing a file keeps passing. The download is cached; this is a
# second or two.
echo "== rootfs"
rm -f "$img"
gzip -dc "$rootgz" > "$img"
truncate -s "$disk" "$img"
# resize2fs refuses to touch a filesystem that has not been checked since its
# last mount, and the shipped image has not been.
e2fsck -f -y "$img" > "$work/fsck.log" 2>&1 || true
resize2fs "$img" >> "$work/fsck.log" 2>&1
echo "  grown to $disk"

# --- injected files ----------------------------------------------------------
#
# Three things have to be true before the first boot: root has a password (LuCI
# will not accept a login for a passwordless account), our key is authorised for
# ssh, and the LAN interface asks for DHCP instead of claiming 192.168.1.1 --
# QEMU's user-mode network hands out 10.0.2.15 and routes nothing else.
[ -f "$key" ] || ssh-keygen -q -t ed25519 -N '' -C hermes-vm -f "$key"

hash=$(openssl passwd -6 "$password")

# The shipped /etc/shadow is pulled out of the image and edited rather than
# written from scratch: it carries every system account, and replacing the file
# with a single root line breaks anything that looks up daemon users.
debugfs -R 'cat /etc/shadow' "$img" 2>/dev/null > "$work/shadow.orig"
[ -s "$work/shadow.orig" ] || { echo "could not read /etc/shadow out of the image" >&2; exit 1; }
awk -v h="$hash" -F: 'BEGIN{OFS=":"} $1=="root"{$2=h} {print}' \
	"$work/shadow.orig" > "$work/shadow.new"

cat > "$work/rc.local" <<'EOF'
#!/bin/sh
# Test VM only, injected by scripts/vm/run.sh. QEMU's user-mode network hands out
# 10.0.2.15 by DHCP and aims its host forwards at that address, so the stock
# static 192.168.1.1 on br-lan would make the guest unreachable. Idempotent, so
# it survives reboots.
if [ "$(uci -q get network.lan.proto)" != dhcp ]; then
	uci -q set network.lan.proto=dhcp
	uci -q delete network.lan.ipaddr
	uci -q delete network.lan.netmask
	uci -q delete network.lan.ip6assign
	uci commit network
	/etc/init.d/network restart
fi
exit 0
EOF

# debugfs -R takes exactly one command, so a batch this size goes through -f.
#
# Two details that are easy to get wrong and fail quietly:
#   * `sif <file> mode` writes the whole i_mode field, type bits included. 0600
#     would leave a file of type 0, which fsck then "repairs"; regular files need
#     0100600, directories 040755.
#   * `write` gives the file the invoking uid, hence the sif uid/gid lines --
#     dropbear ignores an authorized_keys it does not trust the owner of.
#
# The key goes to /etc/dropbear/authorized_keys, which is where OpenWrt's dropbear
# looks for root's keys; /root/.ssh is not consulted and does not exist here.
cat > "$work/edits.debugfs" <<EOF
cd /etc
rm shadow
write $work/shadow.new shadow
sif shadow mode 0100600
sif shadow uid 0
sif shadow gid 0
rm rc.local
write $work/rc.local rc.local
sif rc.local mode 0100755
sif rc.local uid 0
sif rc.local gid 0
cd /etc/dropbear
write $key.pub authorized_keys
sif authorized_keys mode 0100600
sif authorized_keys uid 0
sif authorized_keys gid 0
quit
EOF

debugfs -w -f "$work/edits.debugfs" "$img" > "$work/debugfs.log" 2>&1
# debugfs reports most failures on stdout and still exits 0, so the log is
# grepped instead of the status being trusted.
grep -iE 'file not found|error|invalid' "$work/debugfs.log" \
	| grep -viE 'rm |File not found by ext2_lookup' >/dev/null 2>&1 && {
	echo "debugfs edits failed, see $work/debugfs.log" >&2
	exit 1
}
e2fsck -f -y "$img" >> "$work/fsck.log" 2>&1 || true
echo "  injected: root password, ${key##*/}.pub in /etc/dropbear, rc.local (dhcp)"

# --- boot --------------------------------------------------------------------
#
# virtio for both disk and net: this kernel has virtio_blk, virtio_net and
# virtio_pci built in, while e1000 is a module the initramfs-less boot cannot
# load. Getting that wrong looks like a kernel panic on "no root device".
echo "== boot"
"$qemu" \
	-name hermes-openwrt-test \
	-machine q35,accel=kvm:tcg \
	-cpu host -smp "$cpus" -m "$mem" \
	-kernel "$kernel" \
	-append "console=ttyS0,115200n8 root=/dev/vda rootwait" \
	-drive "file=$img,if=none,id=d0,format=raw,cache=writeback" \
	-device virtio-blk-pci,drive=d0 \
	-netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$ssh_port-:22,hostfwd=tcp:$http_bind:$http_port-:80" \
	-device virtio-net-pci,netdev=n0 \
	-display none \
	-serial "file:$serial" \
	-monitor "unix:$work/monitor.sock,server,nowait" \
	-pidfile "$pidfile" \
	-daemonize

echo "  qemu pid $(cat "$pidfile"), serial log $serial"

sh_ssh() { # run a command in the guest; -n so stdin stays ours (see below)
	ssh -n -i "$key" -p "$ssh_port" \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR -o ConnectTimeout=5 \
		root@127.0.0.1 "$@"
}

# -n on every guest command is not decoration. Without it the inner ssh inherits
# this script's stdin and swallows the rest of it when run under `bash -s` or a
# heredoc, so the script silently stops early and reports success.
i=0
until sh_ssh true 2>/dev/null; do
	i=$((i + 1))
	[ "$i" -lt 60 ] || {
		echo "  the guest never came up; tail of $serial:" >&2
		tail -25 "$serial" >&2
		exit 1
	}
	sleep 2
done
echo "  ssh up after $((i * 2))s: $(sh_ssh '. /etc/openwrt_release; echo $DISTRIB_ID $DISTRIB_RELEASE $DISTRIB_ARCH')"

# --- install -----------------------------------------------------------------
#
# Piped in over ssh rather than scp'd: the guest has no /usr/libexec/sftp-server,
# so scp and sftp both fail with a confusing "subsystem request failed".
echo "== install"
sh_ssh 'rm -rf /tmp/pkgs && mkdir -p /tmp/pkgs'
for f in "$pkgs"/*; do
	ssh -i "$key" -p "$ssh_port" \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		root@127.0.0.1 "cat > /tmp/pkgs/${f##*/}" < "$f"
	echo "  uploaded ${f##*/}"
done

# The rest of the closure (python3, luci-base, rpcd-mod-ucode, ...) comes from
# the real feeds for this release -- which is the point: it proves the DEPENDS
# lines resolve against what a user actually has.
sh_ssh 'apk update' >"$work/apk.log" 2>&1 || true
if sh_ssh 'apk add --allow-untrusted /tmp/pkgs/*.apk' >>"$work/apk.log" 2>&1; then
	echo "  apk add ok, $(grep -cE '^\([0-9]+/[0-9]+\) Installing' "$work/apk.log") packages installed"
else
	echo "  apk add FAILED, see $work/apk.log" >&2
	tail -20 "$work/apk.log" >&2
	exit 1
fi
echo "  installed size: $(sh_ssh 'du -sh /usr/lib/hermes-agent /usr/share/hermes-agent 2>/dev/null | tr "\n" " "')"

# --- start -------------------------------------------------------------------
#
# serve.enabled defaults to 0 -- a fresh install must not open a gateway nobody
# asked for -- so the init script exits 0 after logging "serve disabled". That is
# correct behaviour and looks exactly like a failed start; flip the flag first.
echo "== start"
sh_ssh 'uci -q set hermes-agent.serve.enabled=1 && uci -q commit hermes-agent'

# A syntactically plausible key so provider validation does not abort startup.
# Nothing here submits a prompt, so it never reaches an API.
sh_ssh 'grep -q "^OPENAI_API_KEY=" /srv/hermes/.env 2>/dev/null ||
	{ printf "OPENAI_API_KEY=sk-vm-0000000000000000000000000000000000000000\n" >> /srv/hermes/.env;
	  chmod 600 /srv/hermes/.env; }'

sh_ssh '/etc/init.d/hermes-agent enable; /etc/init.d/hermes-agent restart' >/dev/null 2>&1 || true
sh_ssh '/etc/init.d/hermes-chatd enable; /etc/init.d/hermes-chatd restart' >/dev/null 2>&1 || true

port=$(sh_ssh 'uci -q get hermes-agent.serve.port' 2>/dev/null || true)
[ -n "$port" ] || port=9119
i=0
until sh_ssh "netstat -ltn 2>/dev/null | grep -q '127.0.0.1:$port'"; do
	i=$((i + 1))
	[ "$i" -lt 90 ] || {
		echo "  the gateway never listened on 127.0.0.1:$port" >&2
		sh_ssh "logread -e hermes | tail -25" >&2 || true
		exit 1
	}
	sleep 2
done
echo "  gateway listening on 127.0.0.1:$port after $((i * 2))s"

i=0
until sh_ssh 'grep -q "\"connected\": *true" /var/run/hermes-chat/state 2>/dev/null'; do
	i=$((i + 1))
	[ "$i" -lt 30 ] || {
		echo "  the bridge never connected; state: $(sh_ssh 'cat /var/run/hermes-chat/state 2>&1' || true)" >&2
		sh_ssh "logread -e chatd | tail -15" >&2 || true
		exit 1
	}
	sleep 2
done
echo "  bridge connected after $((i * 2))s"

# --- the actual test ---------------------------------------------------------
echo
echo "== luci-check ($http_bind:$http_port)"
rc=0
VM_PASSWORD="$password" sh "$here/luci-check.sh" "http://127.0.0.1:$http_port" "$password" || rc=$?

echo
if [ "$keep" = 0 ]; then
	echo "== shutdown"
	sh_ssh 'poweroff' >/dev/null 2>&1 || true
	sleep 5
	kill "$(cat "$pidfile")" 2>/dev/null || true
else
	echo "The VM is still running:"
	echo "  LuCI   http://$http_bind:$http_port/   root / $password"
	echo "  ssh    ssh -i $key -p $ssh_port root@127.0.0.1"
	echo "  serial $serial"
	echo "  stop   kill \$(cat $pidfile)"
fi

exit "$rc"
