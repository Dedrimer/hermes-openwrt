#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-typing-extensions
PKG_VERSION:=4.16.0
PKG_RELEASE:=1

PYPI_NAME:=typing-extensions
PYPI_SOURCE_NAME:=typing_extensions
PKG_HASH:=dc983d19a509c94dba722ee6abd33940f7c05a89e243c47e907eb4db6f1a43e5

PKG_LICENSE:=PSF-2.0

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-typing-extensions
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Backported and experimental type hints for Python
  URL:=https://pypi.org/project/typing-extensions/
  DEPENDS:=
endef

define Package/python3-typing-extensions/description
  Backported and experimental type hints for Python
  (vendored for hermes-agent 4.16.0)
endef

$(eval $(call Py3Package,python3-typing-extensions))
$(eval $(call BuildPackage,python3-typing-extensions))
