#!/usr/bin/env python3
"""Fetch PyPI metadata (version, sdist sha256, requires_dist) for the
python3-* packages vendored in this feed, so PKG_VERSION/PKG_HASH/DEPENDS
can be filled in accurately.

Usage:
    python3 scripts/fetch-pypi-meta.py > docs/package-versions.json

The output is also used by PORTING.md's version-pin table.
"""

import json
import sys
import urllib.request

# (pypi_name, pinned_version_or_None)
# Pinned = exact version required by hermes-agent 0.20.0's pyproject.toml
# (tag v2026.8.3). None = pick latest stable (transitive deps).
PACKAGES = [
    ("annotated-doc", None),        # fastapi 0.14x dep
    ("anyio", None),                # httpx/httpcore/starlette dep
    ("annotated-types", None),      # pydantic dep
    ("croniter", "6.0.0"),          # hermes pin
    ("fastapi", None),              # hermes: >=0.104,<1 -> latest
    ("fire", "0.7.1"),              # hermes pin
    ("h11", None),                  # httpcore/uvicorn dep
    ("httpcore", None),             # httpx dep
    ("httpx", "0.28.1"),            # hermes pin
    ("idna", "3.18"),               # httpx dep; feed only has 3.6/3.11
    ("jiter", None),                # openai dep (rust ext)
    ("markdown-it-py", "3.0.0"),    # rich dep; pin 3.x (4.x untested w/ rich 14)
    ("mdurl", None),                # markdown-it-py dep
    ("openai", "2.24.0"),           # hermes pin (old httpx<1 line, not 3.x!)
    ("pathspec", "1.1.1"),          # hermes pin
    ("prompt-toolkit", "3.0.52"),   # hermes pin
    ("ptyprocess", None),           # hermes: >=0.7,<1 -> latest
    ("pydantic", "2.13.4"),         # hermes pin
    ("pydantic-core", "2.46.4"),    # required exactly by pydantic 2.13.4 (rust)
    ("pygments", None),             # rich dep
    ("pyjwt", "2.13.0"),            # hermes pin (plain, no [crypto] extra)
    ("python-multipart", None),     # hermes: >=0.0.9,<1 -> latest
    ("rich", "14.3.3"),             # hermes pin
    ("socksio", None),              # httpx[socks] dep
    ("starlette", None),            # fastapi dep
    ("tenacity", "9.1.4"),          # hermes pin
    ("termcolor", None),            # fire dep
    ("tqdm", None),                 # openai dep
    ("typing-extensions", None),    # pydantic/anyio/starlette dep
    ("typing-inspection", None),    # pydantic/fastapi dep
    ("uvicorn", None),              # hermes: >=0.24,<1 -> latest
    ("pysocks", "1.7.1"),           # httpx[socks] dep; NOT in official feed
    ("tzdata", "2025.3"),           # zoneinfo data; OpenWrt lacks /usr/share/zoneinfo
]

# Packages whose musllinux wheel list is also dumped (filename/sha256/size),
# used to pick prebuilt wheels per {python-version, arch} in the Makefile.
WHEEL_PACKAGES = {"pydantic-core", "jiter"}

UA = {"User-Agent": "hermes-openwrt-feed/1.0 (package metadata fetch)"}


def fetch_json(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def main():
    out = {}
    for name, pin in PACKAGES:
        data = fetch_json(f"https://pypi.org/pypi/{name}/json")
        version = pin if pin else data["info"]["version"]
        release = data["releases"].get(version)
        if not release:
            sys.stderr.write(f"WARN: {name}: pin {version} not on PyPI\n")
            version = data["info"]["version"]
            release = data["releases"].get(version)
        sdist = next((u for u in release if u["packagetype"] == "sdist"), None)
        lic = data["info"].get("license_expression") or data["info"].get("license")
        rec = {
            "version": version,
            "sha256": sdist["digests"]["sha256"] if sdist else None,
            "url": sdist["url"] if sdist else None,
            "license": lic if lic else "UNKNOWN",
            "requires_dist": data["info"].get("requires_dist") or [],
        }
        if name in WHEEL_PACKAGES:
            rec["wheels_musllinux"] = [
                {
                    "filename": u["filename"],
                    "url": u["url"],
                    "sha256": u["digests"]["sha256"],
                    "size": u["size"],
                }
                for u in release
                if u["packagetype"] == "bdist_wheel"
                and "musllinux" in u["filename"]
                and "pp3" not in u["filename"]
                and "cp314" not in u["filename"]
            ]
        out[name] = rec
        dep_hint = "; ".join(r for r in rec["requires_dist"]
                             if ";" not in r and "<" not in r) or "-"
        sys.stderr.write(f"{name}=={rec['version']}  sha256={rec['sha256']}\n")
        sys.stderr.write(f"    deps: {dep_hint}\n")
    print(json.dumps(out, indent=1, sort_keys=True))


if __name__ == "__main__":
    main()
