'use strict';

'require view';
'require form';
'require rpc';
'require uci';
'require ui';

var ENV_KEYS = [
	'OPENAI_API_KEY',
	'ANTHROPIC_API_KEY',
	'OPENROUTER_API_KEY',
	'NOUS_API_KEY',
	'GEMINI_API_KEY',
	'HF_TOKEN'
];

var callSettingsGet = rpc.declare({
	object: 'hermes-agent',
	method: 'settings_get',
	expect: { '': {} }
});

var callSettingsSet = rpc.declare({
	object: 'hermes-agent',
	method: 'settings_set',
	params: [ 'uci', 'env', 'config' ],
	expect: { '': {} }
});

var callAction = rpc.declare({
	object: 'hermes-agent',
	method: 'action',
	params: [ 'op' ],
	expect: { '': {} }
});

return view.extend({
	load: function() {
		return Promise.all([
			callSettingsGet(),
			uci.load('hermes-agent')
		]);
	},

	render: function(data) {
		var sdata = data[0];
		var self = this;

		var m = new form.Map('hermes-agent', _('Hermes Agent Settings'),
			_('Configure the gateway daemon and the dashboard. API keys and config.yaml are stored under /etc/hermes. Changes to the UCI options below only take effect after the service is restarted.'));

		var s = m.section(form.NamedSection, 'gateway', 'hermes', _('Gateway daemon'));
		s.option(form.Flag, 'enabled', _('Enabled'), _('Run the gateway daemon as a procd service'));
		s.option(form.Value, 'profile', _('Profile'), _('Active HERMES_PROFILE (profiles live in /etc/hermes/profiles)'));

		var s2 = m.section(form.NamedSection, 'dashboard', 'hermes', _('Dashboard (hermes serve)'));
		s2.option(form.Flag, 'enabled', _('Enabled'), _('Run the headless dashboard server'));
		s2.option(form.Value, 'bind', _('Listen address'));
		s2.option(form.Value, 'port', _('Listen port'));
		s2.option(form.Flag, 'insecure', _('Insecure mode'), _('Required when binding to a non-loopback address'));

		var envCard = this.renderEnvCard(sdata.env || {});
		var cfgCard = this.renderConfigCard(sdata.config || '');

		var btnApply = E('button', { 'class': 'btn cbi-button-action important', 'click': function() {
			callAction('restart').then(function(r) {
				if (r.code == 0)
					ui.addNotification(null, E('p', _('Service restarted')));
				else
					ui.addNotification(null, E('p', _('Failed to restart service (exit code %s)').format(r.code)));
			});
		}}, _('Restart service now'));

		return m.render().then(function(node) {
			return E('div', [
				node,
				envCard,
				cfgCard,
				E('div', { 'class': 'cbi-page-actions' }, [ btnApply ])
			]);
		});
	},

	renderEnvCard: function(env) {
		var self = this;
		var inputs = {};

		var table = E('table', { 'class': 'cbi-section-table' });

		ENV_KEYS.forEach(function(key) {
			var input = E('input', {
				'type': 'password',
				'class': 'cbi-input-password',
				'value': env[key] || '',
				'autocomplete': 'new-password'
			});

			inputs[key] = input;

			table.appendChild(E('tr', { 'class': 'cbi-section-table-row' }, [
				E('td', { 'class': 'cbi-section-table-cell' }, E('code', key)),
				E('td', { 'class': 'cbi-section-table-cell' }, [ input ])
			]));
		});

		var btnSave = E('button', { 'class': 'btn cbi-button-action', 'click': function() {
			var envIn = {};

			ENV_KEYS.forEach(function(key) {
				envIn[key] = inputs[key].value;
			});

			callSettingsSet(undefined, envIn, undefined).then(function(r) {
				self.notify(r, _('API keys saved to /etc/hermes/.env'));
			});
		}}, _('Save API Keys'));

		return E('div', { 'class': 'cbi-section' }, [
			E('div', { 'class': 'cbi-section-node' }, [
				E('h3', _('API Keys')),
				E('p', { 'class': 'cbi-section-descr' },
					_('Provider API keys are stored in /etc/hermes/.env (root only). Leave a field empty to remove that key.'))
			]),
			E('div', { 'class': 'cbi-section-node' }, [ table ]),
			btnSave
		]);
	},

	renderConfigCard: function(config) {
		var self = this;

		var ta = E('textarea', {
			'class': 'cbi-input-textarea',
			'rows': 24,
			'style': 'width:100%; font-family:monospace;'
		});

		ta.value = config;

		var btnSave = E('button', { 'class': 'btn cbi-button-action', 'click': function() {
			callSettingsSet(undefined, undefined, ta.value).then(function(r) {
				self.notify(r, _('config.yaml saved'));
			});
		}}, _('Save config.yaml'));

		return E('div', { 'class': 'cbi-section' }, [
			E('div', { 'class': 'cbi-section-node' }, [
				E('h3', _('config.yaml')),
				E('p', { 'class': 'cbi-section-descr' },
					_('Full contents of /etc/hermes/config.yaml. A backup is kept as config.yaml.bak on every save. Changes require a service restart.'))
			]),
			E('div', { 'class': 'cbi-section-node' }, [ ta ]),
			btnSave
		]);
	},

	notify: function(r, okText) {
		if (r.ok) {
			ui.addNotification(null, E('p', okText));
		}
		else {
			ui.addNotification(null, E('p', _('Save failed: %s').format(r.error || _('unknown error'))));
		}
	}
});
