#!/bin/sh
#
# Static checks that need no OpenWrt SDK and no target: syntax-check every
# script and data file in the feed. Run from the repository root:
#
#     scripts/check-sources.sh
#
# This is the fast gate. A typo in a LuCI view or the ucode plugin is otherwise
# invisible until the page is opened on a real router, which is the slowest
# feedback loop in this project.
#
# LuCI views are not plain modules: they end in a top-level `return
# view.extend(...)`, which is a syntax error in a bare script. They are wrapped
# in a function expression before being handed to the parser, exactly as LuCI's
# own runtime does.

set -eu

cd "$(dirname "$0")/.."

fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
skip() { printf '  skip  %s\n' "$*"; }

echo "== shell"
for f in \
	packages/hermes-agent/files/hermes-agent.init \
	packages/hermes-agent/files/hermes-wrapper \
	packages/luci-app-hermes-agent/files/hermes-chatd.init \
	packages/luci-app-hermes-agent/files/hermes-log-cache \
	packages/luci-app-hermes-agent/root/etc/uci-defaults/99-hermes-agent-i18n \
	scripts/check-artifacts.sh \
	scripts/check-sources.sh \
	scripts/release-notes.sh \
	scripts/sdk-trim-config.sh \
	scripts/smoke/run.sh \
	scripts/smoke/inner.sh \
	scripts/vm/run.sh \
	scripts/vm/luci-check.sh
do
	[ -f "$f" ] || { bad "$f (missing)"; continue; }

	if sh -n "$f" 2>"$tmp/err"; then
		ok "$f"
	else
		bad "$f"
		sed 's/^/        /' "$tmp/err"
	fi
done

echo "== python"
for f in \
	packages/hermes-agent/files/shims/webbrowser.py \
	packages/luci-app-hermes-agent/files/hermes-chatd \
	scripts/sync-deps.py \
	scripts/ucode-globals.py
do
	[ -f "$f" ] || { bad "$f (missing)"; continue; }

	# Compile to a scratch directory: py_compile otherwise drops a __pycache__
	# next to the source, and files/ is copied verbatim into the package.
	if python3 -c 'import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
		"$f" "$tmp/$(basename "$f").pyc" 2>"$tmp/err"
	then
		ok "$f"
	else
		bad "$f"
		sed 's/^/        /' "$tmp/err"
	fi
done

echo "== json"
for f in \
	packages/luci-app-hermes-agent/root/usr/share/luci/menu.d/luci-app-hermes-agent.json \
	packages/luci-app-hermes-agent/root/usr/share/rpcd/acl.d/luci-app-hermes-agent.json \
	packages/hermes-agent/deps/deps.lock.json
do
	[ -f "$f" ] || { bad "$f (missing)"; continue; }

	if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>"$tmp/err"; then
		ok "$f"
	else
		bad "$f"
		sed 's/^/        /' "$tmp/err"
	fi
done

