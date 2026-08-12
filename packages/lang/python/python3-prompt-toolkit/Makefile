#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-prompt-toolkit
PKG_VERSION:=3.0.52
PKG_RELEASE:=1

PYPI_NAME:=prompt-toolkit
PYPI_SOURCE_NAME:=prompt_toolkit
PKG_HASH:=28cde192929c8e7321de85de1ddbe736f1375148b02f2e17edd840042b1be855

PKG_LICENSE:=UNKNOWN

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-prompt-toolkit
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Library for building powerful interactive command lines
  URL:=https://pypi.org/project/prompt-toolkit/
  DEPENDS:=+python-wcwidth
endef

define Package/python3-prompt-toolkit/description
  Library for building powerful interactive command lines
  (vendored for hermes-agent 3.0.52)
endef

$(eval $(call Py3Package,python3-prompt-toolkit))
$(eval $(call BuildPackage,python3-prompt-toolkit))
