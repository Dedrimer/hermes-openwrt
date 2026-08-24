'use strict';
'require view';
'require rpc';
'require uci';
'require form';
'require ui';

// Settings: UCI service options, provider credentials, and raw config.yaml.
//
// Two groups of fields here are not backed by UCI, and use the standard LuCI
// idiom for that (cfgvalue/write/remove overridden, values collected into a
// pending buffer and flushed by handleSave -- the same shape luci-app-acl and
// luci-app-adblock-fast use):
//
//  * API keys live in /srv/hermes/.env, not UCI, because UCI config is
//    world-readable and ends up in support dumps. The backend reports only
//    whether a key is set, never its value, so these fields always render empty
//    and write only what the user actually types. A blank field therefore means
//    "leave unchanged" -- clearing a key needs the explicit checkbox.
//
//  * config.yaml is Hermes' own file, which Hermes rewrites itself. We treat it
//    as opaque text and let Hermes validate the contents.
//
// Because form.js only calls write() when formvalue differs from cfgvalue, an
// untouched field costs nothing: no .env rewrite, no config.yaml backup churn.

const callSettingsGet = rpc.declare({
	object: 'luci.hermes-agent',
	method: 'settings_get',
	expect: {}
});

const callSettingsSet = rpc.declare({
	object: 'luci.hermes-agent',
	method: 'settings_set',
	params: [ 'env_set', 'env_clear', 'config' ],
	expect: {}
});

const PROVIDERS = [
	[ 'OPENAI_API_KEY',     _('OpenAI API key') ],
	[ 'ANTHROPIC_API_KEY',  _('Anthropic API key') ],
	[ 'OPENROUTER_API_KEY', _('OpenRouter API key') ],
	[ 'NOUS_API_KEY',       _('Nous Research API key') ],
	[ 'DEEPSEEK_API_KEY',   _('DeepSeek API key') ],
	[ 'GEMINI_API_KEY',     _('Google Gemini API key') ]
];

