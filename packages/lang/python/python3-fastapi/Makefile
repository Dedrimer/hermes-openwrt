#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-fastapi
PKG_VERSION:=0.141.1
PKG_RELEASE:=1

PYPI_NAME:=fastapi
PKG_HASH:=e8822fc40db1e1858054d7a949a888695bc9bdce70139178e33bd2871a453ca1

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-fastapi
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Modern, fast web framework for building APIs
  URL:=https://pypi.org/project/fastapi/
  DEPENDS:=+python3-annotated-doc +python3-pydantic +python3-starlette +python3-typing-extensions +python3-typing-inspection
endef

define Package/python3-fastapi/description
  Modern, fast web framework for building APIs
  (vendored for hermes-agent 0.141.1)
endef

$(eval $(call Py3Package,python3-fastapi))
$(eval $(call BuildPackage,python3-fastapi))
