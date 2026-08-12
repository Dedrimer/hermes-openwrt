#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-uvicorn
PKG_VERSION:=0.52.1
PKG_RELEASE:=1

PYPI_NAME:=uvicorn
PKG_HASH:=112ec661814189acbccd3f7b86460147cc065fc92c0821afa78918780e4354dd

PKG_LICENSE:=BSD-3-Clause

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-uvicorn
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=The lightning-fast ASGI server
  URL:=https://pypi.org/project/uvicorn/
  DEPENDS:=+python-click +python3-h11
endef

define Package/python3-uvicorn/description
  The lightning-fast ASGI server
  (vendored for hermes-agent 0.52.1)
endef

$(eval $(call Py3Package,python3-uvicorn))
$(eval $(call BuildPackage,python3-uvicorn))
