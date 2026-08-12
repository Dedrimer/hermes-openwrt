#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-httpcore
PKG_VERSION:=1.0.9
PKG_RELEASE:=1

PYPI_NAME:=httpcore
PKG_HASH:=6e34463af53fd2ab5d807f399a9b45ea31c3dfa2276f15a2c3f00afff6e176e8

PKG_LICENSE:=BSD-3-Clause

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-httpcore
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Minimal low-level HTTP client
  URL:=https://pypi.org/project/httpcore/
  DEPENDS:=+python-certifi +python3-h11
endef

define Package/python3-httpcore/description
  Minimal low-level HTTP client
  (vendored for hermes-agent 1.0.9)
endef

$(eval $(call Py3Package,python3-httpcore))
$(eval $(call BuildPackage,python3-httpcore))
