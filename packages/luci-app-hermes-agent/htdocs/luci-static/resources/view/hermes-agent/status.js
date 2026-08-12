'use strict';

'require view';
'require rpc';
'require ui';

var callStatus = rpc.declare({
	object: 'hermes-agent',
	method: 'status',
	expect: { '': {} }
});

var callAction = rpc.declare({
	object: 'hermes-agent',
	method: 'action',
	params: [ 'op' ],
	expect: { '': {} }
});

function formatSize(kb) {
	if (kb >= 1048576)
		return (kb / 1048576).toFixed(1) + ' GB';

	if (kb >= 1024)
		return (kb / 1024).toFixed(1) + ' MB';

	return kb + ' KB';
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleAction: function(op) {
		return callAction(op).then(function(r) {
			if (r.code == 0) {
				ui.addNotification(null, E('p', _('Service %s executed successfully').format(op)));
				location.reload();
			}
			else {
				ui.addNotification(null, E('p', _('Failed to execute %s (exit code %s)').format(op, r.code)));
			}
		});
	},

	render: function(data) {
		var status = data;
		var instances = status.instances || {};
		var cfg = status.config || {};
		var dashCfg = cfg.dashboard || {};

		var table = E('table', { 'class': 'cbi-section-table' });

		table.appendChild(E('tr', { 'class': 'cbi-section-table-titles' }, [
			E('th', { 'class': 'cbi-section-table-cell' }, _('Instance')),
			E('th', { 'class': 'cbi-section-table-cell' }, _('Status')),
			E('th', { 'class': 'cbi-section-table-cell' }, _('Details'))
		]));

		[ 'gateway', 'dashboard' ].forEach(function(name) {
			var enabled = (cfg[name] && cfg[name].enabled == '1');
			var inst = instances[name] || {};
			var text, cls;

			if (!enabled) {
				text = _('Disabled');
				cls = 'gray';
			}
			else if (inst.running) {
				text = _('Running');
				cls = 'green';
			}
			else {
				text = _('Not running');
				cls = 'red';
			}

			var details = '';
			if (name == 'gateway' && cfg[name])
				details = _('Profile: %s').format(cfg[name].profile || 'default');
			else if (name == 'dashboard' && cfg[name])
				details = '%s:%s'.format(cfg[name].bind || '127.0.0.1', cfg[name].port || '9119');

			table.appendChild(E('tr', { 'class': 'cbi-section-table-row' }, [
				E('td', { 'class': 'cbi-section-table-cell' }, E('strong', name)),
				E('td', { 'class': 'cbi-section-table-cell' }, E('span', { 'style': 'color:' + cls }, text)),
				E('td', { 'class': 'cbi-section-table-cell' }, details)
			]));
		});

		var buttons = E('div', { 'class': 'cbi-page-actions' }, [
			E('button', { 'class': 'btn cbi-button-action', 'click': function() { this.handleAction('start'); }.bind(this) }, _('Start')),
			E('button', { 'class': 'btn cbi-button-action', 'click': function() { this.handleAction('stop'); }.bind(this) }, _('Stop')),
			E('button', { 'class': 'btn cbi-button-action important', 'click': function() { this.handleAction('restart'); }.bind(this) }, _('Restart'))
		]);

		var dashboardLink = null;
		if (dashCfg.enabled == '1')
			dashboardLink = E('p', {}, [
				E('a', { 'href': 'http://%s:%s/'.format(dashCfg.bind || '127.0.0.1', dashCfg.port || '9119'), 'target': '_blank', 'rel': 'noreferrer' },
					_('Open dashboard') + ' (http://%s:%s/)'.format(dashCfg.bind || '127.0.0.1', dashCfg.port || '9119'))
			]);

		var info = E('table', { 'class': 'cbi-section-table' }, [
			E('tr', { 'class': 'cbi-section-table-titles' }, [
				E('th', { 'class': 'cbi-section-table-cell' }, _('Version')),
				E('th', { 'class': 'cbi-section-table-cell' }, _('Data directory')),
				E('th', { 'class': 'cbi-section-table-cell' }, _('Disk usage'))
			]),
			E('tr', { 'class': 'cbi-section-table-row' }, [
				E('td', { 'class': 'cbi-section-table-cell' }, status.version || _('unknown')),
				E('td', { 'class': 'cbi-section-table-cell' }, E('code', status.home || '/etc/hermes')),
				E('td', { 'class': 'cbi-section-table-cell' },
					status.disk
						? _('%s free of %s (%s used)').format(formatSize(parseInt(status.disk.avail)), formatSize(parseInt(status.disk.size)), status.disk.capacity)
						: _('unavailable'))
			])
		]);

		return E('div', [
			E('h2', _('Hermes Agent Status')),
			E('p', { 'class': 'cbi-section-descr' },
				_('The gateway daemon and the dashboard run as procd instances of the hermes-agent service.')),

			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-section-node' }, [ table ]),
				buttons,
				dashboardLink
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-section-node' }, [ info ])
			])
		]);
	}
});
