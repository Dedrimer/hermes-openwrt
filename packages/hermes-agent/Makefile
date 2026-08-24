#
# Hermes Agent for OpenWrt
#
# Two design rules drive everything in this file:
#
#  1. ZERO upstream source modifications. There is no patches/ directory. The
#     sdist/wheel guard in upstream setup.py is unlocked with HERMES_NIX_BUILD=1
#     -- upstream's own escape hatch for distro packagers -- and the runtime
#     asset paths are injected through the HERMES_BUNDLED_* env vars that
#     upstream's nix/ and Homebrew packaging already rely on.
#
#  2. UPGRADES MUST BE CHEAP. Every Python dependency is resolved from
#     upstream's own uv.lock by scripts/sync-deps.py into deps/*.mk. There is no
#     hand-maintained dependency table anywhere in this repo.
#
# To move to a new Hermes release:
#     python3 scripts/sync-deps.py --ref <tag-or-commit>
#     # then copy the PKG_VERSION / PKG_SOURCE_VERSION it prints in below
# That is the entire procedure.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=hermes-agent
PKG_VERSION:=0.20.5
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/NousResearch/hermes-agent.git
PKG_SOURCE_VERSION:=30d4555085ec684ff140d5841b5456b5d2291a72
PKG_SOURCE_DATE:=2026-08-23
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Dedrimer
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

# Host tooling only: we build one wheel and unpack many. Nothing is compiled
# for the target -- every native dependency arrives as a musllinux wheel.
PKG_BUILD_DEPENDS:=python3/host python-build/host python-installer/host \
	python-setuptools/host python-wheel/host

PKG_CONFIG_DEPENDS:=CONFIG_HERMES_AGENT_OPTIONAL_SKILLS

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/python/python3-package.mk

# --------------------------------------------------------------------------
# Target selection
# --------------------------------------------------------------------------
# The dependency wheels are prebuilt binaries, so the CPython ABI tag and the
# musl arch select which generated fragment applies. PYTHON3_VERSION comes from
# the packages feed (3.11 on 24.10, 3.13 on 25.12); OpenWrt's ARCH values
# "x86_64" and "aarch64" happen to match the musllinux platform tags verbatim.
HERMES_PY_TAG:=cp$(subst .,,$(PYTHON3_VERSION))
HERMES_MUSL_ARCH:=$(ARCH)

HERMES_PREFIX:=/usr/lib/hermes-agent
HERMES_SHARE:=/usr/share/hermes-agent
HERMES_SITE:=$(HERMES_PREFIX)/lib/python$(PYTHON3_VERSION)/site-packages

# HERMES_HOME. Upstream explicitly supports pointing this outside ~/.hermes for
# packaged/container deployments (see get_default_hermes_root(): "In Docker or
# custom deployments where HERMES_HOME points outside ~/.hermes (e.g.
# /opt/data), returns HERMES_HOME directly -- that IS the root"). We follow that
# pattern so config.yaml, .env, the session DB and caches all live in one
# writable directory. Putting config.yaml under /etc would not work: Hermes
# rewrites it itself via atomic replace, which would clobber a symlink.
HERMES_HOME:=/srv/hermes

HERMES_STAGE:=$(PKG_BUILD_DIR)/openwrt-stage
HERMES_BUILD_OUT:=$(PKG_BUILD_DIR)/openwrt-build

# musllinux wheels are built on Alpine, so some of their .so files carry a
# DT_NEEDED on Alpine's libc soname (libc.musl-<arch>.so.1). OpenWrt ships the
# same musl under a different name, so a private compat symlink -- reachable
# only through this package's LD_LIBRARY_PATH -- bridges the two without
# touching the system library namespace.
HERMES_MUSL_SONAME:=libc.musl-$(HERMES_MUSL_ARCH).so.1

define Package/hermes-agent
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Hermes Agent
  URL:=https://github.com/NousResearch/hermes-agent
  DEPENDS:=@(x86_64||aarch64) +python3 +ca-bundle
endef

define Package/hermes-agent/description
Hermes is Nous Research's open agent runtime: a tool-using LLM agent with a
skill system, a plugin system and a JSON-RPC/WebSocket gateway.

