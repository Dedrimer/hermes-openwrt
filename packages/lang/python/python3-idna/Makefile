#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-idna
PKG_VERSION:=3.18
PKG_RELEASE:=1

PYPI_NAME:=idna
PKG_HASH:=ffb385a7e039654cef1ab9ef32c6fafe283c0c0467bba1d9029738ce4a14a848

PKG_LICENSE:=BSD-3-Clause

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-idna
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Internationalized Domain Names in Applications (RFC 3490)
  URL:=https://pypi.org/project/idna/
  DEPENDS:=
endef

define Package/python3-idna/description
  Internationalized Domain Names in Applications (RFC 3490)
  (vendored for hermes-agent 3.18)
endef

$(eval $(call Py3Package,python3-idna))
$(eval $(call BuildPackage,python3-idna))
