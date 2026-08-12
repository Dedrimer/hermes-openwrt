#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-ptyprocess
PKG_VERSION:=0.7.0
PKG_RELEASE:=1

PYPI_NAME:=ptyprocess
PKG_HASH:=5c5d0a3b48ceee0b48485e0c26037c0acd7d29765ca3fbb5cb3831d347423220

PKG_LICENSE:=UNKNOWN

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-ptyprocess
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Run a subprocess in a pseudo terminal
  URL:=https://pypi.org/project/ptyprocess/
  DEPENDS:=
endef

define Package/python3-ptyprocess/description
  Run a subprocess in a pseudo terminal
  (vendored for hermes-agent 0.7.0)
endef

$(eval $(call Py3Package,python3-ptyprocess))
$(eval $(call BuildPackage,python3-ptyprocess))
