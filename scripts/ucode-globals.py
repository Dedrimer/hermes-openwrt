#!/usr/bin/env python3
"""Emit a ucode program that probes every global a ucode script calls.

    python3 scripts/ucode-globals.py <script> > probe.uc
    ucode probe.uc          # prints one line per undeclared global; silence is a pass

Why this exists: ucode resolves globals at *runtime*. A call to a function that
does not exist compiles cleanly -- `ucode -c` is happy -- and throws
"Reference error: access to undeclared variable X" the first time that exact
line executes. Inside an rpcd method the ubus caller sees only "Unknown error",
with the real message going to rpcd's stderr. That is how `rand()` (not a ucode
builtin at all: it lives in the optional ucode-mod-math package) shipped through
a green build, a green package check and a green syntax check, and only failed
when someone pressed Send.

The generated probe reads each name under 'use strict', which is what makes an
undeclared read throw. Without strict mode ucode quietly evaluates an unknown
global to null and the probe would pass for everything, including typos.

Limitations, stated so nobody trusts this further than it goes: only call sites
of the form `name(` are probed -- a global read without a call, one reached
through an alias, or one written inside a `${...}` interpolation (template
literals are blanked whole, see strip_noise) is invisible here -- and the
probing interpreter must be the same generation as the target's. It answers
exactly one question: does every function this script calls by bare name exist?
"""

import re
import sys

KEYWORDS = {
    'if', 'for', 'while', 'switch', 'catch', 'try', 'else', 'do',
    'return', 'function', 'typeof', 'delete', 'in',
}


def strip_noise(src):
    """Remove comments and string literals.

    Without this, prose contributes phantom call sites: a comment reading
    "seek() is used to avoid ..." and a message reading "not running (start
    hermes-chatd)" both match the call regex. Template literals are blanked
    whole -- their ${} parts only interpolate variables in this codebase, they
    never call anything, so nothing is lost.
    """
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.S)
    src = re.sub(r'//[^\n]*', ' ', src)
    src = re.sub(r"'(?:\\.|[^'\\])*'", "''", src)
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    src = re.sub(r'`(?:\\.|[^`\\])*`', '``', src)
    return src


def called_globals(src):
    src = strip_noise(src)

    known = set(re.findall(r'\bfunction\s+(\w+)\s*\(', src))
    for m in re.finditer(r'import\s*\{([^}]*)\}\s*from', src):
        known.update(x.strip() for x in m.group(1).split(','))

    # The lookbehind drops method calls (obj.foo()): those are property lookups,
    # not global ones, and a missing method fails differently.
    calls = set(re.findall(r'(?<![.\w$])([A-Za-z_]\w*)\s*\(', src))

    return sorted(calls - known - KEYWORDS)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[0])

    with open(sys.argv[1], encoding='utf-8') as fh:
        names = called_globals(fh.read())

    out = ["'use strict';"]
    for name in names:
        out.append("try { type(%s); } catch (e) { print('%s\\n'); }" % (name, name))

    print('\n'.join(out))


if __name__ == '__main__':
    main()