Ships with a self-contained Python dependency tree (prebuilt musllinux wheels
resolved from upstream's uv.lock), the bundled skills/plugins/locales assets,
and a procd service for the headless gateway that luci-app-hermes-agent drives.

Restricted to x86_64 and aarch64: those are the only architectures with
complete musllinux wheel coverage for the dependency closure.

The interactive terminal UI is not included -- it is a Node/TypeScript
application. Use the LuCI web interface instead.
endef

define Package/hermes-agent/config
	config HERMES_AGENT_OPTIONAL_SKILLS
		bool "Include the optional skill catalog (adds ~9 MB)"
		depends on PACKAGE_hermes-agent
		default n
		help
		  Installs optional-skills/ alongside the always-bundled skills/.
		  Only worth the flash if you intend to enable those skills.
endef

# Only the UCI service-control file is a conffile. Hermes' own config.yaml and
# .env live under $(HERMES_HOME) because Hermes manages them itself; they are
# preserved across sysupgrade via /lib/upgrade/keep.d instead.
define Package/hermes-agent/conffiles
/etc/config/hermes-agent
endef

# --------------------------------------------------------------------------
# Dependency wheels (generated -- see scripts/sync-deps.py)
# --------------------------------------------------------------------------
# These must be included AFTER package.mk: each $(call Download,...) hooks
# itself onto DOWNLOAD_RDEP (= $(STAMP_PREPARED)), so the wheels are fetched and
# hash-verified before Build/Prepare runs.
include $(CURDIR)/deps/wheels-common.mk
include $(CURDIR)/deps/wheels-$(HERMES_PY_TAG)-$(HERMES_MUSL_ARCH).mk

HERMES_DEP_WHEELS:=$(foreach w,$(HERMES_WHEELS_COMMON) $(HERMES_WHEELS_NATIVE),$(DL_DIR)/$(w))

define Build/Compile
	# ---- 1. build the Hermes wheel ------------------------------------
	# HERMES_NIX_BUILD=1 unlocks upstream's packaging guard in setup.py, which
	# is why this package needs no patches.
	# --skip-dependency-check: upstream pins setuptools==83.0.0 exactly in
	# build-system.requires. The SDK's host setuptools drives the same plain
	# setuptools.build_meta backend, and fetching an unpinned wheel from PyPI
	# mid-build would break offline and reproducible builds.
	$(call Python3/Run, \
		$(PKG_BUILD_DIR), \
		-m build \
			--no-isolation \
			--skip-dependency-check \
			--wheel \
			--outdir "$(HERMES_BUILD_OUT)" \
			"$(PKG_BUILD_DIR)" \
		, \
		HERMES_NIX_BUILD=1 \
	)

	# ---- 2. unpack Hermes + its entire dependency closure -------------
	# `installer` writes real .dist-info/RECORD metadata. That is required, not
	# cosmetic: upstream calls importlib.metadata.version() in several modules
	# (gateway/platforms/api_server.py, tools/lazy_deps.py, ...), so simply
	# copying source trees onto sys.path -- the obvious shortcut -- would raise
	# PackageNotFoundError at runtime.
	rm -rf $(HERMES_STAGE)
	$(INSTALL_DIR) $(HERMES_STAGE)
	for whl in $(HERMES_BUILD_OUT)/*.whl $(HERMES_DEP_WHEELS); do \
		$(call Python3/Run, \
			$(PKG_BUILD_DIR), \
			-m installer \
				--destdir "$(HERMES_STAGE)" \
				--prefix "$(HERMES_PREFIX)" \
				--no-compile-bytecode \
				"$$$$whl" \
		) || exit 1; \
	done
endef

define Package/hermes-agent/install
	# ---- private site-packages -----------------------------------------
	$(INSTALL_DIR) $(1)$(HERMES_SITE)
	$(CP) $(HERMES_STAGE)$(HERMES_SITE)/. $(1)$(HERMES_SITE)/
	-find $(1)$(HERMES_SITE) -type d -name '__pycache__' -prune -exec rm -rf {} +
	-find $(1)$(HERMES_SITE) -type d -name 'tests' -prune -exec rm -rf {} +

	# ---- console scripts ------------------------------------------------
	# Keep every entry-point script the wheels declared, not just hermes':
	# the wrapper puts this dir on PATH so agent tools can shell out to
	# dependency CLIs. They are a few hundred bytes each.
	$(INSTALL_DIR) $(1)$(HERMES_PREFIX)/bin
	$(CP) $(HERMES_STAGE)$(HERMES_PREFIX)/bin/. $(1)$(HERMES_PREFIX)/bin/
	$(call Python3/FixShebang,$(1)$(HERMES_PREFIX)/bin/*)

	# ---- musl soname compat --------------------------------------------
	$(INSTALL_DIR) $(1)$(HERMES_PREFIX)/compat
	$(LN) /lib/libc.so $(1)$(HERMES_PREFIX)/compat/$(HERMES_MUSL_SONAME)

	# ---- stdlib shims ---------------------------------------------------
	# OpenWrt's python3 packaging splits the stdlib and drops webbrowser.py
	# entirely -- there is no python3-webbrowser to depend on -- while upstream
	# imports it at module scope in auth.py and portal_cli.py, both pulled in
	# while main() builds its parser. Without this, every subcommand raises
	# ModuleNotFoundError before it starts. The wrapper appends this directory
	# after site-packages, so it cannot shadow a real dependency.
	$(INSTALL_DIR) $(1)$(HERMES_PREFIX)/shims
	$(INSTALL_DATA) ./files/shims/*.py $(1)$(HERMES_PREFIX)/shims/

	# ---- bundled runtime assets ----------------------------------------
	# Resolved at runtime through HERMES_BUNDLED_* / HERMES_OPTIONAL_* (see
	# hermes_constants.py); deliberately not inside the wheel.
	$(INSTALL_DIR) $(1)$(HERMES_SHARE)
	$(CP) $(PKG_BUILD_DIR)/skills $(1)$(HERMES_SHARE)/
	$(CP) $(PKG_BUILD_DIR)/plugins $(1)$(HERMES_SHARE)/
	$(CP) $(PKG_BUILD_DIR)/locales $(1)$(HERMES_SHARE)/
	$(CP) $(PKG_BUILD_DIR)/optional-mcps $(1)$(HERMES_SHARE)/
ifeq ($(CONFIG_HERMES_AGENT_OPTIONAL_SKILLS),y)
	$(CP) $(PKG_BUILD_DIR)/optional-skills $(1)$(HERMES_SHARE)/
endif

	# ---- seed config (copied into $(HERMES_HOME) by postinst) -----------
	$(INSTALL_DIR) $(1)$(HERMES_SHARE)/defaults
	$(INSTALL_CONF) ./files/config.yaml.default $(1)$(HERMES_SHARE)/defaults/config.yaml
	$(INSTALL_CONF) ./files/env.default $(1)$(HERMES_SHARE)/defaults/env

	# ---- wrapper --------------------------------------------------------
	# One script dispatched on $$0, symlinked for the three entry points.
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/hermes-wrapper $(1)/usr/bin/hermes
	$(SED) 's,@PREFIX@,$(HERMES_PREFIX),g' \
		-e 's,@SHARE@,$(HERMES_SHARE),g' \
		-e 's,@SITE@,$(HERMES_SITE),g' \
		-e 's,@HOME@,$(HERMES_HOME),g' \
		-e 's,@VERSION@,$(PKG_VERSION),g' \
		-e 's,@REVISION@,$(PKG_SOURCE_VERSION),g' \
		$(1)/usr/bin/hermes
	$(LN) hermes $(1)/usr/bin/hermes-agent
	$(LN) hermes $(1)/usr/bin/hermes-acp

	# ---- service + UCI --------------------------------------------------
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/hermes-agent.init $(1)/etc/init.d/hermes-agent
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/hermes-agent.config $(1)/etc/config/hermes-agent

	# ---- preserve config across sysupgrade ------------------------------
	# sysupgrade walks the paths listed here (see sbin/sysupgrade
	# list_static_conffiles). Only the two config files -- never the session DB.
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/hermes-agent.upgrade $(1)/lib/upgrade/keep.d/hermes-agent
endef

define Package/hermes-agent/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

HOME_DIR="$(HERMES_HOME)"
DEFAULTS="$(HERMES_SHARE)/defaults"

mkdir -p "$$HOME_DIR"
chmod 0750 "$$HOME_DIR"

# Never overwrite an existing config -- this runs on upgrades too.
[ -f "$$HOME_DIR/config.yaml" ] || cp "$$DEFAULTS/config.yaml" "$$HOME_DIR/config.yaml"
[ -f "$$HOME_DIR/.env" ]        || cp "$$DEFAULTS/env" "$$HOME_DIR/.env"

# API keys live here, so keep it unreadable to non-root.
chmod 0600 "$$HOME_DIR/.env"
chmod 0640 "$$HOME_DIR/config.yaml"

exit 0
endef

$(eval $(call BuildPackage,hermes-agent))
