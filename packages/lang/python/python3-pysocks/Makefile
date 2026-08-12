#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-pysocks
PKG_VERSION:=1.7.1
PKG_RELEASE:=1

PYPI_NAME:=pysocks
PYPI_SOURCE_NAME:=PySocks
PKG_HASH:=3f8804571ebe159c380ac6de37643bb4685970655d3bba243530d6558b799aa0

PKG_LICENSE:=BSD

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-pysocks
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=SOCKS4/5 proxy support for Python
  URL:=https://pypi.org/project/pysocks/
  DEPENDS:=
endef

define Package/python3-pysocks/description
  SOCKS4/5 proxy support for Python
  (vendored for hermes-agent 1.7.1)
endef

$(eval $(call Py3Package,python3-pysocks))
$(eval $(call BuildPackage,python3-pysocks))
