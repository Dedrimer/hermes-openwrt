#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=python3-pydantic-core
PKG_VERSION:=2.46.4
PKG_RELEASE:=1

# Rust extension: instead of cross-compiling with the buildroot Rust
# toolchain, use the prebuilt musllinux wheels (self-contained, no
# glibc dependency). One PKG_SOURCE/PKG_SOURCE_URL/PKG_HASH set per
# {Python version, CPU} combination below.
#
# Supported CPU architectures: aarch64, x86_64, armv7l

PKG_LICENSE:=MIT

PKG_MAINTAINER:=hermes-openwrt feed <https://github.com/hermes-openwrt>

include $(INCLUDE_DIR)/package.mk
include ../python3-package.mk

ifeq ($(filter aarch64 x86_64 arm_%,$(ARCH)),)

# No musllinux wheel for ARCH=$(ARCH); python3-pydantic-core is not defined on this
# architecture (hermes-agent therefore cannot be built here either).

else

# wheels are .zip containers - download.pl does not unpack them
PKG_UNPACK:=unzip -o $(DL_DIR)/$(PKG_SOURCE) -d $(PKG_BUILD_DIR)

ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.10)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp310-cp310-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/72/04/2beacf7e1607e93eefe4aed1b4709f079b905fb77530179d4f7c71745f22
    PKG_HASH:=daa27d92c36f24388fe3ad306b174781c747627f134452e4f128ea00ce1fe8c4
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp310-cp310-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/7c/af/0f7a5b85fec6075bea96e3ef9187de38fccced0de92c1e7feda8d5cc7bb9
    PKG_HASH:=c1747f85cee84c26985853c6f3d9bd3e75da5212912443fa111c113b9c246f39
  endif
  ifeq ($(filter arm_%,$(ARCH)),arm_%)
    PKG_SOURCE:=pydantic_core-2.46.4-cp310-cp310-musllinux_1_1_armv7l.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/9e/29/d2b9fd9f539133548eaf622c06a4ce176cb46ac59f32d0359c4abc0de047
    PKG_HASH:=19e51f073cd3df251856a8a4189fbdf1de4012c3ebacfb1884f94f1eb406079f
  endif
endif
ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.11)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp311-cp311-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/f7/52/7c529d7bdb2d1068bd52f51fe32572c8301f9a4febf1948f10639f1436f5
    PKG_HASH:=aaa2a54443eff1950ba5ddc6b6ccda0d9c84a364276a62f969bdf2a390650848
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp311-cp311-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/d9/37/f913f81a657c865b75da6c0dbed79876073c2a43b5bd9edbe8da785e4d49
    PKG_HASH:=a0f62d0a58f4e7da165457e995725421e0064f2255d8eccebc49f41bbc23b109
  endif
  ifeq ($(filter arm_%,$(ARCH)),arm_%)
    PKG_SOURCE:=pydantic_core-2.46.4-cp311-cp311-musllinux_1_1_armv7l.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/37/b3/7c40325848ba78247f2812dcf9c7274e38cd801820ca6dd9fe63bcfb0eb4
    PKG_HASH:=18e5ceec2ab67e6d5f1a9085e5a24c9c4e2ac4545730bfe668680bca05e555f3
  endif
endif
ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.12)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp312-cp312-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/ae/6c/fc44000918855b42779d007ae63b0532794739027b2f417321cddbc44f6a
    PKG_HASH:=b2f69dec1725e79a012d920df1707de5caf7ed5e08f3be4435e25803efc47458
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp312-cp312-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/d0/cf/c873d91679f3a30bcf5e7ac280ce5573483e72295307685120d0d5ad3416
    PKG_HASH:=fbdb89b3e1c94a30cc5edfce477c6e6a5dc4d8f84665b455c27582f211a1c72c
  endif
  ifeq ($(filter arm_%,$(ARCH)),arm_%)
    PKG_SOURCE:=pydantic_core-2.46.4-cp312-cp312-musllinux_1_1_armv7l.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/6b/65/d9cadc9f1920d7a127ad2edba16c1db7916e59719285cd6c94600b0080ba
    PKG_HASH:=8d0820e8192167f80d88d64038e609c31452eeca865b4e1d9950a27a4609b00b
  endif
endif
ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.13)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp313-cp313-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/5a/f2/c8d7773ede6af08036423a00ae0ceffce266c3c52a096c435d68c896083f
    PKG_HASH:=cbaf13819775b7f769bf4a1f066cb6df7a28d4480081a589828ef190226881cd
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp313-cp313-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/c2/eb/4f6c8a41efa30baa755590f4141abf3a8c370fab610915733e74134a7270
    PKG_HASH:=82cf5301172168103724d49a1444d3378cb20cdee30b116a1bd6031236298a5d
  endif
  ifeq ($(filter arm_%,$(ARCH)),arm_%)
    PKG_SOURCE:=pydantic_core-2.46.4-cp313-cp313-musllinux_1_1_armv7l.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/59/31/0c864784e31f09f05cdd87606f08923b9c9e7f6e51dd27f20f62f975ce9f
    PKG_HASH:=633147d34cf4550417f12e2b1a0383973bdf5cdfde212cb09e9a581cf10820be
  endif
endif
ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),3.9)
  ifeq ($(ARCH),aarch64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp39-cp39-musllinux_1_1_aarch64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/2a/21/fe9f039138c9ea3be10ccdb6ec490acb54dcbef5a5e96dbdf1411f82b929
    PKG_HASH:=228ee9bae8bef5b1e97ec58302f80357c37199e0d0a99174e138d28e6957b9d9
  endif
  ifeq ($(ARCH),x86_64)
    PKG_SOURCE:=pydantic_core-2.46.4-cp39-cp39-musllinux_1_1_x86_64.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/cd/14/fe3fbf6e845bf2080dc2f282d75085ddf79d037b35634ecde68f33c217b4
    PKG_HASH:=91a06d2e259ecfbd8c901d70c3c507900458498142b3026a296b7de4d1322cc9
  endif
  ifeq ($(filter arm_%,$(ARCH)),arm_%)
    PKG_SOURCE:=pydantic_core-2.46.4-cp39-cp39-musllinux_1_1_armv7l.whl
    PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/44/cb/19ca0da64821d1aefcef65f253aa9ecbdd0dde360f607d0f9b3d95db2b4e
    PKG_HASH:=10e17cbb10a330363733efc4d7c4d0dd827ac0909b8f6a6542298fed1ea62f29
  endif
endif

ifndef PKG_SOURCE
$(error python3-pydantic-core: no wheel for Python $(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR) / ARCH=$(ARCH))
endif

define Build/Compile
	$(INSTALL_DIR) $(PKG_INSTALL_DIR)$(PYTHON3_PKG_DIR)
	$(CP) $(PKG_BUILD_DIR)/. $(PKG_INSTALL_DIR)$(PYTHON3_PKG_DIR)/
endef

define Package/python3-pydantic-core
  SECTION:=lang
  CATEGORY:=Languages
  SUBMENU:=Python
  TITLE:=Core validation logic for pydantic, written in Rust
  URL:=https://pypi.org/project/pydantic-core/
  DEPENDS:=+python3-typing-extensions
endef

define Package/python3-pydantic-core/description
  Core validation logic for pydantic, written in Rust
  (vendored for hermes-agent 2.46.4)
endef

$(eval $(call Py3Package,python3-pydantic-core))
$(eval $(call BuildPackage,python3-pydantic-core))

endif
