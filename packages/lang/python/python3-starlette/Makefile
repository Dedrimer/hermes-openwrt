#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-starlette
PKG_VERSION:=1.6.0
PKG_RELEASE:=1

PYPI_NAME:=starlette
PKG_HASH:=d4e3ac5e546444960c710297a3c9fc3f7ebae1b7e963f3d36173b49da535be9b

PKG_LICENSE:=BSD-3-Clause

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-starlette
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=The little ASGI framework that shines
  URL:=https://pypi.org/project/starlette/
  DEPENDS:=+python3-anyio +python3-typing-extensions
endef

define Package/python3-starlette/description
  The little ASGI framework that shines
  (vendored for hermes-agent 1.6.0)
endef

$(eval $(call Py3Package,python3-starlette))
$(eval $(call BuildPackage,python3-starlette))
