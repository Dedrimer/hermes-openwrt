#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-httpx
PKG_VERSION:=0.28.1
PKG_RELEASE:=1

PYPI_NAME:=httpx
PKG_HASH:=75e98c5f16b0f35b567856f597f06ff2270a374470a5c2392242528e3e3e42fc

PKG_LICENSE:=BSD-3-Clause

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-httpx
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Next generation HTTP client
  URL:=https://pypi.org/project/httpx/
  DEPENDS:=+python3-anyio +python-certifi +python3-httpcore +python3-idna +python3-socksio
endef

define Package/python3-httpx/description
  Next generation HTTP client
  (vendored for hermes-agent 0.28.1)
endef

$(eval $(call Py3Package,python3-httpx))
$(eval $(call BuildPackage,python3-httpx))
