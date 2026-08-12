#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-python-multipart
PKG_VERSION:=0.0.32
PKG_RELEASE:=1

PYPI_NAME:=python-multipart
PYPI_SOURCE_NAME:=python_multipart
PKG_HASH:=be54b7f3fa167bb83e4fcd936b887b708f4e57fe75911c02aebf53efaf8d938e

PKG_LICENSE:=Apache-2.0

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-python-multipart
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Multipart form data parsing
  URL:=https://pypi.org/project/python-multipart/
  DEPENDS:=
endef

define Package/python3-python-multipart/description
  Multipart form data parsing
  (vendored for hermes-agent 0.0.32)
endef

$(eval $(call Py3Package,python3-python-multipart))
$(eval $(call BuildPackage,python3-python-multipart))
