#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-jiter
PKG_VERSION:=0.16.0
PKG_RELEASE:=1

# Rust extension: instead of cross-compiling with the buildroot Rust
# toolchain, use the prebuilt musllinux wheels (self-contained, no
# glibc dependency). One PKG_SOURCE/PKG_SOURCE_URL/PKG_HASH set per
# {Python version, CPU} combination below.
#
# Supported CPU architectures: aarch64, x86_64

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

ifeq ($(filter aarch64 x86_64,$(ARCH)),)

# No musllinux wheel for ARCH=$(ARCH); python3-jiter is not defined on this
# architecture (hermes-agent therefore cannot be built here either).

else

# wheels are .zip containers - download.pl does not unpack them
PKG_UNPACK:=unzip -o $(DL_DIR)/$(PKG_SOURCE) -d $(PKG_BUILD_DIR)

ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.10)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=jiter-0.16.0-cp310-cp310-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/9d/70/c6c23e76ebb3766b111bc399437bbc9f870a76e2a92e10b2a5f561d57372
    PKG_HASH:=2c842cbf374a8daf50b2c04212995bee34ca2ac2cdc29a901b4cdb072c9c4131
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=jiter-0.16.0-cp310-cp310-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/2a/d3/0001c8c0c5976af2625bb1cfb1895e8ec693b6589fe4574b8e6fc2c85501
    PKG_HASH:=5ed466aee31294d7cdcd4d37dfe5c42c97bc29d9a5f00eacf24504358309cb9b
  endif
endif
ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.11)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=jiter-0.16.0-cp311-cp311-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/3b/dc/7b2f303a2847207e265503853a2d964a55354cffd62a5f2936c155486798
    PKG_HASH:=adff21bc78edfe086c15eb495b900306076de378dc2337c132401fc39bd79c91
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=jiter-0.16.0-cp311-cp311-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/c2/5f/501cf6e1e09caeb420195179ffc6f62aca603f1220ec53fd80d0d70b3e56
    PKG_HASH:=dab907db06fc593645e73109acf4581ba5b548897d28b9348dc41ddc8343b2d3
  endif
endif
ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.12)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=jiter-0.16.0-cp312-cp312-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/d9/8c/554691e48bc711299c0a293dd8a6179e24b2d66a54dc295421fcf64569c0
    PKG_HASH:=44d019fa8cdaf89bf29c71b39e3712143fdd0ac76725c6ef954f9957a5ea8730
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=jiter-0.16.0-cp312-cp312-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/a4/cb/01e9d69dc2cc6759d4f91e230b34489c4fdb2518992650633f9e20bece89
    PKG_HASH:=0df91907609837f33341b8e6fe73b95991fdaa57caf1a0fbd343dffe826f386f
  endif
endif
ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.13)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=jiter-0.16.0-cp313-cp313-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/8b/d6/5fbc2f7d6b67b754caa61a993a2e626e815dec47ffc2f9e35f01adfebec7
    PKG_HASH:=6edb63a46e65a82c26800a868e49b2cac30dd5a4218b88d74bc2c848c8ad60bb
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=jiter-0.16.0-cp313-cp313-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/ed/54/284f0164b64a5fed915fea6ba7e9ba9b3d8d37c67d59cf2e3bb99d45cdfe
    PKG_HASH:=659039cc50b5addcc35fcc87ae2c1833b7c0a8e5326ef631a75e4478447bcf84
  endif
endif
ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.9)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=jiter-0.16.0-cp39-cp39-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/bb/1d/eb4261cdf94d4a485a47e3544ff1ee4e8a752b24aedeae250dc00a238166
    PKG_HASH:=2a0d46ef67cc58d906a6132dd3040ca70ae4f0b0d7c9c052fe432c658a69b3f6
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=jiter-0.16.0-cp39-cp39-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/b1/c3/a7dd14c86bcd04e7b0d5d13937e980f94085b61c0eec12622eaa159965c4
    PKG_HASH:=70a490b55634dc0d2606ce8a8e01b1d62459011beb368d15d76e1eaf62460e3d
  endif
endif

ifndef PKG_SOURCE
$(error python3-jiter: no wheel for Python $(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR) / ARCH=$(ARCH))
endif

define Build/Compile
	$(INSTALL_DIR) $(PKG_INSTALL_DIR)$(PYTHON3_PKG_DIR)
	$(CP) $(PKG_BUILD_DIR)/. $(PKG_INSTALL_DIR)$(PYTHON3_PKG_DIR)/
endef

define Package/python3-jiter
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Fast iterable JSON parser
  URL:=https://pypi.org/project/jiter/
  DEPENDS:=
endef

define Package/python3-jiter/description
  Fast iterable JSON parser
  (vendored for hermes-agent 0.16.0)
endef

$(eval $(call Py3Package,python3-jiter))
$(eval $(call BuildPackage,python3-jiter))

endif
