#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-pyjwt
PKG_VERSION:=2.13.0
PKG_RELEASE:=1

PYPI_NAME:=pyjwt
PKG_HASH:=41571c89ca91598c79e8ef18a2d07367d4810fbbd6f637794879baf1b7703423

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-pyjwt
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=JSON Web Token implementation in Python
  URL:=https://pypi.org/project/pyjwt/
  DEPENDS:=
endef

define Package/python3-pyjwt/description
  JSON Web Token implementation in Python
  (vendored for hermes-agent 2.13.0)
endef

$(eval $(call Py3Package,python3-pyjwt))
$(eval $(call BuildPackage,python3-pyjwt))
