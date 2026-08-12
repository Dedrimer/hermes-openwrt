#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-typing-inspection
PKG_VERSION:=0.4.4
PKG_RELEASE:=1

PYPI_NAME:=typing-inspection
PYPI_SOURCE_NAME:=typing_inspection
PKG_HASH:=547274fa6b0a561ccf549cc9524b999a578e737d015d8709d021f9d0d13bea47

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-typing-inspection
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Runtime typing introspection tools
  URL:=https://pypi.org/project/typing-inspection/
  DEPENDS:=+python3-typing-extensions
endef

define Package/python3-typing-inspection/description
  Runtime typing introspection tools
  (vendored for hermes-agent 0.4.4)
endef

$(eval $(call Py3Package,python3-typing-inspection))
$(eval $(call BuildPackage,python3-typing-inspection))
