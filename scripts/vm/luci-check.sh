#!/bin/sh
#
# Exercise an installed luci-app-hermes-agent the way a browser does:
#
#     scripts/vm/luci-check.sh [base-url] [root-password]
#
# Defaults: http://127.0.0.1:8080 and the password scripts/vm/run.sh set.
#
# Every other layer of verification in this repository calls ubus directly as
# root. That skips three things a real user cannot skip: uhttpd, the LuCI session
# and the rpcd ACL. So this script logs in, keeps the session cookie, and drives
# the app through /ubus/ exactly as the pages do -- which is how the .env bug in
# docs/PORTING.md §7 (4) was finally caught: settings_set answered {"ok":true}
# while writing the four bytes "null" over the user's API keys.
#
# Exit status is the number of failed checks.

set -u

base=${1:-http://127.0.0.1:8080}
pass=${2:-${VM_PASSWORD:-hermes-vm}}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/luci-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

pass_n=0
fail_n=0
ok()  { pass_n=$((pass_n + 1)); echo "  ok    $*"; }
bad() { fail_n=$((fail_n + 1)); echo "  FAIL  $*"; }
step() { echo; echo "-- $*"; }
cut1() { tr -s '\n\t ' ' ' | cut -c1-"${1:-160}"; }

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }

step "session"
# LuCI answers the login POST with a 302 and a sysauth_<proto> cookie; that
# cookie's value is also the ubus session id the JSON-RPC calls must carry.
curl -s -o /dev/null -c "$tmp/cookies" -X POST \
	--data-urlencode "luci_username=root" \
	--data-urlencode "luci_password=$pass" \
	"$base/cgi-bin/luci/" || { bad "cannot reach $base"; exit 1; }

sid=$(awk '/sysauth/ { print $7 }' "$tmp/cookies" 2>/dev/null)

if [ -n "$sid" ]; then
	ok "logged in as root, session ${sid}"
else
	bad "login failed -- wrong password, or uhttpd is not serving $base"
	exit 1
fi

step "view assets"
# Served by uhttpd out of /www, not read off the disk by this script: a view that
# the package failed to install is a 404 here even though the menu entry exists.
for v in overview chat settings; do
	code=$(curl -s -o "$tmp/view.js" -w '%{http_code}' \
		"$base/luci-static/resources/view/hermes-agent/$v.js")

	if [ "$code" = 200 ] && grep -q 'return view.extend' "$tmp/view.js"; then
		ok "$v.js is a LuCI view, $(wc -c < "$tmp/view.js" | tr -d ' ') bytes"
	else
		bad "$v.js -> HTTP $code"
	fi
done

step "page shells"
# The dispatcher resolving these proves the menu.d entries parse and point at
# views that exist -- check-sources.sh asserts the same thing statically.
for p in '' /chat /settings; do
	code=$(curl -s -b "$tmp/cookies" -o "$tmp/page" -w '%{http_code}' \
		"$base/cgi-bin/luci/admin/services/hermes-agent$p")

	[ "$code" = 200 ] \
		&& ok "GET admin/services/hermes-agent$p -> 200" \
		|| bad "GET admin/services/hermes-agent$p -> $code"
done

code=$(curl -s -b "$tmp/cookies" -o "$tmp/menu" -w '%{http_code}' "$base/cgi-bin/luci/admin/menu")
if [ "$code" = 200 ] && grep -q 'hermes-agent/overview' "$tmp/menu"; then
	ok "the sidebar menu carries our three entries"
else
	bad "admin/menu -> HTTP $code, no hermes-agent entries"
fi

# ubus over the session, the way the views do it. $1 object, $2 method, $3 params
rpc() {
	printf '[{"jsonrpc":"2.0","id":1,"method":"call","params":["%s","%s","%s",%s]}]' \
		"$sid" "$1" "$2" "$3" > "$tmp/req.json"
	curl -s -b "$tmp/cookies" -H 'Content-Type: application/json' \
		--data @"$tmp/req.json" "$base/ubus/"
}

step "ubus through the ACL"
for m in status settings_get logs; do
	out=$(rpc luci.hermes-agent "$m" '{}')

	case $out in
		*'"result":[0,'*) ok "$m -> $(printf '%s' "$out" | cut1 110)" ;;
		*) bad "$m -> $(printf '%s' "$out" | cut1)" ;;
	esac
done

# ubus status 6 is UBUS_STATUS_PERMISSION_DENIED. file.exec would run any command
# as root; the ACL of this app must never make it reachable from a LuCI session.
out=$(rpc file exec '{"command":"id"}')
case $out in
	*'"result":[6'*|*'"error"'*) ok "file.exec denied: $(printf '%s' "$out" | cut1 100)" ;;
	*) bad "file.exec was NOT denied: $(printf '%s' "$out" | cut1)" ;;
esac

step "settings_set really writes"
# The regression test for the bug this whole layer exists to catch. Two keys in
# one call on purpose: the bug was in serializing the whole file, not in any one
# assignment. The value is read back through settings_get rather than off the
# disk, because that is all a browser can see -- and it is enough: env_present
# flips only for a key the plugin can parse out of the file again.
#
# DEEPSEEK and GEMINI, not OPENAI: nothing in this VM is configured to use them,
# so setting and then clearing them cannot disturb a gateway that is already
# running against whatever provider .env names.
#
# OPENAI_API_KEY is the untouched bystander -- whatever its state is before the
# edits, it has to be the same after them. The bug replaced the entire file, so
# "our own key is there" alone would not have caught it.
was=$(rpc luci.hermes-agent settings_get '{}' | tr -d ' \t\n')
case $was in
	*'"OPENAI_API_KEY":true'*) bystander='"OPENAI_API_KEY":true' ;;
	*) bystander='"OPENAI_API_KEY":false' ;;
