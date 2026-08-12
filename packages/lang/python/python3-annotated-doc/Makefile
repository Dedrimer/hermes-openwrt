#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-annotated-doc
PKG_VERSION:=0.0.5
PKG_RELEASE:=1

PYPI_NAME:=annotated-doc
PYPI_SOURCE_NAME:=annotated_doc
PKG_HASH:=c7e58ce09192557605d8bbd92836d7e1d520ac9580096042c0bfd197efacf1bb

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-annotated-doc
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Generate documentation for your pydantic models
  URL:=https://pypi.org/project/annotated-doc/
  DEPENDS:=
endef

define Package/python3-annotated-doc/description
  Generate documentation for your pydantic models
  (vendored for hermes-agent 0.0.5)
endef

$(eval $(call Py3Package,python3-annotated-doc))
$(eval $(call BuildPackage,python3-annotated-doc))