echo "== translations"
if command -v msgfmt >/dev/null 2>&1; then
	for f in packages/luci-app-hermes-agent/po/*/*.po; do
		if msgfmt --check --check-format -o /dev/null "$f" 2>"$tmp/err"; then
			ok "$f"
		else
			bad "$f"
			sed 's/^/        /' "$tmp/err"
		fi
	done
else
	skip "msgfmt not installed -- translations unchecked"
fi

# GitHub silently ignores a workflow it cannot parse: no run, no error, no hint
# in the Actions tab. And a shell typo inside a `run:` block surfaces an hour
# into an SDK build -- or, in the release workflow, in the last job after four
# green build legs. Both are cheap to catch here.
echo "== workflows"
if python3 -c 'import yaml' 2>/dev/null; then
	python3 - <<'PY' || fail=1
import glob, pathlib, re, subprocess, sys, yaml

ok = True


def say(good, msg):
    global ok
    print(('  ok    ' if good else '  FAIL  ') + msg)
    if not good:
        ok = False


files = sorted(glob.glob('.github/workflows/*.yml'))
if not files:
    say(False, 'no workflows found')

for wf in files:
    try:
        doc = yaml.safe_load(open(wf))
    except yaml.YAMLError as e:
        say(False, '%s (%s)' % (wf, str(e).splitlines()[0]))
        continue

    # YAML 1.1 reads a bare `on:` key as the boolean True, so accept either form
    # rather than depending on which spec version the loader follows.
    if not doc.get(True, doc.get('on')) or not doc.get('jobs'):
        say(False, '%s (no trigger or no jobs)' % wf)
        continue

    # Every `run:` block, parsed by the shell that will run it. GitHub
    # expressions are textual substitution at run time, so replacing them with
    # an inert word first is close to what bash actually ends up parsing.
    blocks = 0
    broken = 0
    for job, spec in doc['jobs'].items():
        for i, step in enumerate(spec.get('steps') or []):
            if not step.get('run'):
                continue
            blocks += 1
            src = re.sub(r'\$\{\{[^}]*\}\}', 'EXPR', step['run'])
            shell = 'sh' if step.get('shell') in ('sh', 'dash') else 'bash'
            p = subprocess.run([shell, '-n'], input=src, text=True,
                               capture_output=True)
            if p.returncode:
                broken += 1
                say(False, '%s / %s / %s\n        %s' %
                    (wf, job, step.get('name', 'step %d' % (i + 1)),
                     p.stderr.strip().replace('\n', '\n        ')))
    if not broken:
        plural = lambda n, w: '%d %s%s' % (n, w, '' if n == 1 else 's')
        say(True, '%s (%s, %s)' % (wf, plural(len(doc['jobs']), 'job'),
                                   plural(blocks, 'run block')))

refs = sorted({m for wf in files
               for m in re.findall(r'scripts/[A-Za-z0-9_./-]+\.(?:sh|py)',
                                   open(wf).read())})
missing = [r for r in refs if not pathlib.Path(r).is_file()]
for r in missing:
    say(False, 'workflows reference %s (missing)' % r)
if refs and not missing:
    say(True, '%d script references from workflows all resolve' % len(refs))

sys.exit(0 if ok else 1)
PY
else
	skip "PyYAML not installed -- workflows unchecked"
fi

# Every view named in menu.d must exist, and every ubus method the views call
# must be granted by acl.d. Both mismatches produce a blank page with a console
# error and nothing in the system log.
echo "== luci wiring"
python3 - <<'PY' || fail=1
import json, re, sys, pathlib

root = pathlib.Path('packages/luci-app-hermes-agent')
menu = json.loads((root / 'root/usr/share/luci/menu.d/luci-app-hermes-agent.json').read_text())
acl = json.loads((root / 'root/usr/share/rpcd/acl.d/luci-app-hermes-agent.json').read_text())
views = root / 'htdocs/luci-static/resources/view'
ok = True

def say(good, msg):
    global ok
    print(('  ok    ' if good else '  FAIL  ') + msg)
    if not good:
        ok = False

for path, entry in menu.items():
    action = entry.get('action', {})
    if action.get('type') != 'view':
        continue
    target = views / (action['path'] + '.js')
    say(target.is_file(), '%s -> %s' % (path, target.relative_to(root)))

granted = set()
for mode in ('read', 'write'):
    for obj, fns in acl.get(next(iter(acl)), {}).get(mode, {}).get('ubus', {}).items():
        granted.update('%s.%s' % (obj, fn) for fn in fns)

plugin = (root / 'root/usr/share/rpcd/ucode/luci.hermes-agent').read_text()
declared = set(re.findall(r'^\t(\w+): \{$', plugin, re.M))

for js in sorted(views.glob('hermes-agent/*.js')):
    src = js.read_text()
    for obj, method in re.findall(r"object:\s*'([\w.-]+)',\s*\n\s*method:\s*'([\w.-]+)'", src):
        full = '%s.%s' % (obj, method)
        note = '%s calls %s' % (js.name, full)
        if full not in granted:
            say(False, note + ' (not in acl.d)')
        elif obj == 'luci.hermes-agent' and method not in declared:
            say(False, note + ' (not implemented by the plugin)')
        else:
            say(True, note)

# The reverse direction: a method the plugin implements and the ACL grants but
# nothing calls is dead weight, not an error -- report it without failing.
called = set()
for js in views.glob('hermes-agent/*.js'):
    src = js.read_text()
    called.update('luci.hermes-agent.%s' % m for _, m in
                  re.findall(r"object:\s*'([\w.-]+)',\s*\n\s*method:\s*'([\w.-]+)'", src))
for m in sorted(declared):
    if 'luci.hermes-agent.%s' % m not in called:
        print('  info  plugin method %s is never called by a view' % m)

sys.exit(0 if ok else 1)
PY

echo "== javascript"
if command -v node >/dev/null 2>&1; then
	for f in packages/luci-app-hermes-agent/htdocs/luci-static/resources/view/hermes-agent/*.js; do
		# Legalise the top-level `return` the same way LuCI's loader does.
		{ printf '(function(){\n'; cat "$f"; printf '\n});\n'; } > "$tmp/wrap.js"

		if node --check "$tmp/wrap.js" 2>"$tmp/err"; then
			ok "$f"
		else
			bad "$f"
			sed 's/^/        /' "$tmp/err"
		fi
	done
else
	skip "node not installed -- LuCI views unchecked"
fi

echo "== ucode"
plugin=packages/luci-app-hermes-agent/root/usr/share/rpcd/ucode/luci.hermes-agent
if command -v ucode >/dev/null 2>&1; then
	# -c compiles to bytecode without executing: that is the real syntax check.
	#
	# NOT -T. That flag means "process the file as a template", i.e. everything
	# outside {% %} is literal text -- `ucode -T` echoes a file of pure garbage
	# and exits 0. This check used to use it and was therefore vacuous, which is
	# a good reminder that a check nobody has ever seen fail is not a check.
	if ucode -c -o /dev/null "$plugin" 2>"$tmp/err"; then
		ok "$plugin (ucode -c)"
	else
		bad "$plugin"
		sed 's/^/        /' "$tmp/err"
	fi

	# Compiling is not enough. ucode resolves globals at *runtime*, so a call to
	# a function that does not exist compiles cleanly and dies with "access to
	# undeclared variable" the first time that line executes -- for a method on
	# the chat path, that means a green build, a green package check, and a
	# broken button. `rand()` was exactly this: it is not a ucode builtin, it
	# lives in the optional ucode-mod-math package.
	#
	# scripts/ucode-globals.py explains the mechanism; the smoke test runs the
	# same probe against the *installed* plugin, which is where it matters most
	# because a target rootfs always has a ucode binary and a build host usually
	# does not.
	python3 scripts/ucode-globals.py "$plugin" > "$tmp/globals.uc"
	undeclared=$(ucode "$tmp/globals.uc" 2>&1 | tr '\n' ' ' | sed 's/ *$//')
	if [ -z "$undeclared" ]; then
		ok "$(grep -c '^try' "$tmp/globals.uc") global calls all resolve"
	else
		bad "undeclared globals called by the plugin: $undeclared"
	fi
elif command -v node >/dev/null 2>&1; then
	# Fallback: ucode's grammar is close enough to ES2020 that node catches
	# ordinary typos. The module syntax differs, so the import/export lines are
	# rewritten first. This is a smoke test, not a substitute for ucode -T.
	sed -e "s/^import .*from 'fs';/const { popen, readfile, writefile, access, stat, open, mkdir, rename, unlink } = {};/" \
	    -e "s/^import .*from 'ubus';/const { connect } = {};/" \
	    -e "s/^import .*from 'uci';/const { cursor } = {};/" \
	    "$plugin" | sed 's/^return {/export default {/' > "$tmp/plugin.mjs"

	if node --check "$tmp/plugin.mjs" 2>"$tmp/err"; then
		ok "$plugin (via node, approximate)"
	else
		bad "$plugin (via node, approximate)"
		sed 's/^/        /' "$tmp/err"
	fi
else
	skip "neither ucode nor node installed -- plugin unchecked"
fi

echo
if [ "$fail" -eq 0 ]; then
	echo "SOURCES OK"
else
	echo "SOURCE CHECKS FAILED"
fi

exit "$fail"
