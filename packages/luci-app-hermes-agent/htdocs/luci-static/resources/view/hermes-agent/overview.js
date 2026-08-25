'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require dom';

// Overview: what state is Hermes in, and the buttons to change it.
//
// Everything on this page comes from one ubus call (luci.hermes-agent.status),
// polled every 5s. That is deliberate -- a router serving this page may be
// doing real work, and one round trip per refresh keeps it cheap.
//
// The log tail lives here rather than on its own menu page: when the service
// misbehaves, the state and the reason for it are one thing to look at, and a
// third menu entry for twenty lines of logread is not worth the click. It polls
// on a slower cycle than the status block since logread is the more expensive
// of the two.

const callStatus = rpc.declare({
	object: 'luci.hermes-agent',
	method: 'status',
	expect: {}
});

const callAction = rpc.declare({
	object: 'luci.hermes-agent',
	method: 'action',
	params: [ 'op' ],
	expect: {}
});

const callLogs = rpc.declare({
	object: 'luci.hermes-agent',
	method: 'logs',
	params: [ 'lines', 'pattern', 'refresh' ],
	expect: {}
});

const LOG_LINES = 80;
const LOG_INTERVAL = 300;

// Render a label/value pair as a table row. LuCI's own status pages use this
// two-column table idiom, so it inherits the theme's spacing and dark mode.
function row(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '33%' }, [ label ]),
		E('td', { 'class': 'td left' }, value)
	]);
}

function pill(ok, text) {
	return E('span', {
		'style': 'display:inline-block;padding:0 .5em;border-radius:.8em;color:#fff;' +
			'font-size:90%;background:' + (ok ? '#4caf50' : '#9e9e9e')
	}, [ text ]);
}

function fmtKB(kb) {
	const n = parseInt(kb, 10);

	if (isNaN(n))
		return '?';

	if (n >= 1048576)
		return '%.1f GiB'.format(n / 1048576);

	if (n >= 1024)
		return '%.1f MiB'.format(n / 1024);

	return '%d KiB'.format(n);
}

