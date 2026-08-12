#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=hermes-agent
PKG_VERSION:=0.20.0
PKG_RELEASE:=1

# Tag v2026.8.3 (annotated tag, peeled to the commit)
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/nousresearch/hermes-agent.git
PKG_SOURCE_VERSION:=3c27eb6234bf91b8ceee9e9071591b31e9b148cb
PKG_SOURCE_DATE:=2026-08-03
PKG_MIRROR_HASH:=
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include $(INCLUDE_DIR)/package.mk
include ../lang/python/python3-package.mk

# openai 2.24.0 depends on the legacy httpx 0.28.x line (httpx<1), which is
# vendored here as python3-httpx. tzdata provides the IANA database that
# OpenWrt lacks (/usr/share/zoneinfo).
#
# Naming: OpenWrt >= 24.10 names its python packages with the "python-"
# prefix (python-yaml, python-requests, ...). The packages vendored in this
# feed keep the "python3-" prefix used inside this feed, while dependencies
# provided by the official packages feed are referenced by their official
# "python-" names. python3-sqlite3/python3-multiprocessing are stdlib
# split-off subpackages of the python3 meta package.
define Package/hermes-agent
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Hermes Agent - self-improving AI agent (Nous Research)
  URL:=https://github.com/nousresearch/hermes-agent
  DEPENDS:= \
    +python3-openai \
    +python-certifi \
    +python-dotenv \
    +python3-fire \
    +python3-httpx \
    +python3-pysocks \
    +python3-rich \
    +python3-tenacity \
    +python-yaml \
    +python-ruamel-yaml \
    +python-requests \
    +python-jinja2 \
    +python3-pydantic \
    +python3-prompt-toolkit \
    +python3-croniter \
    +python-packaging \
    +python-markdown \
    +python3-pyjwt \
    +python-cryptography \
    +python-urllib3 \
    +python-psutil \
    +python-websockets \
    +python3-pathspec \
    +python3-fastapi \
    +python3-uvicorn \
    +python3-python-multipart \
    +python3-ptyprocess \
    +pillow \
    +python3-tzdata \
    +python3-sqlite3 \
    +python3-multiprocessing
endef

define Package/hermes-agent/description
  Hermes Agent (Nous Research, v0.20.0) ported to OpenWrt as a native
  procd service. Provides the "hermes" CLI, the gateway daemon and the
  headless dashboard (hermes serve, default port 9119).

  This is a non-Docker, native port. Installation size is large
  (roughly 30-60 MB on disk); an extroot/USB or a device with ample
  flash is recommended.

  Note: upstream pins exact dependency versions; OpenWrt feed packages
  may be newer/older (see docs/PORTING.md for the deviation table).
  Unsupported upstream distribution methods (pip, uv) are replaced by
  this opkg/apk package - the setup.py build guard is bypassed.
endef

# /etc/hermes/config.yaml is generated from cli-config.yaml.example.
# opkg/apk treat files under /etc/ as conffiles, so user settings
# survive package upgrades automatically.

define Package/hermes-agent/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/hermes-agent.init $(1)/etc/init.d/hermes-agent
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/hermes-agent.config $(1)/etc/config/hermes-agent
	$(INSTALL_DIR) $(1)/etc/hermes
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/cli-config.yaml.example $(1)/etc/hermes/config.yaml
endef

define Package/hermes-agent/postinst
#!/bin/sh
# Create runtime directories owned by this package's data dir.
mkdir -p /etc/hermes/profiles /etc/hermes/logs
chmod 700 /etc/hermes
# Version stamp shown by the LuCI status page. Keep in sync with PKG_VERSION.
echo "0.20.0" > /etc/hermes/.version
exit 0
endef

$(eval $(call Py3Package,hermes-agent))
$(eval $(call BuildPackage,hermes-agent))
