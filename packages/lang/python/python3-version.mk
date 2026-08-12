#
# python3-version.mk for the hermes-openwrt feed
#
# Upstream OpenWrt keeps one copy of this file per release branch
# (24.10 = Python 3.11, 25.12 = Python 3.13), but this feed must serve
# both build systems from a single git tree, so the Python version is
# resolved in this order:
#
#   1. If the official packages feed is present (feeds/*/lang/python/
#      python3-version.mk), its pinned values are used. This makes the
#      feed auto-adapt to whichever SDK (24.10 or 25.12) it is built
#      against - no extra flags needed.
#   2. Otherwise the defaults below apply (3.11, matching 24.10). When
#      building against the 25.12 SDK without the packages feed, pass
#      the version explicitly, e.g.:
#
#        make package/hermes-agent/compile \
#          PYTHON3_VERSION_MAJOR=3 PYTHON3_VERSION_MINOR=13
#

PYTHON3_UPSTREAM_VERSION_MK:=$(firstword $(wildcard $(TOPDIR)/feeds/*/lang/python/python3-version.mk))
-include $(PYTHON3_UPSTREAM_VERSION_MK)

PYTHON3_VERSION_MAJOR?=3
PYTHON3_VERSION_MINOR?=11
PYTHON3_VERSION_MICRO?=14

PYTHON3_VERSION:=$(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR)

# PEP 425 wheel tag for the musllinux wheels used by pydantic-core/jiter,
# e.g. cp311 / cp313. Only CPython is supported by OpenWrt.
PY3_TAG:=cp$(subst .,,$(PYTHON3_VERSION))