return view.extend({
	// Filled by the option write() callbacks during Map.save(), drained by
	// handleSave() straight afterwards.
	pending: null,

	resetPending() {
		this.pending = { env_set: {}, env_clear: [], config: null };
	},

	load() {
		return Promise.all([
			uci.load('hermes-agent'),
			L.resolveDefault(callSettingsGet(), { env_present: {}, env: {}, config: '' })
		]);
	},

	render(data) {
		const st = data[1];
		const self = this;
		let m, s, o;

		this.st = st;
		this.resetPending();

		m = new form.Map('hermes-agent', _('Hermes Agent Settings'));

		// ---- service ------------------------------------------------------
		s = m.section(form.NamedSection, 'serve', 'service', _('Gateway service'));
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Start on boot'));
		o.rmempty = false;

		o = s.option(form.Value, 'host', _('Listen address'),
			_('Keep this on loopback. Hermes requires an authentication provider for any non-loopback bind, and the LuCI chat page reaches the gateway locally regardless.'));
		o.default = '127.0.0.1';
		o.datatype = 'ipaddr';
		o.rmempty = false;

		o = s.option(form.Value, 'port', _('Port'));
		o.default = '9119';
		o.datatype = 'port';
		o.rmempty = false;

		o = s.option(form.ListValue, 'log_level', _('Log level'));
		o.value('debug', 'debug');
		o.value('info', 'info');
		o.value('warning', 'warning');
		o.value('error', 'error');
		o.default = 'info';

		o = s.option(form.Value, 'workdir', _('Workspace directory'),
			_('Where the agent reads and writes files when a task involves them.'));
		o.default = '/srv/hermes/workspace';
		o.rmempty = false;

		// ---- credentials --------------------------------------------------
		s = m.section(form.NamedSection, 'serve', 'service', _('Provider credentials'),
			_('Stored in %s with mode 0600, not in UCI. Existing keys are never displayed — leave a field blank to keep it unchanged.')
				.format('<code>/srv/hermes/.env</code>'));
		s.addremove = false;

		PROVIDERS.forEach(entry => {
			const key = entry[0];
			const isSet = (st.env_present && st.env_present[key] == true);

			o = s.option(form.Value, 'key_' + key, entry[1],
				isSet ? _('A key is currently configured.') : _('Not configured.'));
			o.password = true;
			o.placeholder = isSet ? '••••••••' : '';
			o.rmempty = true;
			o.cfgvalue = () => '';
			o.write = (sid, val) => { self.pending.env_set[key] = String(val).trim(); };
			o.remove = () => {};

			if (isSet) {
				o = s.option(form.Flag, 'clear_' + key, _('Remove this key'));
				o.rmempty = true;
				o.cfgvalue = () => '0';
				o.write = () => { self.pending.env_clear.push(key); };
				o.remove = () => {};
			}
		});

		o = s.option(form.Value, 'env_OPENAI_BASE_URL', _('OpenAI base URL'),
			_('Optional. Point this at an OpenAI-compatible endpoint to use a local or third-party model server.'));
		o.placeholder = 'https://api.openai.com/v1';
		o.rmempty = true;
		o.cfgvalue = () => (st.env ? (st.env.OPENAI_BASE_URL ?? '') : '');
		o.write = (sid, val) => { self.pending.env_set.OPENAI_BASE_URL = String(val).trim(); };
		o.remove = () => { self.pending.env_clear.push('OPENAI_BASE_URL'); };

		// ---- config.yaml --------------------------------------------------
		s = m.section(form.NamedSection, 'serve', 'service', _('Hermes configuration'),
			_('The contents of %s. Hermes owns this file and rewrites it itself, so what you enter may come back reformatted. A backup is kept as %s on every save.')
				.format('<code>/srv/hermes/config.yaml</code>', '<code>config.yaml.bak</code>'));
		s.addremove = false;

		o = s.option(form.TextValue, 'config_yaml');
		o.rows = 20;
		o.monospace = true;
		o.rmempty = false;
		o.cfgvalue = () => (st.config ?? '');
		o.write = (sid, val) => { self.pending.config = String(val); };
		o.remove = () => {};

		return m.render();
	},

	// Push whatever the option writers collected. Runs after the UCI half has
	// been staged, so a rejected .env write surfaces before Apply restarts the
	// service with a config that has no matching credential.
	flushPending() {
		const p = this.pending;
		const args = {};
		let dirty = false;

		if (Object.keys(p.env_set).length) {
			args.env_set = p.env_set;
			dirty = true;
		}

		if (p.env_clear.length) {
			args.env_clear = p.env_clear;
			dirty = true;
		}

		if (p.config != null) {
			args.config = p.config;
			dirty = true;
		}

		if (!dirty)
			return Promise.resolve();

		return callSettingsSet(args.env_set ?? {}, args.env_clear ?? [], args.config ?? '')
			.then(res => {
				if (res && res.ok === false)
					throw new Error(res.error || _('the backend rejected the change'));

				// Re-read so the presence flags and textarea match reality on the
				// Save-only path, where the page is not reloaded.
				return L.resolveDefault(callSettingsGet(), null).then(fresh => {
					if (fresh) {
						this.st.env_present = fresh.env_present;
						this.st.env = fresh.env;
						this.st.config = fresh.config;
					}
				});
			})
			.catch(err => {
				ui.addNotification(null, E('p', {}, [
					_('Failed to save Hermes settings: %s').format(err.message)
				]), 'error');

				return Promise.reject(err);
			});
	},

	handleSave(ev) {
		this.resetPending();

		return Promise.resolve(this.super('handleSave', [ ev ]))
			.then(() => this.flushPending());
	},

	handleSaveApply(ev, mode) {
		return this.handleSave(ev).then(() => {
			ui.changes.apply(mode == '0');
		});
	}
});
