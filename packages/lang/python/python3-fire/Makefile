#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-fire
PKG_VERSION:=0.7.1
PKG_RELEASE:=1

PYPI_NAME:=fire
PKG_HASH:=3b208f05c736de98fb343310d090dcc4d8c78b2a89ea4f32b837c586270a9cbf

PKG_LICENSE:=Apache-2.0

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-fire
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Automatically generate command line interfaces
  URL:=https://pypi.org/project/fire/
  DEPENDS:=+python3-termcolor
endef

define Package/python3-fire/description
  Automatically generate command line interfaces
  (vendored for hermes-agent 0.7.1)
endef

$(eval $(call Py3Package,python3-fire))
$(eval $(call BuildPackage,python3-fire))