return view.extend({
	// The view is read-only; the buttons below do their own confirmed writes.
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	logNode: null,

	load() {
		return L.resolveDefault(callStatus(), {});
	},

	// Run an init.d operation, then refresh immediately rather than waiting
	// for the next poll tick, so the button feels connected to the result.
	handleAction(op, ev) {
		return callAction(op).then(res => {
			if (res && res.code != 0) {
				ui.addNotification(null, [
					E('p', {}, [ _('Operation %s failed (exit code %d).').format(op, res.code) ]),
					res.output ? E('pre', { 'style': 'white-space:pre-wrap' }, [ res.output ]) : ''
				], 'warning');
			}

			return this.refresh();
		}).then(() => this.refreshLogs(true)).catch(err => {
			ui.addNotification(null, E('p', {}, [
				_('Operation %s failed: %s').format(op, err.message)
			]), 'error');
		});
	},

	refresh() {
		return L.resolveDefault(callStatus(), {}).then(st => {
			const node = document.getElementById('hermes-status');

			if (node)
				dom.content(node, this.renderStatus(st));
		});
	},

	// logread matches on the syslog tag, which covers both the init script's own
	// messages and procd's capture of the gateway's stdout/stderr.
	refreshLogs(force) {
		if (force && this.logRefreshButton)
			this.logRefreshButton.disabled = true;

		const request = callLogs(LOG_LINES, 'hermes', force === true);

		return (force ? request : L.resolveDefault(request, null)).then(res => {
			if (force && (!res || res.code != 0))
				throw new Error(_('Unable to update the log cache.'));

			if (!this.logNode)
				return;

			const lines = (res && res.lines) ? res.lines : [];
			const atBottom = (this.logNode.scrollHeight - this.logNode.scrollTop -
				this.logNode.clientHeight) < 40;

			dom.content(this.logNode, lines.length
				? lines.join('\n')
				: E('em', {}, [ _('No log entries yet.') ]));

			if (atBottom)
				this.logNode.scrollTop = this.logNode.scrollHeight;
		}).finally(() => {
			if (force && this.logRefreshButton)
				this.logRefreshButton.disabled = false;
		});
	},

	handleRefreshLogs(ev) {
		return this.refreshLogs(true).catch(err => {
			ui.addNotification(null, E('p', {}, [
				_('Failed to refresh the log: %s').format(err.message)
			]), 'error');
		});
	},

	renderStatus(st) {
		const serve = st.serve ?? {};
		const bridge = st.bridge ?? {};
		const running = (st.running == true);
		const enabled = (serve.enabled == '1');

		// A common first-run failure is a running service with no API key, which
		// otherwise only shows up as a confusing error inside the chat page.
		const warnings = [];

		if (!st.env_present || !st.config_present) {
			warnings.push(_('Hermes has not been initialised yet — %s is missing. Reinstall the hermes-agent package to recreate it.')
				.format(!st.config_present ? 'config.yaml' : '.env'));
		}

		if (serve.host != '127.0.0.1' && serve.host != 'localhost' && serve.host != '::1') {
			warnings.push(_('The gateway is bound to %s rather than loopback. Hermes then requires an authentication provider, and the port becomes reachable from your network — the LuCI chat page does not need this.')
				.format(serve.host));
		}

		if (running && bridge.connected !== true) {
			warnings.push(bridge.running === true
				? _('The chat bridge is running but not connected to the gateway%s. The Chat page will not work until it is.')
					.format(bridge.error ? ' (%s)'.format(bridge.error) : '')
				: _('The chat bridge (hermes-chatd) is not running, so the Chat page will not work.'));
		}

		return [
			warnings.length ? E('div', { 'class': 'alert-message warning' },
				warnings.map(w => E('p', { 'style': 'margin:.2em 0' }, [ w ]))) : '',

			E('div', { 'class': 'table' }, [
				row(_('Status'), [
					pill(running, running ? _('Running') : _('Stopped')),
					running && st.pid ? E('span', {}, [ ' ' + _('(PID %d)').format(st.pid) ]) : ''
				]),
				row(_('Start on boot'), [
					pill(enabled, enabled ? _('Enabled') : _('Disabled'))
				]),
				row(_('Chat bridge'), [
					pill(bridge.connected === true, bridge.connected === true
						? _('Connected')
						: (bridge.running === true ? _('Reconnecting') : _('Not running')))
				]),
				row(_('Version'), [ st.version || E('em', {}, [ _('unknown') ]) ]),
				row(_('Gateway address'), [
					E('code', {}, [ st.listen ?? '-' ])
				]),
				row(_('Data directory'), [ E('code', {}, [ st.home ?? '-' ]) ]),
				row(_('Workspace'), [ E('code', {}, [ serve.workdir ?? '-' ]) ]),
				row(_('Free space'), st.disk
					? [ _('%s free of %s (%s used)').format(
						fmtKB(st.disk.avail), fmtKB(st.disk.size), st.disk.capacity) ]
					: [ E('em', {}, [ _('unavailable') ]) ])
			])
		];
	},

	render(st) {
		const running = (st.running == true);
		const enabled = (st.serve && st.serve.enabled == '1');

		poll.add(L.bind(this.refresh, this), 5);
		poll.add(L.bind(this.refreshLogs, this), LOG_INTERVAL);

		const btn = (label, op, cls) => E('button', {
			'class': 'cbi-button cbi-button-' + cls,
			'click': ui.createHandlerFn(this, 'handleAction', op)
		}, [ label ]);

		this.logNode = E('pre', {
			'style': 'height:16em;overflow:auto;margin:0;padding:.4em;white-space:pre-wrap;' +
				'word-break:break-all;font-size:90%;border:1px solid rgba(128,128,128,.35);' +
				'border-radius:3px;background:rgba(128,128,128,.04)'
		}, [ E('em', {}, [ _('Loading…') ]) ]);

		// poll.add only fires after the first interval elapses, and 5 minutes of
		// "Loading…" reads as broken. Fill it in now; the node is still detached
		// at this point, which dom.content does not mind.
		this.refreshLogs(false);

		this.logRefreshButton = E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, 'handleRefreshLogs')
		}, [ _('Refresh now') ]);

		return E([], [
			E('h2', {}, [ _('Hermes Agent') ]),
			E('p', {}, [
				_('Hermes runs as a local gateway; this page manages the service, and the Chat page talks to it.')
			]),

			E('div', { 'id': 'hermes-status' }, this.renderStatus(st)),

			E('div', { 'class': 'cbi-page-actions', 'style': 'margin-top:1em' }, [
				running ? btn(_('Restart'), 'restart', 'action') : btn(_('Start'), 'start', 'positive'),
				' ',
				running ? btn(_('Stop'), 'stop', 'negative') : '',
				' ',
				enabled ? btn(_('Disable on boot'), 'disable', 'remove')
					: btn(_('Enable on boot'), 'enable', 'apply')
			]),

			E('div', {
				'style': 'display:flex;align-items:center;justify-content:space-between;' +
					'gap:.6em;margin-top:1.2em'
			}, [
				E('h3', { 'style': 'margin:0' }, [ _('Recent log') ]),
				this.logRefreshButton
			]),
			this.logNode
		]);
	}
});
