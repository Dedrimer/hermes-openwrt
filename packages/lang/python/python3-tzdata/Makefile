#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-tzdata
PKG_VERSION:=2025.3
PKG_RELEASE:=1

PYPI_NAME:=tzdata
PKG_HASH:=de39c2ca5dc7b0344f2eba86f49d614019d29f060fc4ebc8a417896a620b56a7

PKG_LICENSE:=Apache-2.0

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-tzdata
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=IANA time zone database for Python
  URL:=https://pypi.org/project/tzdata/
  DEPENDS:=
endef

define Package/python3-tzdata/description
  IANA time zone database for Python
  (vendored for hermes-agent 2025.3)
endef

$(eval $(call Py3Package,python3-tzdata))
$(eval $(call BuildPackage,python3-tzdata))
