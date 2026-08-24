#!/bin/sh
#
# Runs inside the OpenWrt rootfs; scripts/smoke/run.sh sets up the sandbox and
# invokes this. Non-fatal throughout -- the point is the whole report, not the
# first failure -- and the exit status is the number of failed checks.
#
# Two invariants worth knowing before editing:
#
#   * `hermes` dispatches on $0 and passes everything through to the Hermes CLI,
#     where `-c` means "continue the session with this title". It is not a Python
#     interpreter. To exercise the private site-packages, call python3 directly
#     with the same environment hermes-wrapper exports (see py() below).
#   * the init scripts log through `logger`, and logd cannot run in this sandbox
#     (it wants /proc/kmsg and a setgid() that bwrap's single-uid namespace
#     refuses), so checks on their output stub `logger` via PATH instead of
#     reading logread.

set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

fail=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; fail=$((fail + 1)); }
step() { echo; echo "-- $*"; }

PREFIX=/usr/lib/hermes-agent
TOKEN=/var/run/hermes-agent.token
RUN_DIR=/var/run/hermes-chat
PORT=9119

mkdir -p /var/run /var/lock /var/state /var/log

# The subset of hermes-wrapper's environment that decides whether the bundled
# dependencies import: the private site-packages, the shims directory that fills
# OpenWrt's stdlib gaps, no user site, and the compat directory carrying the
# libc.musl-<arch>.so.1 soname the Alpine-built wheels ask for.
#
# Resolved on each call, not once at the top: the path does not exist until apk
# has installed the package, and an empty PYTHONPATH here fails every dependency
# check below for the wrong reason.
site() { ls -d "$PREFIX"/lib/python*/site-packages 2>/dev/null | head -n1; }
py() {
	PYTHONPATH="$(site):$PREFIX/shims" PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 \
		LD_LIBRARY_PATH="$PREFIX/compat" /usr/bin/python3 "$@"
}


step "environment"
echo "  $(. /etc/openwrt_release 2>/dev/null; echo "$DISTRIB_ID $DISTRIB_RELEASE $DISTRIB_ARCH")"
echo "  loader: $(ls /lib/ld-musl-* 2>/dev/null | tr '\n' ' ')"

step "apk install"
apk update >/tmp/apk-update.log 2>&1 && ok "apk update" || {
	bad "apk update"; tail -3 /tmp/apk-update.log | sed 's/^/        /'
}
if apk add --allow-untrusted /pkgs/*.apk >/tmp/apk.log 2>&1; then
	ok "apk add ($(ls /pkgs | tr '\n' ' '))"
	echo "  pulled: $(grep -cE '^\([0-9]+/[0-9]+\) Installing' /tmp/apk.log) packages"
else
	bad "apk add"; tail -20 /tmp/apk.log | sed 's/^/        /'
fi

step "files landed"
for f in /usr/bin/hermes /usr/bin/hermes-agent /usr/sbin/hermes-chatd \
	/etc/init.d/hermes-agent /etc/init.d/hermes-chatd \
	/etc/config/hermes-agent /srv/hermes/config.yaml /srv/hermes/.env \
	/usr/share/rpcd/ucode/luci.hermes-agent \
	/usr/share/luci/menu.d/luci-app-hermes-agent.json \
	/usr/share/rpcd/acl.d/luci-app-hermes-agent.json \
	/lib/upgrade/keep.d/hermes-agent
do
	[ -e "$f" ] && ok "$f" || bad "$f missing"
done
echo "  site-packages: $(site)"
echo "  .env    $(ls -l /srv/hermes/.env 2>/dev/null | awk '{print $1}')"
echo "  config  $(ls -l /srv/hermes/config.yaml 2>/dev/null | awk '{print $1}')"

step "musl soname compat symlink"
n=0
for l in "$PREFIX"/compat/*; do
	[ -L "$l" ] || continue
	n=$((n + 1))
	if [ -e "$l" ]; then
		ok "${l##*/} -> $(readlink "$l")"
	else
		bad "${l##*/} -> $(readlink "$l")  (DANGLING)"
	fi
done
[ "$n" -ge 1 ] || bad "compat dir empty"

step "hermes --version   (loader + PYTHONPATH + importlib.metadata)"
if out=$(hermes --version 2>&1); then
	ok "$(echo "$out" | tr '\n' ' ' | cut -c1-200)"
else
	bad "exit $?"; echo "$out" | tail -20 | sed 's/^/        /'
fi