esac
echo "  (bystander: $bystander)"

out=$(rpc luci.hermes-agent settings_set \
	'{"env_set":{"DEEPSEEK_API_KEY":"sk-luci-check-0000","GEMINI_API_KEY":"sk-luci-check-1111"}}')
case $out in
	*'"ok":true'*) ok "settings_set reported success" ;;
	*) bad "settings_set -> $(printf '%s' "$out" | cut1 200)" ;;
esac

out=$(rpc luci.hermes-agent settings_get '{}')
flat=$(printf '%s' "$out" | tr -d ' \t\n')
case $flat in
	*'"DEEPSEEK_API_KEY":true'*'"GEMINI_API_KEY":true'*|*'"GEMINI_API_KEY":true'*'"DEEPSEEK_API_KEY":true'*)
		ok "both keys survived the round trip (env_present is true)" ;;
	*) bad "the keys did not land: $(printf '%s' "$out" | cut1 200)" ;;
esac

case $out in
	*sk-luci-check-*) bad "settings_get echoed the key material back to the browser" ;;
	*) ok "settings_get never returns key material" ;;
esac

case $flat in
	*"$bystander"*) ok "the rest of the file came through untouched ($bystander)" ;;
	*) bad "the rewrite changed OPENAI_API_KEY, which it was not asked to touch" ;;
esac

out=$(rpc luci.hermes-agent settings_set '{"env_clear":["DEEPSEEK_API_KEY","GEMINI_API_KEY"]}')
case $out in
	*'"ok":true'*) ok "env_clear accepted" ;;
	*) bad "env_clear -> $(printf '%s' "$out" | cut1 200)" ;;
esac

out=$(rpc luci.hermes-agent settings_get '{}')
flat=$(printf '%s' "$out" | tr -d ' \t\n')
case $flat in
	*'"DEEPSEEK_API_KEY":false'*) ok "the key is gone again" ;;
	*) bad "the key is still present after env_clear" ;;
esac

case $flat in
	*"$bystander"*) ok "and the bystander survived the clear too" ;;
	*) bad "env_clear changed OPENAI_API_KEY, which it was not asked to touch" ;;
esac

# Two guards on the way in. A newline would smuggle a second assignment into the
# file; a key outside the whitelist would let the page edit anything.
out=$(rpc luci.hermes-agent settings_set '{"env_set":{"NOUS_API_KEY":"a\nB=2"}}')
case $out in
	*newline*) ok "a value containing a newline is refused" ;;
	*) bad "newline injection was NOT refused: $(printf '%s' "$out" | cut1)" ;;
esac

out=$(rpc luci.hermes-agent settings_set '{"env_set":{"PATH":"/tmp"}}')
case $out in
	*'not editable'*) ok "a key outside the whitelist is refused" ;;
	*) bad "PATH was NOT refused: $(printf '%s' "$out" | cut1)" ;;
esac

step "chat, browser path"
out=$(rpc luci.hermes-agent chat_poll '{"tail":true}')
case $out in
	*'"connected":true'*) ok "chat_poll: the bridge is connected to the gateway" ;;
	*) bad "chat_poll -> $(printf '%s' "$out" | cut1 200)" ;;
esac

out=$(rpc luci.hermes-agent chat_send '{"id":"luci-check-1","method":"model.options","params":{}}')
case $out in
	*'"ok":true'*) ok "chat_send queued a request" ;;
	*) bad "chat_send -> $(printf '%s' "$out" | cut1 200)" ;;
esac

# A reply carrying our id means ubus -> file IPC -> hermes-chatd -> websocket ->
# gateway and all the way back completed. A gateway error reply is still a pass:
# what is under test is the transport, not the model.
k=0
while [ "$k" -lt 30 ]; do
	rpc luci.hermes-agent chat_poll '{"gen":0,"offset":0,"tail":false}' \
		| grep -q 'luci-check-1' && break
	k=$((k + 1))
	sleep 1
done
rpc luci.hermes-agent chat_poll '{"gen":0,"offset":0,"tail":false}' | grep -q 'luci-check-1' \
	&& ok "the gateway replied to luci-check-1 after ${k}s" \
	|| bad "no reply to luci-check-1 within ${k}s"

# Two allowlists guard the JSON-RPC socket; the plugin is the first of them.
out=$(rpc luci.hermes-agent chat_send '{"id":"luci-check-2","method":"shell.exec","params":{}}')
case $out in
	*'not permitted'*) ok "shell.exec refused by the plugin allowlist" ;;
	*) bad "shell.exec was NOT refused: $(printf '%s' "$out" | cut1)" ;;
esac

step "logout"
curl -s -b "$tmp/cookies" -o /dev/null "$base/cgi-bin/luci/admin/logout"
out=$(rpc luci.hermes-agent status '{}')
case $out in
	*'"error"'*|*'"result":[6'*) ok "the session is dead: $(printf '%s' "$out" | cut1 90)" ;;
	*) bad "the session still works after logout: $(printf '%s' "$out" | cut1)" ;;
esac

echo
echo "PASSED=$pass_n FAILURES=$fail_n"
exit "$fail_n"
