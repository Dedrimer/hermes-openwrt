#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-tqdm
PKG_VERSION:=4.70.0
PKG_RELEASE:=1

PYPI_NAME:=tqdm
PKG_HASH:=55b0b0dbd97462d06ebee91e4dac24ed4d4702be82b24f07e6c1d27e08cea220

PKG_LICENSE:=MPL-2.0 AND MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-tqdm
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Fast, Extensible Progress Meter
  URL:=https://pypi.org/project/tqdm/
  DEPENDS:=
endef

define Package/python3-tqdm/description
  Fast, Extensible Progress Meter
  (vendored for hermes-agent 4.70.0)
endef

$(eval $(call Py3Package,python3-tqdm))
$(eval $(call BuildPackage,python3-tqdm))
