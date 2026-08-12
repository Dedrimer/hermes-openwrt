#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-pydantic
PKG_VERSION:=2.13.4
PKG_RELEASE:=1

PYPI_NAME:=pydantic
PKG_HASH:=c40756b57adaa8b1efeeced5c196f3f3b7c435f90e84ea7f443901bec8099ef6

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-pydantic
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Data validation using Python type hints
  URL:=https://pypi.org/project/pydantic/
  DEPENDS:=+python3-annotated-types +python3-pydantic-core +python3-typing-extensions +python3-typing-inspection
endef

define Package/python3-pydantic/description
  Data validation using Python type hints
  (vendored for hermes-agent 2.13.4)
endef

$(eval $(call Py3Package,python3-pydantic))
$(eval $(call BuildPackage,python3-pydantic))
