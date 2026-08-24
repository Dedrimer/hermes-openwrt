#!/bin/sh
#
# Verify that a feed build produced packages containing what the Makefiles
# promise. Run it against an SDK directory after `make package/*/compile`:
#
#     scripts/check-artifacts.sh /path/to/openwrt-sdk-...
#
# Why this exists: a missing $(INSTALL_BIN) line does not fail the build. It
# produces a package that installs cleanly and then does nothing -- the LuCI
# menu entry appears, the view 404s, and the only symptom is an empty page. The
# checks below are the cheapest place to catch that, and CI runs the same script
# so it cannot drift from what a human runs by hand.
#
# Handles both packaging formats: .apk (apk-tools v3, OpenWrt 25.12+) and .ipk
# (opkg, 24.10 and earlier). Both are unpacked into a scratch directory and then
# checked with plain path globs, so the two paths differ only in the extractor.

set -eu

sdk=${1:?usage: check-artifacts.sh <sdk-dir>}
sdk=$(cd "$sdk" && pwd)

fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

say() { printf '%s\n' "$*"; }

# Locate one package by name, accepting either format. apk names files
# <name>-<version>-r<rel>.apk, opkg names them <name>_<version>-r<rel>_<arch>.ipk,
# so the separator is the one thing we must not hard-code.
find_pkg() {
	find "$sdk/bin" -type f \
		\( -name "$1-[0-9]*.apk" -o -name "$1_[0-9]*.ipk" \) 2>/dev/null |
		sort | tail -n 1
}

extract() {
	pkg=$1
	dest=$2
	mkdir -p "$dest"

	case $pkg in
	*.apk)
		# apk v3 archives are not plain tarballs; use the SDK's own host tool.
		# --allow-untrusted because a locally built package carries no signature.
		apk_bin=$sdk/staging_dir/host/bin/apk
		[ -x "$apk_bin" ] || apk_bin=$(command -v apk || true)
		[ -n "$apk_bin" ] || { say "  ! no apk tool available to read $pkg"; return 1; }
		"$apk_bin" extract --allow-untrusted --destination "$dest" "$pkg" >/dev/null 2>&1
		;;
	*.ipk)
		# An .ipk is an ar or tar archive holding data.tar.gz; 24.10 produces the
		# tar flavour, older releases the ar flavour. Try both.
		if tar -xzOf "$pkg" ./data.tar.gz 2>/dev/null | tar -xz -C "$dest" 2>/dev/null; then
			:
		else
			(cd "$dest" && ar x "$pkg" data.tar.gz 2>/dev/null) &&
				tar -xzf "$dest/data.tar.gz" -C "$dest" && rm -f "$dest/data.tar.gz"
		fi
		;;
	*)
		say "  ! unknown package format: $pkg"
		return 1
		;;
	esac
}

# Each argument is a glob relative to the package root. A leading @ marks the
# entry as a directory that must be non-empty rather than a file.
check_paths() {
	root=$1
	shift

	for want in "$@"; do
		case $want in
		@*)
			path=${want#@}
			# shellcheck disable=SC2086
			if [ -n "$(find $root$path -mindepth 1 -print -quit 2>/dev/null)" ]; then
				say "  ok  $path/ (non-empty)"
			else
				say "  MISSING  $path/"
				fail=1
			fi
			;;
		*)
			# shellcheck disable=SC2086
			set -- $root$want
			if [ -e "$1" ] || [ -L "$1" ]; then
				say "  ok  $want"
			else
				say "  MISSING  $want"
				fail=1
			fi
			;;
		esac
	done
}

# --- hermes-agent ----------------------------------------------------------

pkg=$(find_pkg hermes-agent)

if [ -z "$pkg" ]; then
	say "MISSING PACKAGE: hermes-agent"
	fail=1
else
	say "hermes-agent: $(basename "$pkg") ($(( $(wc -c <"$pkg") / 1024 )) KiB)"
	if extract "$pkg" "$tmp/agent"; then
		check_paths "$tmp/agent" \
			/usr/bin/hermes \
			/usr/bin/hermes-agent \
			/usr/bin/hermes-acp \
			/etc/init.d/hermes-agent \
			/etc/config/hermes-agent \
			/lib/upgrade/keep.d/hermes-agent \
			'/usr/lib/hermes-agent/compat/libc.musl-*.so.1' \
			/usr/lib/hermes-agent/shims/webbrowser.py \
			'/usr/lib/hermes-agent/lib/python3.*/site-packages/hermes_cli/web_server.py' \
			'/usr/lib/hermes-agent/lib/python3.*/site-packages/hermes_agent-*.dist-info/RECORD' \
			'@/usr/share/hermes-agent/skills' \
			'@/usr/share/hermes-agent/plugins' \
			'@/usr/share/hermes-agent/locales' \
			/usr/share/hermes-agent/defaults/config.yaml \
			/usr/share/hermes-agent/defaults/env

		# The wheels carry native extensions; a build that silently picked the
		# wrong musllinux fragment shows up here as an empty set.
		n=$(find "$tmp/agent/usr/lib/hermes-agent" -name '*.so' 2>/dev/null | wc -l)
		say "  info  bundled native extensions: $n"
		[ "$n" -gt 0 ] || { say "  MISSING  no .so files -- wrong wheel set?"; fail=1; }

		# Every dependency must have real metadata: upstream calls
		# importlib.metadata.version() at runtime in several modules.
		d=$(find "$tmp/agent/usr/lib/hermes-agent" -maxdepth 4 -name '*.dist-info' 2>/dev/null | wc -l)
		say "  info  dist-info directories: $d"
		[ "$d" -gt 10 ] || { say "  MISSING  too few dist-info dirs"; fail=1; }
	else
		fail=1
	fi
fi

# --- luci-app-hermes-agent -------------------------------------------------

pkg=$(find_pkg luci-app-hermes-agent)

if [ -z "$pkg" ]; then
	say "MISSING PACKAGE: luci-app-hermes-agent"
	fail=1
else
	say "luci-app-hermes-agent: $(basename "$pkg") ($(( $(wc -c <"$pkg") / 1024 )) KiB)"
	if extract "$pkg" "$tmp/luci"; then
		check_paths "$tmp/luci" \
			/www/luci-static/resources/view/hermes-agent/overview.js \
			/www/luci-static/resources/view/hermes-agent/chat.js \
			/www/luci-static/resources/view/hermes-agent/settings.js \
			/usr/share/luci/menu.d/luci-app-hermes-agent.json \
			/usr/share/rpcd/acl.d/luci-app-hermes-agent.json \
			/usr/share/rpcd/ucode/luci.hermes-agent \
			/usr/sbin/hermes-chatd \
			/etc/init.d/hermes-chatd

		# The two scripts must be executable, or procd starts nothing.
		for x in /usr/sbin/hermes-chatd /etc/init.d/hermes-chatd; do
			if [ -x "$tmp/luci$x" ]; then
				say "  ok  $x is executable"
			else
				say "  MISSING  $x is not executable"
				fail=1
			fi
		done

		# Stale views deleted from the tree must not reappear from a dirty
		# PKG_BUILD_DIR: Build/Prepare copies into it without clearing it first.
		for x in logs.js status.js; do
			if [ -e "$tmp/luci/www/luci-static/resources/view/hermes-agent/$x" ]; then
				say "  STALE  $x is still being packaged"
				fail=1
			fi
		done
	else
		fail=1
	fi
fi

say ""
if [ "$fail" -eq 0 ]; then
	say "ARTIFACTS OK"
else
	say "ARTIFACT CHECK FAILED"
fi

exit "$fail"
