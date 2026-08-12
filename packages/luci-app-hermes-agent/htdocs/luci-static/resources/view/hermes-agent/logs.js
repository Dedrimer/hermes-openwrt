'use strict';

'require view';
'require rpc';

var callLogs = rpc.declare({
	object: 'hermes-agent',
	method: 'logs',
	params: [ 'lines', 'pattern' ],
	expect: { '': {} }
});

return view.extend({
	load: function() {
		return null;
	},

	render: function() {
		var self = this;

		var patternInput = E('input', { 'class': 'cbi-input-text', 'size': 30, 'value': 'hermes' });
		this.patternInput = patternInput;

		var linesSelect = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': '50' }, '50'),
			E('option', { 'value': '100' }, '100'),
			E('option', { 'value': '200', 'selected': true }, '200'),
			E('option', { 'value': '500' }, '500')
		]);
		this.linesSelect = linesSelect;

		var btnRefresh = E('button', { 'class': 'btn cbi-button-action', 'click': function() {
			self.refresh();
		}}, _('Refresh'));

		var output = E('div', { 'class': 'cbi-section-node' });
		this.output = output;

		var card = E('div', { 'class': 'cbi-section' }, [
			E('div', { 'class': 'cbi-section-node' }, [
				E('p', { 'class': 'cbi-section-descr' },
					_('System log entries matching the given pattern, read via logread. The hermes gateway writes to the logd service.'))
			]),
			E('div', { 'class': 'cbi-section-node' }, [
				E('label', { 'class': 'cbi-value-description' }, [
					_('Pattern'), ' ',
					patternInput,
					' ',
					_('Lines'), ' ',
					linesSelect,
					' ',
					btnRefresh
				])
			]),
			output
		]);

		this.refresh();

		return card;
	},

	refresh: function() {
		var self = this;
		var lines = parseInt(this.linesSelect.value) || 200;
		var pattern = this.patternInput.value || 'hermes';

		this.output.innerHTML = '';

		callLogs(lines, pattern).then(function(r) {
			if (r.code != 0) {
				self.output.appendChild(E('p', { 'class': 'cbi-section-descr' },
					_('Failed to read log (exit code %s)').format(r.code)));
				return;
			}

			var entries = r.lines || [];

			if (!entries.length) {
				self.output.appendChild(E('p', { 'class': 'cbi-section-descr' }, _('No matching log entries')));
				return;
			}

			entries.forEach(function(line) {
				self.output.appendChild(E('div', {
					'class': 'cbi-value-description',
					'style': 'font-family:monospace; white-space:pre-wrap; word-break:break-all;'
				}, line));
			});
		});
	}
});
