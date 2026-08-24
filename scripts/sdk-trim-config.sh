#!/bin/sh
#
# Reduce an OpenWrt SDK's baked-in package selection to just this feed's
# dependency closure.
#
#     scripts/sdk-trim-config.sh <sdk-dir>                 # trim + make defconfig
#     scripts/sdk-trim-config.sh <sdk-dir> --no-defconfig  # trim only
#     scripts/sdk-trim-config.sh <sdk-dir> --restore       # undo
#
# An SDK arrives with every package of every feed selected: ~1100 kernel
# modules, all of linux-firmware, and on rockchip 34 u-boot variants. That is
# not cosmetic. `make package/<pkg>/compile` builds the kmod universe as
# collateral (the better part of an hour per target), and `make` runs the
# `prereq` phase for *every* selected package before it does anything, so
# uboot-rockchip's prereq (host swig + python3-pyelftools) can fail the whole
# build for a bootloader nobody asked for.
#
# Two mechanisms keep those packages selected, and missing either one makes the
# trim look like it silently does nothing:
#
#   1. Config-build.in -- the SDK's frozen build config -- declares each package
#      symbol *without a prompt*:
#
#          config PACKAGE_kmod-aoe
#          	tristate
#          	default m
#
#      kconfig ignores user values for invisible symbols, so `=n` in .config, or
#      `# ... is not set`, or deleting the line, is reverted by the next
#      `make defconfig`. Same for the ALL / ALL_KMODS / ALL_NONSHARED switches,
#      which are promptless here too. These have to be changed in the file.
#
#   2. Feed packages are *also* declared in tmp/.config-package.in, and there
#      they do have a prompt. A visible symbol keeps its value from .config --
#      and the .config an SDK ships already says =m for all of them. So even
#      after step 1, dropping those lines from .config is required.
#
# Doing only step 1 leaves a *partial* kmod selection, which is worse than
# leaving everything on: Config-build.in carries no `select` lines at all (0 of
# them, against 777 in tmp/.config-package.in), so kconfig has no way to compute
# the kmod dependency closure. comgt-ncm selects kmod-usb-serial-option, nothing
# then selects kmod-usb-serial-wwan, and package/kernel/linux fails its .ko
# closure check:
#
#     Package kmod-usb-serial-option is missing dependencies for the following libraries:
#     usb_wwan.ko
#     ERROR: package/kernel/linux failed to build.
#
# With both steps the result is 0 kmods, 0 firmware, 0 bootloaders, and ~64
# packages -- exactly what hermes-agent and luci-app-hermes-agent pull in
# through their own DEPENDS.

set -eu

sdk=${1:?usage: sdk-trim-config.sh <sdk-dir> [--restore|--no-defconfig]}
mode=${2:-trim}

cfg=$sdk/Config-build.in
orig=$cfg.pristine
dotcfg=$sdk/.config

ours='hermes-agent|luci-app-hermes-agent'

[ -f "$cfg" ] || { echo "not an SDK (no Config-build.in): $sdk" >&2; exit 1; }

# Counts come from .config, not from Config-build.in: after step 2 the file is
# no longer the whole story, and .config is what the build actually reads.
report() {
	[ -f "$dotcfg" ] || { printf '  %-10s (no .config yet)\n' "$1"; return 0; }
	printf '  %-10s packages:%-6s kmod:%-6s firmware:%-4s u-boot:%s\n' "$1" \
		"$(grep -c '^CONFIG_PACKAGE_.*=[ym]' "$dotcfg" || true)" \
		"$(grep -c '^CONFIG_PACKAGE_kmod.*=[ym]' "$dotcfg" || true)" \
		"$(grep -cE '^CONFIG_PACKAGE_[a-z0-9-]*firmware.*=[ym]' "$dotcfg" || true)" \
		"$(grep -cE '^CONFIG_PACKAGE_u-?boot.*=[ym]' "$dotcfg" || true)"
}

if [ "$mode" = "--restore" ]; then
	[ -f "$orig" ] || { echo "no pristine copy to restore: $orig" >&2; exit 1; }
	cp "$orig" "$cfg"
	echo "  restored $cfg; run 'make defconfig' in $sdk"
	exit 0
fi

[ -f "$orig" ] || cp "$cfg" "$orig"
report "before"

# Step 1: neutralise the promptless defaults. Every PACKAGE_* symbol plus the
# three ALL* switches -- those gate the `default m if ALL||ALL_NONSHARED` lines
# in tmp/.config-package.in, which would otherwise re-select every feed package.
awk '
	/^config [A-Za-z0-9_]/ { sym = $2 }

	(sym ~ /^PACKAGE_/ || sym ~ /^(ALL|ALL_KMODS|ALL_NONSHARED)$/) && /^\tdefault [ym]$/ {
		print "\tdefault n"
		next
	}

	{ print }
' "$orig" > "$cfg.new"
mv "$cfg.new" "$cfg"

# Step 2: drop the inherited package values. Keep everything else in .config --
# target, arch, toolchain and libc settings all live there and must survive.
if [ -f "$dotcfg" ]; then
	grep -vE "^(CONFIG_PACKAGE_|# CONFIG_PACKAGE_)" "$dotcfg" > "$dotcfg.new"
	printf 'CONFIG_PACKAGE_hermes-agent=m\nCONFIG_PACKAGE_luci-app-hermes-agent=m\n' >> "$dotcfg.new"
	mv "$dotcfg.new" "$dotcfg"
fi

if [ "$mode" = "--no-defconfig" ]; then
	echo "  note: run 'make defconfig' in $sdk to regenerate .config"
	exit 0
fi

# .config is derived from Config-build.in, so the change only takes effect after
# a refresh. Running it here also lets the script verify its own work.
( cd "$sdk" && make defconfig >/dev/null 2>&1 ) || {
	echo "make defconfig failed in $sdk" >&2
	exit 1
}
report "after"

selected=$(grep -cE "^CONFIG_PACKAGE_($ours)=m" "$dotcfg" || true)
if [ "$selected" != "2" ]; then
	echo "our packages are not selected after defconfig -- is the feed installed?" >&2
	echo "  (./scripts/feeds src-link hermes-openwrt <repo>/packages && ./scripts/feeds install -a)" >&2
	exit 1
fi

kmods=$(grep -c '^CONFIG_PACKAGE_kmod.*=[ym]' "$dotcfg" || true)
if [ "$kmods" != "0" ]; then
	# Not fatal -- but a partial kmod set is the one state that reliably breaks
	# package/kernel/linux, so say so loudly rather than 40 minutes later.
	echo "  warning: $kmods kernel modules still selected; package/kernel/linux may fail" >&2
	echo "  warning: its .ko dependency closure cannot be resolved from Config-build.in" >&2
fi
