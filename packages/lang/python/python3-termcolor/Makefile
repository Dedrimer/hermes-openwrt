#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-termcolor
PKG_VERSION:=3.3.0
PKG_RELEASE:=1

PYPI_NAME:=termcolor
PKG_HASH:=348871ca648ec6a9a983a13ab626c0acce02f515b9e1983332b17af7979521c5

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-termcolor
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=ANSI color formatting for output in terminal
  URL:=https://pypi.org/project/termcolor/
  DEPENDS:=
endef

define Package/python3-termcolor/description
  ANSI color formatting for output in terminal
  (vendored for hermes-agent 3.3.0)
endef

$(eval $(call Py3Package,python3-termcolor))
$(eval $(call BuildPackage,python3-termcolor))