step "hermes --help   (the full parser, i.e. every subcommand's imports)"
# --version short-circuits early, so it proves far less than it looks like it
# does. Building the parser imports portal_cli and auth, which is where a
# missing stdlib module (OpenWrt ships no webbrowser.py -- see files/shims)
# takes down every subcommand at once. Cheapest possible check for that class
# of failure.
if out=$(hermes --help 2>&1); then
	ok "parser builds; $(echo "$out" | grep -cE '^ ' ) usage lines"
else
	bad "hermes --help failed"; echo "$out" | tail -20 | sed 's/^/        /'
fi

step "stdlib gaps in OpenWrt's python3"
# Informational, but it is the list to consult when a subcommand dies on an
# import that "cannot possibly" be missing. msvcrt/winreg/nt/msvcrt are Windows
# modules Hermes only imports inside platform-guarded blocks.
py - <<'PY' 2>&1 | sed 's/^/  /'
import importlib.util, sys
missing = [n for n in sorted(sys.stdlib_module_names)
           if not n.startswith('_') and importlib.util.find_spec(n) is None]
print("missing: %s" % " ".join(missing))
print("webbrowser resolves to: %s" % (importlib.util.find_spec("webbrowser").origin,))
PY

step "native extensions import"
# The closure has exactly 13 non-pure wheels (deps.lock.json marks them
# pure:false); the rest is pure Python and cannot fail architecture-wise. Their
# distribution names are not their module names, and for several of them
# importing the top-level package never touches the compiled object -- hence the
# explicit submodules. One line per wheel so a failure names the culprit.
cat > /tmp/native.py <<'PY'
import importlib, sys

mods = [
	("cffi",             "_cffi_backend"),
	("cryptography",     "cryptography.hazmat.bindings._rust"),
	("httptools",        "httptools.parser.parser"),
	("jiter",            "jiter"),
	("markupsafe",       "markupsafe._speedups"),
	("nemo-relay",       "nemo_relay"),
	("pillow",           "PIL._imaging"),
	("psutil",           "psutil._psutil_linux"),
	("pydantic-core",    "pydantic_core._pydantic_core"),
	("pyyaml",           "yaml._yaml"),
	("ruamel-yaml-clib", "_ruamel_yaml"),
	("uvloop",           "uvloop.loop"),
	("watchfiles",       "watchfiles._rust_notify"),
	# Not a wheel of ours, but the point of the whole exercise.
	("hermes-agent",     "hermes_cli"),
]

bad = 0
for dist, mod in mods:
	try:
		m = importlib.import_module(mod)
	except Exception as e:
		print("FAIL %-17s %s: %s" % (dist, mod, e))
		bad += 1
	else:
		print("ok   %-17s %s" % (dist, getattr(m, "__file__", "<builtin>")))

sys.exit(1 if bad else 0)
PY
if py /tmp/native.py >/tmp/native.log 2>&1; then
	ok "$(grep -c '^ok' /tmp/native.log) native modules import"
else
	bad "native extension imports"
	grep -v '^ok' /tmp/native.log | sed 's/^/        /'
fi

