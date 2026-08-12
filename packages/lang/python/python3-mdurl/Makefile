#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-mdurl
PKG_VERSION:=0.1.2
PKG_RELEASE:=1

PYPI_NAME:=mdurl
PKG_HASH:=bb413d29f5eea38f31dd4754dd7377d4465116fb207585f97bf925588687c1ba

PKG_LICENSE:=UNKNOWN

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-mdurl
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Markdown URL utilities
  URL:=https://pypi.org/project/mdurl/
  DEPENDS:=
endef

define Package/python3-mdurl/description
  Markdown URL utilities
  (vendored for hermes-agent 0.1.2)
endef

$(eval $(call Py3Package,python3-mdurl))
$(eval $(call BuildPackage,python3-mdurl))
