#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-h11
PKG_VERSION:=0.16.0
PKG_RELEASE:=1

PYPI_NAME:=h11
PKG_HASH:=4e35b956cf45792e4caa5885e69fba00bdbc6ffafbfa020300e549b208ee5ff1

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-h11
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Pure-Python HTTP/1.1 protocol implementation
  URL:=https://pypi.org/project/h11/
  DEPENDS:=
endef

define Package/python3-h11/description
  Pure-Python HTTP/1.1 protocol implementation
  (vendored for hermes-agent 0.16.0)
endef

$(eval $(call Py3Package,python3-h11))
$(eval $(call BuildPackage,python3-h11))
