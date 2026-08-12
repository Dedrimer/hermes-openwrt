#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-croniter
PKG_VERSION:=6.0.0
PKG_RELEASE:=1

PYPI_NAME:=croniter
PKG_HASH:=37c504b313956114a983ece2c2b07790b1f1094fe9d81cc94739214748255577

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include ../pypi.mk
include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

define Package/python3-croniter
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Cron-like scheduling for Python
  URL:=https://pypi.org/project/croniter/
  DEPENDS:=+python-dateutil
endef

define Package/python3-croniter/description
  Cron-like scheduling for Python
  (vendored for hermes-agent 6.0.0)
endef

$(eval $(call Py3Package,python3-croniter))
$(eval $(call BuildPackage,python3-croniter))
