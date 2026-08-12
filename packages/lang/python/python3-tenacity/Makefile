#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-tenacity
PKG_VERSION:=9.1.4
PKG_RELEASE:=1

PYPI_NAME:=tenacity
PKG_HASH:=adb31d4c263f2bd041081ab33b498309a57c77f9acf2db65aadf0898179cf93a

PKG_LICENSE:=Apache 2.0

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-tenacity
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Retry library for Python
  URL:=https://pypi.org/project/tenacity/
  DEPENDS:=
endef

define Package/python3-tenacity/description
  Retry library for Python
  (vendored for hermes-agent 9.1.4)
endef

$(eval $(call Py3Package,python3-tenacity))
$(eval $(call BuildPackage,python3-tenacity))
