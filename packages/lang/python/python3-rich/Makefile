#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-rich
PKG_VERSION:=14.3.3
PKG_RELEASE:=1

PYPI_NAME:=rich
PKG_HASH:=b8daa0b9e4eef54dd8cf7c86c03713f53241884e814f4e2f5fb342fe520f639b

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-rich
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Rich text and beautiful formatting in the terminal
  URL:=https://pypi.org/project/rich/
  DEPENDS:=+python3-markdown-it-py +python3-pygments
endef

define Package/python3-rich/description
  Rich text and beautiful formatting in the terminal
  (vendored for hermes-agent 14.3.3)
endef

$(eval $(call Py3Package,python3-rich))
$(eval $(call BuildPackage,python3-rich))
