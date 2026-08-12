#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-markdown-it-py
PKG_VERSION:=3.0.0
PKG_RELEASE:=1

PYPI_NAME:=markdown-it-py
PKG_HASH:=e3f60a94fa066dc52ec76661e37c851cb232d92f9886b15cb560aaada2df8feb

PKG_LICENSE:=UNKNOWN

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-markdown-it-py
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Markdown parser, done right
  URL:=https://pypi.org/project/markdown-it-py/
  DEPENDS:=+python3-mdurl
endef

define Package/python3-markdown-it-py/description
  Markdown parser, done right
  (vendored for hermes-agent 3.0.0)
endef

$(eval $(call Py3Package,python3-markdown-it-py))
$(eval $(call BuildPackage,python3-markdown-it-py))
