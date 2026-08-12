#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-pygments
PKG_VERSION:=2.20.0
PKG_RELEASE:=1

PYPI_NAME:=pygments
PKG_HASH:=6757cd03768053ff99f3039c1a36d6c0aa0b263438fcab17520b30a303a82b5f

PKG_LICENSE:=BSD-2-Clause

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-pygments
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Syntax highlighting package
  URL:=https://pypi.org/project/pygments/
  DEPENDS:=
endef

define Package/python3-pygments/description
  Syntax highlighting package
  (vendored for hermes-agent 2.20.0)
endef

$(eval $(call Py3Package,python3-pygments))
$(eval $(call BuildPackage,python3-pygments))
