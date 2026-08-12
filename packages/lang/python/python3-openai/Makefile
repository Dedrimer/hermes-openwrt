#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-openai
PKG_VERSION:=2.24.0
PKG_RELEASE:=1

PYPI_NAME:=openai
PKG_HASH:=1e5769f540dbd01cb33bc4716a23e67b9d695161a734aff9c5f925e2bf99a673

PKG_LICENSE:=Apache-2.0

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-openai
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=The official Python library for the OpenAI API
  URL:=https://pypi.org/project/openai/
  DEPENDS:=+python3-anyio +python-distro +python3-httpx +python3-jiter +python3-pydantic +python-sniffio +python3-tqdm +python3-typing-extensions
endef

define Package/python3-openai/description
  The official Python library for the OpenAI API
  (vendored for hermes-agent 2.24.0)
endef

$(eval $(call Py3Package,python3-openai))
$(eval $(call BuildPackage,python3-openai))
