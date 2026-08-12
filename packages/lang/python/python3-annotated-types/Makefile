#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-annotated-types
PKG_VERSION:=0.8.0
PKG_RELEASE:=1

PYPI_NAME:=annotated-types
PYPI_SOURCE_NAME:=annotated_types
PKG_HASH:=13b2beaad985e05e2d6407ee4c4f35590b11f8d693a258a561055cac8f64cab7

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-annotated-types
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Reusable constraint types for pydantic
  URL:=https://pypi.org/project/annotated-types/
  DEPENDS:=
endef

define Package/python3-annotated-types/description
  Reusable constraint types for pydantic
  (vendored for hermes-agent 0.8.0)
endef

$(eval $(call Py3Package,python3-annotated-types))
$(eval $(call BuildPackage,python3-annotated-types))
