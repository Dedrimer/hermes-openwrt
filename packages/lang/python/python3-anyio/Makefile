#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-anyio
PKG_VERSION:=4.14.2
PKG_RELEASE:=1

PYPI_NAME:=anyio
PKG_HASH:=cfa139f3ed1a23ee8f88a145ddb5ac7605b8bbfd8592baacd7ce3d8bb4313c7f

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-anyio
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Asynchronous compatibility layer for asyncio, trio and curio
  URL:=https://pypi.org/project/anyio/
  DEPENDS:=+python3-idna +python3-typing-extensions
endef

define Package/python3-anyio/description
  Asynchronous compatibility layer for asyncio, trio and curio
  (vendored for hermes-agent 4.14.2)
endef

$(eval $(call Py3Package,python3-anyio))
$(eval $(call BuildPackage,python3-anyio))
