#!/usr/bin/env python3
"""Generate the python3-<pkg>/Makefile for every dependency vendored in the
hermes-openwrt feed.

Reads docs/package-versions.json (output of scripts/fetch-pypi-meta.py) and
emits:

  * a standard sdist Makefile (pypi.mk + Py3Package) for pure-Python
    packages - PKG_VERSION / PKG_HASH / PKG_LICENSE / DEPENDS are taken
    from the JSON plus the mapping tables below, and

  * a wheel-based Makefile for the Rust-extension packages (pydantic-core,
    jiter), which are fetched as prebuilt musllinux wheels selected per
    {Python version, CPU architecture} via conditional PKG_SOURCE /
    PKG_SOURCE_URL / PKG_HASH blocks (see docs/PORTING.md).

Usage:
    python3 scripts/gen-package-makefiles.py
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
META = json.load(open(os.path.join(ROOT, "docs", "package-versions.json")))
OUT_DIR = os.path.join(ROOT, "packages", "lang", "python")

# ---------------------------------------------------------------------------
# Metadata tables (source of truth for everything not in the PyPI JSON)
# ---------------------------------------------------------------------------

# openwrt binary package name each PyPI project maps to when it is *not*
# vendored here (i.e. reused from the official packages feed)
# openwrt binary package name each PyPI project maps to when it is *not*
# vendored here (i.e. reused from the official packages feed). Note that
# OpenWrt >= 24.10 names python packages with the "python-" prefix.
FEED_REUSE = {
    "sniffio": "python-sniffio",
    "certifi": "python-certifi",
    "python-dateutil": "python-dateutil",
    "wcwidth": "python-wcwidth",
    "click": "python-click",
    "distro": "python-distro",
}

# DEPENDS for each vendored package (openwrt package names).  +python3-*
# entries without a vendor package here resolve against the official feed.
DEPENDS = {
    "annotated-doc": [],                       # no runtime deps
    "annotated-types": [],
    "anyio": ["+python3-idna",
              "+python3-typing-extensions"],   # te only <3.13; harmless superset
    "croniter": ["+python-dateutil"],
    "fastapi": ["+python3-annotated-doc", "+python3-pydantic",
                "+python3-starlette", "+python3-typing-extensions",
                "+python3-typing-inspection"],
    "fire": ["+python3-termcolor"],
    "h11": [],
    "httpcore": ["+python-certifi", "+python3-h11"],
    "httpx": ["+python3-anyio", "+python-certifi", "+python3-httpcore",
              "+python3-idna", "+python3-socksio"],
    "idna": [],
    "jiter": [],
    "markdown-it-py": ["+python3-mdurl"],
    "mdurl": [],
    "openai": ["+python3-anyio", "+python-distro", "+python3-httpx",
               "+python3-jiter", "+python3-pydantic", "+python-sniffio",
               "+python3-tqdm", "+python3-typing-extensions"],
    "pathspec": [],
    "prompt-toolkit": ["+python-wcwidth"],
    "ptyprocess": [],
    "pydantic": ["+python3-annotated-types", "+python3-pydantic-core",
                 "+python3-typing-extensions", "+python3-typing-inspection"],
    "pydantic-core": ["+python3-typing-extensions"],
    "pygments": [],
    "pyjwt": [],
    "python-multipart": [],
    "rich": ["+python3-markdown-it-py", "+python3-pygments"],
    "socksio": [],
    "starlette": ["+python3-anyio", "+python3-typing-extensions"],  # te needed on 3.11
    "tenacity": [],
    "termcolor": [],
    "tqdm": [],
    "pysocks": [],
    "typing-extensions": [],
    "tzdata": [],
    "typing-inspection": ["+python3-typing-extensions"],
    "uvicorn": ["+python-click", "+python3-h11"],
}

TITLES = {
    "annotated-doc": "Generate documentation for your pydantic models",
    "annotated-types": "Reusable constraint types for pydantic",
    "anyio": "Asynchronous compatibility layer for asyncio, trio and curio",
    "croniter": "Cron-like scheduling for Python",
    "fastapi": "Modern, fast web framework for building APIs",
    "fire": "Automatically generate command line interfaces",
    "h11": "Pure-Python HTTP/1.1 protocol implementation",
    "httpcore": "Minimal low-level HTTP client",
    "httpx": "Next generation HTTP client",
    "idna": "Internationalized Domain Names in Applications (RFC 3490)",
    "jiter": "Fast iterable JSON parser",
    "markdown-it-py": "Markdown parser, done right",
    "mdurl": "Markdown URL utilities",
    "openai": "The official Python library for the OpenAI API",
    "pathspec": "Utility library for gitignore style pattern matching",
    "prompt-toolkit": "Library for building powerful interactive command lines",
    "ptyprocess": "Run a subprocess in a pseudo terminal",
    "pydantic": "Data validation using Python type hints",
    "pydantic-core": "Core validation logic for pydantic, written in Rust",
    "pygments": "Syntax highlighting package",
    "pyjwt": "JSON Web Token implementation in Python",
    "python-multipart": "Multipart form data parsing",
    "rich": "Rich text and beautiful formatting in the terminal",
    "socksio": "Sans-I/O implementation of SOCKS4/5",
    "starlette": "The little ASGI framework that shines",
    "tenacity": "Retry library for Python",
    "termcolor": "ANSI color formatting for output in terminal",
    "tqdm": "Fast, Extensible Progress Meter",
    "pysocks": "SOCKS4/5 proxy support for Python",
    "typing-extensions": "Backported and experimental type hints for Python",
    "typing-inspection": "Runtime typing introspection tools",
    "tzdata": "IANA time zone database for Python",
    "uvicorn": "The lightning-fast ASGI server",
}

# Rust-extension packages served as prebuilt musllinux wheels instead of
# being cross-compiled:  {pypi_name: {openwrt_arch_pattern: wheel_arch_tag}}
WHEEL_PACKAGES = {
    "pydantic-core": {
        "aarch64": "aarch64",
        "x86_64": "x86_64",
        # arm_* (e.g. arm_cortex-a7) map to the musllinux armv7l wheels;
        # these require a hard-float target (FEATURES has "fpu").
        "arm_%": "armv7l",
    },
    "jiter": {
        # jiter publishes no armv7l wheels - arm_* targets are unsupported
        "aarch64": "aarch64",
        "x86_64": "x86_64",
    },
}

MAINTAINER = "hermes-openwrt feed <https://github.com/hermes-openwrt>"

HEADER = """#
# Copyright (C) 2026 hermes-openwrt feed contributors
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
"""


def norm(name):
    return re.sub(r"[-_.]+", "-", name.lower())


def verify_depends():
    """Cross-check the DEPENDS table against requires_dist from PyPI."""
    # pypi project name -> openwrt binary package name (vendored or feed-reuse)
    openwrt_of = {k: f"python3-{k}" for k in META}
    openwrt_of.update(FEED_REUSE)
    for name, deps in DEPENDS.items():
        req = {openwrt_of.get(norm(m.group(1)), norm(m.group(1))) for m in
               (re.match(r"([A-Za-z0-9_.-]+)", d) for d in META[name]["requires_dist"])
               if m
               # optional-dependency groups never apply on OpenWrt
               and "extra == " not in m.group(0)}
        # deps we declare that PyPI does not list (skip ";-marked" extras)
        extra = {d.lstrip("+") for d in deps} - req
        if extra:
            print(f"NOTE {name}: declared deps not in requires_dist: {sorted(extra)}")
        # deps PyPI lists that we do not declare (skip env-marked ones)
        undeclared = req - {d.lstrip("+") for d in deps}
        if undeclared:
            print(f"WARN {name}: requires_dist deps not declared: {sorted(undeclared)}")


def sdist_makefile(pypi_name, rec):
    version = rec["version"]
    pkg = f"python3-{pypi_name}"
    url = rec["url"]
    fname = url.rsplit("/", 1)[-1]
    src_name, src_ext = fname.rsplit("-" + version + ".", 1)
    lines = [
        HEADER,
        "include $(TOPDIR)/rules.mk",
        "",
        f"PKG_NAME:={pkg}",
        f"PKG_VERSION:={version}",
        "PKG_RELEASE:=1",
        "",
        f"PYPI_NAME:={pypi_name}",
    ]
    # PyPI normalizes sdist filenames per PEP 625 ({name}_{version}.tar.gz);
    # pypi.mk needs PYPI_SOURCE_NAME when it differs from the PyPI project name
    if src_name != pypi_name:
        lines += [
            f"PYPI_SOURCE_NAME:={src_name}",
        ]
    lines += [
        f"PKG_HASH:={rec['sha256']}",
        "",
        f"PKG_LICENSE:={rec['license']}",
        "",
        f"PKG_MAINTAINER:={MAINTAINER}",
        "",
        "include ../pypi.mk",
        "include $(INCLUDE_DIR)/package.mk",
        "include ../python3-package.mk",
        "",
        f"define Package/{pkg}",
        "  SECTION:=lang",
        "  CATEGORY:=Languages",
        "  SUBMENU:=Python",
        f"  TITLE:={TITLES[pypi_name]}",
        f"  URL:=https://pypi.org/project/{pypi_name}/",
        f"  DEPENDS:={' '.join(DEPENDS[pypi_name])}",
        "endef",
        "",
        f"define Package/{pkg}/description",
        f"  {TITLES[pypi_name]}",
        f"  (vendored for hermes-agent {version})",
        "endef",
        "",
        f"$(eval $(call Py3Package,{pkg}))",
        f"$(eval $(call BuildPackage,{pkg}))",
        "",
    ]
    return "\n".join(lines)


def wheel_makefile(pypi_name, rec):
    version = rec["version"]
    pkg = f"python3-{pypi_name}"
    arch_map = WHEEL_PACKAGES[pypi_name]
    wheels = {w["filename"]: w for w in rec["wheels_musllinux"]}
    blocks = []
    pyversions = sorted({fn.split("-")[2] for fn in wheels})
    for pyver in pyversions:
        blocks.append(
            f"ifeq ($(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR),"
            f"{pyver[2]}.{pyver[3:]})"
        )
        for arch_pat, wheel_arch in arch_map.items():
            fname = f"{pypi_name.replace('-', '_')}-{version}-{pyver}-{pyver}-musllinux_1_1_{wheel_arch}.whl"
            w = wheels.get(fname)
            if not w:
                raise SystemExit(f"missing wheel {fname}")
            url_dir = w["url"].rsplit("/", 1)[0]
            blocks.append(f"  ifeq ($(filter {arch_pat},$(ARCH)),{arch_pat})"
                          if arch_pat.endswith("%")
                          else f"  ifeq ($(ARCH),{arch_pat})")
            blocks.append(f"    PKG_SOURCE:={fname}")
            blocks.append(f"    PKG_SOURCE_URL:={url_dir}")
            blocks.append(f"    PKG_HASH:={w['sha256']}")
            blocks.append("  endif")
        blocks.append("endif")
    cond = "\n".join(blocks)
    lines = [
        HEADER,
        "include $(TOPDIR)/rules.mk",
        "",
        f"PKG_NAME:={pkg}",
        f"PKG_VERSION:={version}",
        "PKG_RELEASE:=1",
        "",
        "# Rust extension: instead of cross-compiling with the buildroot Rust",
        "# toolchain, use the prebuilt musllinux wheels (self-contained, no",
        "# glibc dependency). One PKG_SOURCE/PKG_SOURCE_URL/PKG_HASH set per",
        "# {Python version, CPU} combination below.",
        "#",
        "# Supported CPU architectures: "
        + ", ".join("armv7l" if a.endswith("%") else a for a in arch_map.values()),
        "",
        f"PKG_LICENSE:={rec['license']}",
        "",
        f"PKG_MAINTAINER:={MAINTAINER}",
        "",
        "include $(INCLUDE_DIR)/package.mk",
        "include ../python3-package.mk",
        "",
        f"ifeq ($(filter {' '.join(arch_map)},$(ARCH)),)",
        "",
        f"# No musllinux wheel for ARCH=$(ARCH); {pkg} is not defined on this",
        "# architecture (hermes-agent therefore cannot be built here either).",
        "",
        "else",
        "",
        "# wheels are .zip containers - download.pl does not unpack them",
        f"PKG_UNPACK:=unzip -o $(DL_DIR)/$(PKG_SOURCE) -d $(PKG_BUILD_DIR)",
        "",
        cond,
        "",
        "ifndef PKG_SOURCE",
        f"$(error {pkg}: no wheel for Python $(PYTHON3_VERSION_MAJOR).$(PYTHON3_VERSION_MINOR) / ARCH=$(ARCH))",
        "endif",
        "",
        f"define Build/Compile",
        "\t$(INSTALL_DIR) $(PKG_INSTALL_DIR)$(PYTHON3_PKG_DIR)",
        "\t$(CP) $(PKG_BUILD_DIR)/. $(PKG_INSTALL_DIR)$(PYTHON3_PKG_DIR)/",
        "endef",
        "",
        f"define Package/{pkg}",
        "  SECTION:=lang",
        "  CATEGORY:=Languages",
        "  SUBMENU:=Python",
        f"  TITLE:={TITLES[pypi_name]}",
        f"  URL:=https://pypi.org/project/{pypi_name}/",
        f"  DEPENDS:={' '.join(DEPENDS[pypi_name])}",
        "endef",
        "",
        f"define Package/{pkg}/description",
        f"  {TITLES[pypi_name]}",
        f"  (vendored for hermes-agent {version})",
        "endef",
        "",
        f"$(eval $(call Py3Package,{pkg}))",
        f"$(eval $(call BuildPackage,{pkg}))",
        "",
        "endif",
        "",
    ]
    return "\n".join(lines)


def main():
    verify_depends()
    os.makedirs(OUT_DIR, exist_ok=True)
    count = 0
    for pypi_name, rec in sorted(META.items()):
        if pypi_name not in TITLES:
            raise SystemExit(f"missing TITLES entry for {pypi_name}")
        if pypi_name not in DEPENDS:
            raise SystemExit(f"missing DEPENDS entry for {pypi_name}")
        sub = os.path.join(OUT_DIR, f"python3-{pypi_name}")
        os.makedirs(sub, exist_ok=True)
        with open(os.path.join(sub, "Makefile"), "w", newline="\n") as f:
            if pypi_name in WHEEL_PACKAGES:
                f.write(wheel_makefile(pypi_name, rec))
            else:
                f.write(sdist_makefile(pypi_name, rec))
        count += 1
    print(f"generated {count} package Makefiles in {OUT_DIR}")


if __name__ == "__main__":
    main()