step "dist-info metadata"
d=$(ls -d "$(site)"/*.dist-info 2>/dev/null | wc -l)
[ "$d" -gt 10 ] && ok "$d .dist-info dirs" || bad "only $d .dist-info dirs in $(site)"
# The reason .dist-info matters: upstream calls importlib.metadata.version() in
# several places and a source-tree copy would raise PackageNotFoundError there.
out=$(py -c 'from importlib.metadata import version; print(version("hermes-agent"))' 2>&1) \
	&& ok "importlib.metadata.version(hermes-agent) = $out" \
	|| { bad "metadata lookup"; echo "$out" | tail -6 | sed 's/^/        /'; }

step "ucode compiles the rpcd plugin"
# -c, not -T: -T means "treat the input as a template", which prints any file at
# all and exits 0. The target's own ucode is used here, so this also catches a
# syntax the build host's newer ucode would have accepted.
if command -v ucode >/dev/null 2>&1; then
	ucode -c -o /dev/null /usr/share/rpcd/ucode/luci.hermes-agent 2>/tmp/ucode.err \
		&& ok "ucode -c" \
		|| { bad "ucode -c"; head -10 /tmp/ucode.err | sed 's/^/        /'; }

	# Compiling proves nothing about whether the functions it calls exist: ucode
	# looks globals up at runtime, so a name that is not a builtin raises
	# "access to undeclared variable" only when its line runs. See
	# scripts/ucode-globals.py -- this is the check that would have caught
	# rand() before a human did.
	if /usr/bin/python3 /ucode-globals.py /usr/share/rpcd/ucode/luci.hermes-agent \
		> /tmp/globals.uc 2>/tmp/globals.err
	then
		undeclared=$(ucode /tmp/globals.uc 2>&1 | tr '\n' ' ' | sed 's/ *$//')
		if [ -z "$undeclared" ]; then
			ok "$(grep -c '^try' /tmp/globals.uc) global calls all resolve"
		else
			bad "plugin calls undeclared globals: $undeclared"
		fi
	else
		bad "could not build the globals probe"
		sed 's/^/        /' /tmp/globals.err
	fi
else
	bad "no ucode binary in rootfs"
fi

step "ubus / rpcd"
ubusd >/tmp/ubusd.log 2>&1 &
sleep 1
# No logd here, deliberately. It cannot run in this sandbox: it opens
# /proc/kmsg (denied) and drops privileges with setgid(), which returns EINVAL
# inside bwrap's single-uid user namespace -- and bwrap cannot map more ids
# without a setuid newuidmap. So there is no `log` ubus object, logread stays
# empty, and anything that inspects logger output stubs logger instead (see the
# non-loopback guard below).
rpcd >/tmp/rpcd.log 2>&1 &
sleep 3
if ubus list 2>/dev/null | grep -qx 'luci.hermes-agent'; then
	ok "ubus object luci.hermes-agent registered"
	echo "  methods: $(ubus -v list luci.hermes-agent 2>/dev/null | grep -oE '"[a-z_]+":\{' | tr -d '":{' | tr '\n' ' ')"
	for m in status settings_get logs; do
		if out=$(ubus call luci.hermes-agent "$m" 2>&1); then
			ok "call $m -> $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-150)"
		else
			bad "call $m -> $out"
		fi
	done
	# `logs` shells out to logread, which has nothing to read without logd. The
	# call is checked for its plumbing; an empty result here is expected.
	echo "  note: logs returns no lines because logd cannot run in the sandbox"
else
	bad "luci.hermes-agent not registered"
	ubus list 2>&1 | head -8 | sed 's/^/        /'
	tail -5 /tmp/rpcd.log | sed 's/^/        /'
fi

# The Settings page writes API keys through this method, so "it returned ok" is
# not enough: the file has to actually say what the user typed. That distinction
# is not academic -- `join(array, sep)` (ucode wants the separator first) returns
# null instead of throwing, so the whole file was once replaced with the four
# bytes "null" while every call still answered {"ok":true}. Only reading the file
# back catches that, which is exactly what this step does.
step "settings_set really edits .env"
if ubus list 2>/dev/null | grep -qx 'luci.hermes-agent'; then
	# A line outside the whitelist must survive every edit, untouched.
	printf 'CUSTOM_KEEP_ME=1\n' >> /srv/hermes/.env

	out=$(ubus call luci.hermes-agent settings_set \
		'{"env_set":{"OPENAI_API_KEY":"sk-smoke-set-1","OPENAI_BASE_URL":"http://127.0.0.1:1/v1"}}' 2>&1)
	if echo "$out" | grep -q '"ok": *true'; then
		ok "settings_set reported success"
	else
		bad "settings_set: $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-200)"
		tail -10 /tmp/rpcd.log | sed 's/^/        /'
	fi

	if grep -qx 'OPENAI_API_KEY=sk-smoke-set-1' /srv/hermes/.env 2>/dev/null; then
		ok ".env contains the value that was written"
	else
		bad ".env does NOT contain the written value"
		sed 's/^/        /' /srv/hermes/.env
	fi

	grep -qx 'CUSTOM_KEEP_ME=1' /srv/hermes/.env 2>/dev/null \
		&& ok "a line outside the whitelist survived the rewrite" \
		|| bad "the rewrite dropped CUSTOM_KEEP_ME=1"

	mode=$(ls -l /srv/hermes/.env | awk '{print $1}')
	case "$mode" in
		-rw-------) ok ".env is still $mode after the rewrite" ;;
		*) bad ".env mode is $mode, expected -rw-------" ;;
	esac

	# Write-only secrets: the presence flag may come back, the value may not.
	out=$(ubus call luci.hermes-agent settings_get 2>&1)
	echo "$out" | tr -d ' \t\n' | grep -q '"OPENAI_API_KEY":true' \
		&& ok "settings_get reports the key as present" \
		|| bad "settings_get does not see the key: $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-200)"
	case "$out" in
		*sk-smoke-set-1*) bad "settings_get echoed the key material back" ;;
		*) ok "settings_get never returns key material" ;;
	esac

	# A newline in a value would smuggle a second assignment into the file.
	out=$(ubus call luci.hermes-agent settings_set '{"env_set":{"NOUS_API_KEY":"a
B=2"}}' 2>&1)
	case "$out" in
		*newline*) ok "a value containing a newline is refused" ;;
		*) bad "newline injection was NOT refused: $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-160)" ;;
	esac

	out=$(ubus call luci.hermes-agent settings_set '{"env_set":{"PATH":"/tmp"}}' 2>&1)
	case "$out" in
		*'not editable'*) ok "a key outside the whitelist is refused" ;;
		*) bad "PATH was NOT refused: $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-160)" ;;
	esac

	# Clearing must remove the key and keep everything else. The gateway step
	# further down re-adds a key of its own, so leaving it cleared is fine.
	out=$(ubus call luci.hermes-agent settings_set '{"env_clear":["OPENAI_API_KEY"]}' 2>&1)
	if echo "$out" | grep -q '"ok": *true' && ! grep -q '^OPENAI_API_KEY=' /srv/hermes/.env; then
		ok "env_clear removed the key"
	else
		bad "env_clear: $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-160)"
		sed 's/^/        /' /srv/hermes/.env
	fi
	grep -qx 'CUSTOM_KEEP_ME=1' /srv/hermes/.env 2>/dev/null \
		&& ok "the foreign line survived the clear too" \
		|| bad "env_clear dropped CUSTOM_KEEP_ME=1"
else
	bad "settings_set not tested: the ubus object is missing"
fi

step "init scripts parse"
for s in hermes-agent hermes-chatd; do
	sh -n /etc/init.d/$s 2>/tmp/e && ok "sh -n /etc/init.d/$s" || {
		bad "/etc/init.d/$s"; sed 's/^/        /' /tmp/e
	}
done

step "the gateway refuses a non-loopback bind"
# enabled=1 matters: with serve disabled the script returns before the guard.
# The guard reports through `logger`, and logd cannot run here (see above), so
# logger is stubbed for this one step -- /lib/functions.sh calls it by name, so
# a directory in front of PATH is the whole trick. procd is not running either,
# and procd_close_service will say so on stderr; the guard fires long before
# that point.
mkdir -p /tmp/bin
cat > /tmp/bin/logger <<'EOF'
#!/bin/sh
echo "$*" >> /tmp/logger.out
EOF
chmod +x /tmp/bin/logger
: > /tmp/logger.out

uci set hermes-agent.serve.enabled=1
uci set hermes-agent.serve.host=192.168.1.1
uci commit hermes-agent
PATH=/tmp/bin:$PATH /etc/init.d/hermes-agent start >/tmp/guard.log 2>&1
if grep -q 'refusing to bind 192.168.1.1' /tmp/logger.out; then
	ok "$(grep 'refusing to bind' /tmp/logger.out | tail -1 | cut -c1-160)"
else
	bad "non-loopback host was NOT refused"
	sed 's/^/        /' /tmp/logger.out
	tail -5 /tmp/guard.log | sed 's/^/        /'
fi
uci set hermes-agent.serve.host=127.0.0.1
uci commit hermes-agent

step "gateway <-> bridge websocket handshake"
# A syntactically plausible key so provider validation does not abort startup.
# Nothing here submits a prompt, so it is never used against a real API.
grep -q '^OPENAI_API_KEY=' /srv/hermes/.env 2>/dev/null || {
	printf 'OPENAI_API_KEY=sk-smoke-0000000000000000000000000000000000000000\n' >> /srv/hermes/.env
	chmod 600 /srv/hermes/.env
}

# Same as init's mint_token: /api/ws rejects an empty token even on loopback,
# and hermes-wrapper exports this file as HERMES_DASHBOARD_SESSION_TOKEN.
[ -s "$TOKEN" ] || (umask 077; dd if=/dev/urandom bs=32 count=1 2>/dev/null | md5sum | cut -d' ' -f1 > "$TOKEN")
chmod 600 "$TOKEN"
mkdir -p /srv/hermes/workspace "$RUN_DIR"
chmod 700 "$RUN_DIR"

cat > /tmp/portup.py <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(1)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except Exception:
    sys.exit(1)
sys.exit(0)
PY

( cd /srv/hermes/workspace && hermes serve --host 127.0.0.1 --port "$PORT" --skip-build ) \
	>/tmp/serve.log 2>&1 &
serve_pid=$!

i=0
while [ "$i" -lt 120 ]; do
	/usr/bin/python3 /tmp/portup.py "$PORT" 2>/dev/null && break
	kill -0 "$serve_pid" 2>/dev/null || break
	i=$((i + 1)); sleep 1
done

if /usr/bin/python3 /tmp/portup.py "$PORT" 2>/dev/null; then
	ok "hermes serve listening on 127.0.0.1:$PORT after ${i}s"

	hermes-chatd --host 127.0.0.1 --port "$PORT" --token-file "$TOKEN" --run-dir "$RUN_DIR" \
		>/tmp/chatd.log 2>&1 &
	chatd_pid=$!

	j=0
	while [ "$j" -lt 60 ]; do
		grep -q '"connected": *true' "$RUN_DIR/state" 2>/dev/null && break
		kill -0 "$chatd_pid" 2>/dev/null || break
		j=$((j + 1)); sleep 1
	done

	if grep -q '"connected": *true' "$RUN_DIR/state" 2>/dev/null; then
		ok "bridge connected to /api/ws after ${j}s: $(cat "$RUN_DIR/state")"
		echo "  perms: $(ls -ld "$RUN_DIR" | awk '{print $1}') $(ls -l "$RUN_DIR/state" | awk '{print $1}')"

		# Through the whole chain the browser uses: ubus -> ucode plugin ->
		# file IPC -> chatd -> websocket -> gateway, and back.
		#
		# rpcd's stderr is dumped on any failure here: an exception inside a
		# ucode method surfaces at the ubus caller as a bare "Unknown error",
		# while rpcd prints the actual message, file and line. Finding that out
		# the slow way is what the `rand()` bug cost.
		out=$(ubus call luci.hermes-agent chat_poll '{"tail":true}' 2>&1)
		if echo "$out" | grep -q '"connected": *true'; then
			ok "chat_poll reports connected"
		else
			bad "chat_poll: $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-200)"
			tail -20 /tmp/rpcd.log | sed 's/^/        /'
		fi

		out=$(ubus call luci.hermes-agent chat_send '{"id":"smoke-1","method":"model.options","params":{}}' 2>&1)
		if echo "$out" | grep -q '"ok": *true'; then
			ok "chat_send queued model.options"
		else
			bad "chat_send: $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-200)"
			tail -20 /tmp/rpcd.log | sed 's/^/        /'
		fi

		# A reply carrying our id means the request crossed every hop. Whether
		# the gateway answers with a result or an error is irrelevant here.
		k=0
		while [ "$k" -lt 30 ]; do
			ubus call luci.hermes-agent chat_poll '{"gen":0,"offset":0,"tail":false}' 2>/dev/null \
				| grep -q 'smoke-1' && break
			k=$((k + 1)); sleep 1
		done
		if ubus call luci.hermes-agent chat_poll '{"gen":0,"offset":0,"tail":false}' 2>/dev/null | grep -q 'smoke-1'; then
			ok "round trip: gateway replied to smoke-1 after ${k}s"
		else
			bad "no reply to smoke-1 within ${k}s"
			tail -5 /tmp/chatd.log | sed 's/^/        /'
			# The event log is the transcript of everything the gateway said;
			# a rejection or an error reply shows up here even when nothing
			# carries our id.
			tail -c 400 "$RUN_DIR/events" 2>/dev/null | sed 's/^/        /'
		fi

		# The bridge is the authoritative allowlist; the plugin is the first of
		# two. Neither may forward a shell method.
		out=$(ubus call luci.hermes-agent chat_send '{"id":"smoke-2","method":"shell.exec","params":{}}' 2>&1)
		case "$out" in
			*'not permitted'*) ok "shell.exec refused by the plugin allowlist" ;;
			*) bad "shell.exec was NOT refused: $(echo "$out" | tr -s '\n\t ' ' ' | cut -c1-160)" ;;
		esac
	else
		bad "bridge never connected"
		tail -15 /tmp/chatd.log | sed 's/^/        /'
	fi

	kill "$chatd_pid" 2>/dev/null
else
	bad "hermes serve did not listen within ${i}s"
	tail -25 /tmp/serve.log | sed 's/^/        /'
fi

kill "$serve_pid" 2>/dev/null

step "the bridge refuses a non-loopback gateway"
out=$(hermes-chatd --host 10.0.0.1 --port "$PORT" --token-file "$TOKEN" --run-dir /tmp/x 2>&1; echo "rc=$?")
case "$out" in
	*'refusing to bridge'*rc=2*) ok "hermes-chatd --host 10.0.0.1 -> $(echo "$out" | tr '\n' ' ')" ;;
	*) bad "non-loopback gateway was NOT refused: $(echo "$out" | tr '\n' ' ' | cut -c1-160)" ;;
esac

echo
echo "FAILURES=$fail"
exit "$fail"
