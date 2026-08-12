#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-socksio
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PYPI_NAME:=socksio
PKG_HASH:=f88beb3da5b5c38b9890469de67d0cb0f9d494b78b106ca1845f96c10b91c4ac

PKG_LICENSE:=UNKNOWN

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-socksio
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Sans-I/O implementation of SOCKS4/5
  URL:=https://pypi.org/project/socksio/
  DEPENDS:=
endef

define Package/python3-socksio/description
  Sans-I/O implementation of SOCKS4/5
  (vendored for hermes-agent 1.0.0)
endef

$(eval $(call Py3Package,python3-socksio))
$(eval $(call BuildPackage,python3-socksio))
