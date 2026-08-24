#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-hermes-agent
PKG_VERSION:=0.20.5
PKG_RELEASE:=2

# Version-tracked with the hermes-agent package it manages; PKG_RELEASE moves on
# its own for packaging fixes (r2: the Settings page silently discarded API keys,
# see docs/PORTING.md §7).

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-hermes-agent
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Hermes Agent - LuCI management interface
  URL:=https://github.com/nousresearch/hermes-agent
  DEPENDS:=+luci-base +rpcd-mod-ucode +hermes-agent
  PKGARCH:=all
endef

define Package/luci-app-hermes-agent/description
  LuCI management interface for the native OpenWrt Hermes Agent port:
  service status and control with a log tail, settings (UCI, API keys,
  config.yaml) and an embedded chat page. Backed by an rpcd ucode plugin
  (the "luci.hermes-agent" ubus object) and hermes-chatd, a small resident
  bridge that holds the gateway's websocket on the page's behalf.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./htdocs $(PKG_BUILD_DIR)/ 2>/dev/null || true
	$(CP) ./root $(PKG_BUILD_DIR)/ 2>/dev/null || true
	$(CP) ./files $(PKG_BUILD_DIR)/ 2>/dev/null || true
endef

define Build/Compile
endef

define Package/luci-app-hermes-agent/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/hermes-agent
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/hermes-agent/*.js \
		$(1)/www/luci-static/resources/view/hermes-agent/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-hermes-agent.json \
		$(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/acl.d/luci-app-hermes-agent.json \
		$(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/ucode/luci.hermes-agent \
		$(1)/usr/share/rpcd/ucode/

	# The chat bridge. Python 3 stdlib only -- it rides the interpreter that
	# hermes-agent already depends on, so this adds no packages.
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/hermes-chatd $(1)/usr/sbin/hermes-chatd
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/hermes-chatd.init $(1)/etc/init.d/hermes-chatd
endef

# Flush the LuCI view/menu cache, let rpcd pick up the new ubus plugin, and
# bring the bridge up. `enable` is unconditional but `start` is not: the init
# script exits quietly when the gateway is disabled in UCI, so this is a no-op
# on a fresh install and a real start on an upgrade.
define Package/luci-app-hermes-agent/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	/etc/init.d/hermes-chatd enable 2>/dev/null
	/etc/init.d/hermes-chatd restart 2>/dev/null
	exit 0
}
endef

define Package/luci-app-hermes-agent/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	/etc/init.d/hermes-chatd stop 2>/dev/null
	/etc/init.d/hermes-chatd disable 2>/dev/null
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-hermes-agent))
