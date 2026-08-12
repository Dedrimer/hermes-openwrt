#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-pathspec
PKG_VERSION:=1.1.1
PKG_RELEASE:=1

PYPI_NAME:=pathspec
PKG_HASH:=17db5ecd524104a120e173814c90367a96a98d07c45b2e10c2f3919fff91bf5a

PKG_LICENSE:=UNKNOWN

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-pathspec
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Utility library for gitignore style pattern matching
  URL:=https://pypi.org/project/pathspec/
  DEPENDS:=
endef

define Package/python3-pathspec/description
  Utility library for gitignore style pattern matching
  (vendored for hermes-agent 1.1.1)
endef

$(eval $(call Py3Package,python3-pathspec))
$(eval $(call BuildPackage,python3-pathspec))
