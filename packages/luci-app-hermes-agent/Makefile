#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-hermes-agent
PKG_VERSION:=0.20.0
PKG_RELEASE:=1

# Version-tracked with the hermes-agent package it manages.

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
  service status and control, settings (UCI, API keys, config.yaml) and
  log viewer. Backed by an rpcd ucode plugin ("hermes-agent" ubus object).
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./htdocs $(PKG_BUILD_DIR)/ 2>/dev/null || true
	$(CP) ./root $(PKG_BUILD_DIR)/ 2>/dev/null || true
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
endef

# Flush the LuCI view/menu cache and let rpcd pick up the new ubus plugin.
define Package/luci-app-hermes-agent/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}
endef

$(eval $(call BuildPackage,luci-app-hermes-agent))
