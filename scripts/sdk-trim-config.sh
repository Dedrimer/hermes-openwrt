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
# Three mechanisms keep those packages selected, and missing any one of them
# makes the trim look like it silently does nothing:
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
#      `make defconfig`. These 1392 symbols have to be changed in the file.
#
#      Note the parse order in Config.in: Config-build.in is sourced *before*
#      tmp/.config-package.in, and for a symbol declared twice the first
#      matching `default` wins. So this file decides the base packages even
#      though the other one also declares them, with a prompt.
#
#   2. Feed packages are *also* declared in tmp/.config-package.in, and there
#      they do have a prompt. A visible symbol keeps its value from .config --
#      and the .config an SDK ships already says =m for all of them. So even
#      after step 1, dropping those lines from .config is required.
#
#   3. Those same 10905 prompted symbols carry `default m if ALL||ALL_NONSHARED`,
#      and the SDK's own Config.in (not the generated Config-build.in) declares
#      all three ALL switches a second time *with* prompts:
#
#          config ALL
#          	bool "Select all userspace packages by default"
#          	default y
#
#      A prompted symbol takes its value from .config, so ALL cannot be turned
#      off by editing Config-build.in -- it has to be turned off in .config.
#      This is the step that was missing, and it hid for a long time because a
#      long-lived SDK usually has `# CONFIG_ALL is not set` from some earlier
#      menuconfig. On a *fresh* SDK -- which is what CI always has -- ALL
#      defaults to y and 9832 packages plus 186 kmods survive the trim.
#
# Doing only step 1 leaves a *partial* kmod selection, which is worse than
# leaving everything on: Config-build.in carries no `select` lines at all (0 of
# them, against 24268 in tmp/.config-package.in), so kconfig has no way to
# compute the kmod dependency closure. comgt-ncm selects kmod-usb-serial-option,
# nothing then selects kmod-usb-serial-wwan, and package/kernel/linux fails its
# .ko closure check:
#
#     Package kmod-usb-serial-option is missing dependencies for the following libraries:
#     usb_wwan.ko
#     ERROR: package/kernel/linux failed to build.
#
# That is why the assertions at the bottom are fatal. With all three steps the
# result is 0 kmods, 0 firmware, 0 bootloaders, and ~64 packages -- exactly what
# hermes-agent and luci-app-hermes-agent pull in through their own DEPENDS.

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

# Step 1: neutralise the promptless defaults in Config-build.in. PACKAGE_* only
# -- the ALL* switches are handled in step 2, because in this file they are
# duplicate declarations of symbols the SDK's Config.in already declared with a
# prompt, and editing them here has no effect whatsoever.
awk '
	/^config [A-Za-z0-9_]/ { sym = $2 }

	sym ~ /^PACKAGE_/ && /^\tdefault [ym]$/ {
		print "\tdefault n"
		next
	}

	{ print }
' "$orig" > "$cfg.new"
mv "$cfg.new" "$cfg"

# Step 2: fix up .config. Two edits, and note this runs even when there is no
# .config yet -- a fresh SDK ships without one, and that is precisely the case
# where turning ALL off matters. Everything kconfig needs to fill in the blanks
# (target, arch, toolchain, libc) is a default in Config-build.in.
#
#   - drop the inherited package values, keeping every other line: the prompted
#     declarations in tmp/.config-package.in would otherwise hold their =m;
#   - turn the three ALL switches off, which is what stops
#     `default m if ALL||ALL_NONSHARED` from re-selecting all 10905 of them.
: > "$dotcfg.new"
if [ -f "$dotcfg" ]; then
	grep -vE "^(CONFIG_PACKAGE_|# CONFIG_PACKAGE_|CONFIG_ALL(_KMODS|_NONSHARED)?=|# CONFIG_ALL(_KMODS|_NONSHARED)? )" \
		"$dotcfg" > "$dotcfg.new"
fi
cat >> "$dotcfg.new" <<'EOF'
# CONFIG_ALL is not set
# CONFIG_ALL_KMODS is not set
# CONFIG_ALL_NONSHARED is not set
CONFIG_PACKAGE_hermes-agent=m
CONFIG_PACKAGE_luci-app-hermes-agent=m
EOF
mv "$dotcfg.new" "$dotcfg"

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
	echo "  (the feed name must match /^\\w+\$/; a hyphen is a feeds.conf syntax error)" >&2
	echo "  echo \"src-link hermes <repo>/packages\" >> feeds.conf && ./scripts/feeds install -a" >&2
	exit 1
fi

# A partial kmod set is the one state that reliably breaks package/kernel/linux,
# and it does so in the packaging phase, 40 minutes in. Firmware and bootloaders
# are only expensive, but a non-zero count there means the trim did not take, so
# treat the whole lot as fatal rather than warning into a log nobody reads. This
# used to be a warning, and it duly warned through every green run while CI
# built the kmod universe.
bad=
for what in kmod firmware u-boot; do
	case $what in
	kmod)     n=$(grep -c '^CONFIG_PACKAGE_kmod.*=[ym]' "$dotcfg" || true) ;;
	firmware) n=$(grep -cE '^CONFIG_PACKAGE_[a-z0-9-]*firmware.*=[ym]' "$dotcfg" || true) ;;
	u-boot)   n=$(grep -cE '^CONFIG_PACKAGE_u-?boot.*=[ym]' "$dotcfg" || true) ;;
	esac
	[ "$n" = "0" ] || { echo "  error: $n $what packages still selected" >&2; bad=1; }
done
if [ -n "$bad" ]; then
	grep -E '^(CONFIG_ALL|# CONFIG_ALL)' "$dotcfg" >&2 || true
	echo "  the three ALL switches above must all read 'is not set' -- they are" >&2
	echo "  prompted symbols in the SDK's Config.in, so .config is what decides" >&2
	echo "  them, and 'default m if ALL||ALL_NONSHARED' re-selects every feed" >&2
	echo "  package while any of them is y." >&2
	exit 1
fi
