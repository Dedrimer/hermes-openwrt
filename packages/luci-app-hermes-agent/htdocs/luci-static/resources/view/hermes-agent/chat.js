'use strict';
'require view';
'require rpc';
'require poll';
'require ui';
'require dom';

// Chat: a conversation with the local Hermes agent, inside LuCI.
//
// Hermes' chat protocol is WebSocket-only, and a browser page here cannot open
// that socket itself -- the gateway is on loopback with a token the browser must
// never see. So hermes-chatd holds one websocket on the router and this page
// talks to it through two ubus calls:
//
//   chat_send(id, method, params)  queue one JSON-RPC request
//   chat_poll(gen, offset, tail)   read whatever the gateway has said since
//
// Responses come back through the same event stream as everything else, matched
// on the request id, so send() returns a promise that settles on the next poll.
// Polling is LuCI's own poll loop, which pauses while the tab is hidden and
// resumes where it left off -- the byte offset means nothing is lost meanwhile.
//
// One second of latency on a token stream is fine in practice: the gateway
// coalesces deltas at ~30fps anyway, so each poll delivers a readable burst
// rather than single characters.

const callChatSend = rpc.declare({
	object: 'luci.hermes-agent',
	method: 'chat_send',
	params: [ 'id', 'method', 'params' ],
	expect: {}
});

const callChatPoll = rpc.declare({
	object: 'luci.hermes-agent',
	method: 'chat_poll',
	params: [ 'gen', 'offset', 'tail' ],
	expect: {}
});

const POLL_INTERVAL = 1;
const BOOST_MS = 350;
const BOOST_TRIES = 8;
const RPC_TIMEOUT_MS = 60000;

// Labels for the approval choices Hermes offers. The set is built server-side
// from the tool's own policy (_approval_request_payload), so an unknown value
// must still render -- fall back to the raw token rather than dropping a button
// the user needs to unblock the agent.
const CHOICE_LABELS = {
	'once': _('Allow once'),
	'session': _('Allow for this session'),
	'always': _('Always allow'),
	'deny': _('Deny'),
	'allow': _('Allow'),
	'abort': _('Abort')
};

const ROLE_STYLE = {
	'user': 'background:rgba(33,150,243,.10);border-left:3px solid #2196f3',
	'assistant': 'background:rgba(76,175,80,.08);border-left:3px solid #4caf50',
	'system': 'background:rgba(158,158,158,.10);border-left:3px solid #9e9e9e',
	'tool': 'background:rgba(158,158,158,.07);border-left:3px solid #bdbdbd',
	'error': 'background:rgba(244,67,54,.10);border-left:3px solid #f44336',
	'think': 'background:rgba(156,39,176,.07);border-left:3px solid #9c27b0'
};

const ROLE_LABEL = {
	'user': _('You'),
	'assistant': _('Hermes'),
	'system': _('System'),
	'tool': _('Tool'),
	'error': _('Error'),
	'think': _('Reasoning')
};

function truncate(s, n) {
	s = String(s ?? '');

	return (s.length > n) ? s.substring(0, n) + '…' : s;
}

// A one-line summary of a tool call, in the spirit of Hermes' own collapsed
// tool rows: the interesting argument if we recognise the tool, else a clipped
// dump of the arguments.
function toolPreview(name, args) {
	if (!args || typeof args != 'object')
		return '';

	const pick = args.command ?? args.cmd ?? args.file_path ?? args.path ??
		args.pattern ?? args.query ?? args.url ?? args.prompt;

	if (pick != null)
		return truncate(pick, 160);

	try {
		return truncate(JSON.stringify(args), 160);
	} catch (e) {
		return '';
	}
}

return view.extend({
	// The transcript is not a form; Save/Apply would be meaningless here.
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	// --- wire state --------------------------------------------------------
	gen: 0,
	offset: 0,
	seq: 0,
	sid: '',
	waiting: null,
	polling: false,
	boosts: 0,
	primed: false,

	// --- transcript state --------------------------------------------------
	cur: null,        // open assistant bubble
	curThink: null,   // open reasoning bubble
	tools: null,      // tool_id -> row
	busy: false,
	info: null,       // last session.info payload (model, provider, tools)
	usage: null,      // last session.usage payload
	sessionTitle: '',

	load() {
		// tail: start reading at the end of the log. The transcript itself comes
		// from session.history below, so replaying the daemon's whole buffer here
		// would only duplicate it.
		return L.resolveDefault(callChatPoll(0, 0, true), { running: false });
	},

	// --- plumbing ----------------------------------------------------------

	send(method, params, timeout) {
		const id = 'c%d-%s'.format(++this.seq, Math.random().toString(36).substring(2, 8));

		return callChatSend(id, method, params ?? {}).then(res => {
			if (!res || res.ok !== true)
				throw new Error((res && res.error) || _('the bridge refused the request'));

			return new Promise((resolve, reject) => {
				this.waiting[id] = {
					resolve: resolve,
					reject: reject,
					method: method,
					deadline: Date.now() + (timeout ?? RPC_TIMEOUT_MS)
				};

				this.boost();
			});
		});
	},

	// Poll faster for a moment. Used after sending a request and while a turn is
	// streaming, so the page feels responsive without holding the router at a
	// high poll rate for an idle tab.
	boost() {
		if (this.boosts > 0) {
			this.boosts = BOOST_TRIES;
			return;
		}

		this.boosts = BOOST_TRIES;

		const step = () => {
			if (this.boosts <= 0)
				return;

			this.boosts--;

			this.pump().then(() => {
				const outstanding = Object.keys(this.waiting).length > 0;

				if (this.boosts > 0 && (outstanding || this.busy))
					window.setTimeout(step, BOOST_MS);
				else
					this.boosts = 0;
			});
		};

		window.setTimeout(step, BOOST_MS);
	},

	// One poll cycle: fetch, dispatch, expire.
	pump() {
		if (this.polling)
			return Promise.resolve();

		this.polling = true;

		return L.resolveDefault(callChatPoll(this.gen, this.offset, false), null)
			.then(res => {
				if (!res)
					return;

				this.setLink(res);

				if (res.running !== true)
					return;

				// A generation change means the daemon restarted or rotated its
				// log, so events were dropped. Rebuild from the gateway instead
				// of stitching a transcript with a hole in it.
				if (res.resync == true && this.primed && res.gen != this.gen) {
					this.gen = res.gen;
					this.offset = res.offset;

					return this.resync();
				}

				this.gen = res.gen;
				this.offset = res.offset;

				const lines = res.lines ?? [];

				for (let i = 0; i < lines.length; i++)
					this.dispatch(lines[i]);

				if (res.active_session && !this.sid)
					this.sid = res.active_session;
			})
			.then(() => this.expire())
			.finally(() => { this.polling = false; });
	},

	// Fail requests whose answer is never going to arrive -- the gateway
	// restarted mid-turn, or the bridge dropped the socket after queuing.
	expire() {
		const now = Date.now();
		const ids = Object.keys(this.waiting);

		for (let i = 0; i < ids.length; i++) {
			const w = this.waiting[ids[i]];

			if (w.deadline > now)
				continue;

			delete this.waiting[ids[i]];
			w.reject(new Error(_('%s timed out').format(w.method)));
		}
	},

	dispatch(line) {
		let msg;

		try {
			msg = JSON.parse(line);
		} catch (e) {
			return;
		}

		if (!msg || typeof msg != 'object')
			return;

		// A reply to one of our own requests.
		if (msg.id != null && (msg.result !== undefined || msg.error !== undefined)) {
			const w = this.waiting[msg.id];

			if (!w)
				return;

			delete this.waiting[msg.id];

			if (msg.error) {
				w.reject(new Error(msg.error.message || _('the gateway returned an error')));
			} else {
				w.resolve(msg.result);
			}

			return;
		}

		if (msg.method != 'event' || !msg.params)
			return;

		this.event(msg.params.type, msg.params.payload ?? {}, msg.params.session_id ?? '');
	},

	// --- events ------------------------------------------------------------

	event(type, p, sid) {
		// Session scoping: the bridge is shared, and a scheduled task or a CLI
		// client can be running a turn on another session at the same time.
		// Anything session-bound that is not ours is not ours to render.
		if (sid && this.sid && sid != this.sid && type != 'bridge.status')
			return;

		switch (type) {
		case 'bridge.status':
			// Rendered from the poll reply's own fields; nothing to add here.
			break;

		case 'message.start':
			this.setBusy(true);
			this.cur = null;
			break;

		case 'message.delta':
			this.setBusy(true);
			this.append('assistant', p.text ?? '');
			break;

		case 'message.interim':
			// A provisional full text (tool-call turns emit these between
			// steps). Replace rather than append, or the bubble doubles up.
			if (p.already_streamed != true)
				this.replace('assistant', p.text ?? '');
			break;

		case 'message.complete':
			this.finishTurn(p);
			break;

		case 'reasoning.delta':
		case 'thinking.delta':
			this.appendThink(p.text ?? '');
			break;

		case 'reasoning.available':
			if (!this.curThink)
				this.appendThink(p.text ?? '');
			break;

		case 'tool.generating':
			this.setActivity(_('Preparing %s…').format(p.name || _('a tool')));
			break;

		case 'tool.start':
			this.toolStart(p);
			break;

		case 'tool.complete':
			this.toolComplete(p);
			break;

		case 'status.update':
			this.setActivity(p.text ?? '');
			break;

		case 'backfill':
			this.setActivity(p.status == 'complete'
				? '' : _('Loading history…'));
			break;

		case 'approval.request':
			this.renderApproval(p);
			break;

		case 'clarify.request':
			this.renderClarify(p);
			break;

		case 'approval.expire':
		case 'clarify.expire':
			this.clearPrompt();
			break;

		case 'session.info':
			this.info = Object.assign(this.info ?? {}, p);
			this.renderMeta();
			break;

		case 'session.usage':
			this.usage = p.usage ?? p;
			this.renderMeta();
			break;

		case 'session.title':
			this.sessionTitle = p.title ?? '';
			this.renderMeta();
			break;

		case 'error':
			this.setBusy(false);
			this.row('error', p.message ?? _('unknown error'));
			break;
		}
	},

	finishTurn(p) {
		this.setBusy(false);
		this.setActivity('');
		this.clearPrompt();

		// The final text is authoritative: streamed deltas can be reformatted or,
		// on a resumed turn, never have been streamed to us at all.
		const text = p.text ?? '';

		if (p.status == 'error') {
			this.cur = null;
			this.curThink = null;
			this.row('error', p.error ? '%s\n\n%s'.format(p.error, text) : text);

			return;
		}

		if (text != '')
			this.replace('assistant', text);

		this.cur = null;
		this.curThink = null;
	},

	toolStart(p) {
		const preview = toolPreview(p.name, p.args);
		const node = this.row('tool', preview
			? '%s — %s'.format(p.name || _('tool'), preview)
			: String(p.name || _('tool')));

		if (p.tool_id)
			this.tools[p.tool_id] = node;

		this.setActivity(_('Running %s…').format(p.name || _('a tool')));
	},

	toolComplete(p) {
		const node = p.tool_id ? this.tools[p.tool_id] : null;
		const bits = [ String(p.name || _('tool')) ];

		if (p.summary)
			bits.push(truncate(p.summary, 200));
		else if (p.args)
			bits.push(toolPreview(p.name, p.args));

		if (p.duration_s != null)
			bits.push(Number(p.duration_s).toFixed(1) + 's');

		const text = bits.filter(b => b != '').join(' — ');

		if (node) {
			dom.content(node.body, text);
			delete this.tools[p.tool_id];
		} else {
			this.row('tool', text);
		}

		this.setActivity('');
	},

	// --- transcript rendering ----------------------------------------------

	// Rows carry their own text so streaming updates touch one text node instead
	// of re-rendering the transcript; a long turn otherwise rebuilds hundreds of
	// nodes a second on a router's CPU.
	row(role, text) {
		const body = E('div', { 'style': 'white-space:pre-wrap;word-break:break-word' }, [ text ]);
		const node = E('div', {
			'style': 'margin:.4em 0;padding:.4em .6em;border-radius:3px;' + (ROLE_STYLE[role] ?? '')
		}, [
			E('div', { 'style': 'font-size:85%;opacity:.65;margin-bottom:.15em' }, [ ROLE_LABEL[role] ?? role ]),
			body
		]);

		node.body = body;
		node.text = text;

		this.log.appendChild(node);
		this.scroll();

		return node;
	},

	append(role, text) {
		if (text == '')
			return;

		if (!this.cur)
			this.cur = this.row(role, '');

		this.cur.text += text;
		dom.content(this.cur.body, this.cur.text);
		this.scroll();
	},

	replace(role, text) {
		if (!this.cur)
			this.cur = this.row(role, '');

		this.cur.text = text;
		dom.content(this.cur.body, text);
		this.scroll();
	},

	appendThink(text) {
		if (text == '')
			return;

		if (!this.curThink) {
			this.curThink = this.row('think', '');
			this.curThink.style.fontSize = '90%';
			this.curThink.style.opacity = '.8';
		}

		this.curThink.text += text;
		dom.content(this.curThink.body, this.curThink.text);
		this.scroll();
	},

	// Only follow the stream if the reader is already at the bottom, so scrolling
	// back to re-read something is not yanked away by the next delta.
	scroll() {
		const el = this.log;

		if (!el)
			return;

		if (el.scrollHeight - el.scrollTop - el.clientHeight < 80)
			el.scrollTop = el.scrollHeight;
	},

	setActivity(text) {
		if (this.activity)
			dom.content(this.activity, text ? [ E('em', {}, [ truncate(text, 300) ]) ] : []);
	},

	setBusy(busy) {
		if (this.busy == busy)
			return;

		this.busy = busy;

		if (this.btnSend)
			this.btnSend.disabled = busy;

		if (this.btnStop)
			this.btnStop.style.display = busy ? '' : 'none';

		if (busy)
			this.boost();
	},

	setLink(res) {
		const down = (res.running !== true) || (res.connected !== true);
		const msg = res.error || (res.running !== true
			? _('The chat bridge is not running.')
			: _('The chat bridge is not connected to the gateway.'));

		if (this.banner) {
			dom.content(this.banner, down
				? [ E('div', { 'class': 'alert-message warning' }, [
					E('p', {}, [ msg ]),
					E('p', {}, [ _('Check that the service is started on the Overview page. The bridge reconnects on its own once the gateway is up.') ])
				  ]) ]
				: []);
		}

		if (this.btnSend && down)
			this.btnSend.disabled = true;
		else if (this.btnSend && !this.busy)
			this.btnSend.disabled = false;
	},

	renderMeta() {
		if (!this.meta)
			return;

		const info = this.info ?? {};
		const parts = [];

		if (this.sessionTitle)
			parts.push(truncate(this.sessionTitle, 80));

		if (info.model)
			parts.push(info.provider ? '%s / %s'.format(info.provider, info.model) : info.model);

		if (this.usage && this.usage.total_tokens)
			parts.push(_('%d tokens').format(this.usage.total_tokens));

		if (this.sid)
			parts.push(_('session %s').format(this.sid.substring(0, 8)));

		dom.content(this.meta, parts.join('  ·  '));
	},

	// --- interactive prompts ----------------------------------------------

	clearPrompt() {
		if (this.prompt)
			dom.content(this.prompt, []);
	},

	// The agent is blocked waiting for this answer, so it gets its own card
	// above the input rather than a line in the transcript.
	renderApproval(p) {
		const choices = Array.isArray(p.choices) && p.choices.length
			? p.choices : [ 'once', 'deny' ];
		const detail = p.command ?? p.description ?? p.tool ?? '';

		const card = E('div', { 'class': 'alert-message' }, [
			E('p', { 'style': 'margin:0 0 .3em' }, [
				E('strong', {}, [ _('Approval required') ]),
				p.tool ? E('span', {}, [ ' — ' + p.tool ]) : ''
			]),
			p.reason ? E('p', { 'style': 'margin:.2em 0' }, [ String(p.reason) ]) : '',
			detail ? E('pre', {
				'style': 'white-space:pre-wrap;margin:.3em 0;max-height:12em;overflow:auto'
			}, [ String(detail) ]) : '',
			E('div', {}, choices.map(c => E('button', {
				'class': 'cbi-button cbi-button-' + (c == 'deny' || c == 'abort' ? 'negative' : 'positive'),
				'style': 'margin-right:.4em',
				'click': ui.createHandlerFn(this, 'handleApproval', p.request_id, c)
			}, [ CHOICE_LABELS[c] ?? c ])))
		]);

		dom.content(this.prompt, [ card ]);
		this.scroll();
	},

	handleApproval(requestId, choice, ev) {
		this.clearPrompt();
		this.setActivity(_('Sending decision…'));

		return this.send('approval.respond', {
			session_id: this.sid,
			choice: choice,
			request_id: requestId ?? null
		}).catch(err => this.fail(err));
	},

	// Clarify can be a single question or a batch. Both are rendered as radio
	// groups with a free-text fallback, because Hermes' clarify tool accepts an
	// answer outside the offered choices.
	renderClarify(p) {
		const questions = Array.isArray(p.questions) && p.questions.length
			? p.questions
			: [ { qid: '', question: p.question ?? _('Please clarify'), choices: p.choices ?? [] } ];
		const inputs = [];

		const blocks = questions.map((q, qi) => {
			const name = 'hermes-clarify-%d'.format(qi);
			const free = E('input', {
				'type': 'text',
				'class': 'cbi-input-text',
				'style': 'width:100%;margin-top:.3em',
				'placeholder': _('or type your own answer')
			});

			inputs.push({ qid: q.qid ?? '', name: name, free: free });

			return E('div', { 'style': 'margin:.4em 0' }, [
				E('p', { 'style': 'margin:0 0 .2em' }, [ E('strong', {}, [ String(q.question ?? '') ]) ]),
				E('div', {}, (q.choices ?? []).map(c => E('label', {
					'style': 'display:block;margin:.1em 0'
				}, [
					E('input', { 'type': 'radio', 'name': name, 'value': String(c) }),
					' ' + String(c)
				]))),
				free
			]);
		});

		this.clarifyInputs = inputs;
		this.clarifyBatch = (Array.isArray(p.questions) && p.questions.length > 0);

		dom.content(this.prompt, [
			E('div', { 'class': 'alert-message' }, [
				E('p', { 'style': 'margin:0' }, [ E('strong', {}, [ _('Hermes needs a clarification') ]) ]),
				E('div', {}, blocks),
				E('div', { 'style': 'margin-top:.4em' }, [
					E('button', {
						'class': 'cbi-button cbi-button-positive',
						'click': ui.createHandlerFn(this, 'handleClarify', p.request_id)
					}, [ _('Answer') ])
				])
			])
		]);

		this.scroll();
	},

	handleClarify(requestId, ev) {
		const inputs = this.clarifyInputs ?? [];
		const answers = {};
		const single = [];

		inputs.forEach(entry => {
			const typed = (entry.free.value ?? '').trim();
			const picked = document.querySelector('input[name="%s"]:checked'.format(entry.name));
			const value = typed || (picked ? picked.value : '');

			if (entry.qid)
				answers[entry.qid] = value;
			else
				single.push(value);
		});

		// Batch clarify expects a JSON object keyed by question id; the
		// single-question form expects a plain string. The tool parses both.
		const answer = this.clarifyBatch ? JSON.stringify(answers) : (single[0] ?? '');

		this.clearPrompt();
		this.setActivity(_('Sending answer…'));

		return this.send('clarify.respond', {
			session_id: this.sid,
			request_id: requestId ?? null,
			answer: answer
		}).catch(err => this.fail(err));
	},

	// --- actions -----------------------------------------------------------

	fail(err) {
		this.setActivity('');
		ui.addNotification(null, E('p', {}, [ err.message ]), 'error');
	},

	resync() {
		if (!this.sid)
			return Promise.resolve();

		return this.send('session.history', { session_id: this.sid })
			.then(res => this.loadHistory(res))
			.catch(err => this.fail(err));
	},

	loadHistory(res) {
		const messages = (res && res.messages) ? res.messages : [];

		dom.content(this.log, []);
		this.cur = null;
		this.curThink = null;
		this.tools = {};

		messages.forEach(m => {
			if (m.role == 'tool') {
				this.row('tool', [ m.name, m.context ].filter(x => x).join(' — '));
				return;
			}

			const text = (typeof m.content == 'string') ? m.content
				: (m.text ?? '');

			if (String(text).trim() != '')
				this.row(m.role == 'user' ? 'user' : (m.role == 'system' ? 'system' : 'assistant'), text);
		});

		// A fresh row set means no bubble is open for continuation.
		this.cur = null;
		this.log.scrollTop = this.log.scrollHeight;
	},

	handleSend(ev) {
		const text = (this.input.value ?? '').trim();

		if (text == '')
			return Promise.resolve();

		if (!this.sid) {
			return this.startSession()
				.then(() => this.handleSend(ev))
				.catch(err => this.fail(err));
		}

		this.input.value = '';
		this.row('user', text);
		this.setBusy(true);
		this.setActivity(_('Sending…'));

		return this.send('prompt.submit', { session_id: this.sid, text: text })
			.catch(err => {
				this.setBusy(false);
				this.fail(err);
			});
	},

	handleStop(ev) {
		return this.send('session.interrupt', { session_id: this.sid })
			.then(() => this.setActivity(_('Interrupting…')))
			.catch(err => this.fail(err));
	},

	handleNew(ev) {
		const old = this.sid;

		this.sid = '';
		this.info = null;
		this.usage = null;
		this.sessionTitle = '';

		return (old ? this.send('session.close', { session_id: old })
			.catch(() => null) : Promise.resolve())
			.then(() => this.startSession())
			.then(() => {
				dom.content(this.log, []);
				this.cur = null;
				this.curThink = null;
				this.tools = {};
				this.setActivity('');
			})
			.catch(err => this.fail(err));
	},

	// close_on_disconnect stays false on purpose: hermes-chatd reconnects after
	// a gateway restart, and a session that vanished with the socket would take
	// the transcript with it.
	startSession() {
		return this.send('session.create', {
			cols: 100,
			source: 'luci',
			close_on_disconnect: false
		}).then(res => {
			this.sid = String((res && res.session_id) || '');

			if (!this.sid)
				throw new Error(_('the gateway did not return a session id'));

			if (res.info)
				this.info = res.info;

			this.renderMeta();

			if (res.messages && res.messages.length)
				this.loadHistory(res);

			return this.sid;
		});
	},

	// --- view --------------------------------------------------------------

	render(st) {
		this.waiting = {};
		this.tools = {};
		this.gen = st.gen ?? 0;
		this.offset = st.offset ?? 0;
		this.sid = st.active_session ?? '';

		this.banner = E('div', {});
		this.meta = E('div', { 'style': 'font-size:90%;opacity:.7;margin-bottom:.3em' }, []);
		this.log = E('div', {
			'style': 'height:26em;overflow-y:auto;padding:.3em;border:1px solid rgba(128,128,128,.35);' +
				'border-radius:3px;background:rgba(128,128,128,.04)'
		}, []);
		this.activity = E('div', { 'style': 'min-height:1.3em;font-size:90%;opacity:.7;margin:.2em 0' }, []);
		this.prompt = E('div', {}, []);

		this.input = E('textarea', {
			'class': 'cbi-input-textarea',
			'style': 'width:100%;font-family:inherit',
			'rows': 3,
			'placeholder': _('Ask Hermes something. Ctrl+Enter sends.')
		});

		// Not ui.createHandlerFn here: that disables the element it fires on for
		// the duration of the handler, which on a textarea would eat the rest of
		// the user's typing.
		this.input.addEventListener('keydown', L.bind(function(ev) {
			if (ev.key == 'Enter' && (ev.ctrlKey || ev.metaKey)) {
				ev.preventDefault();
				this.handleSend(ev);
			}
		}, this));

		this.btnSend = E('button', {
			'class': 'cbi-button cbi-button-positive',
			'click': ui.createHandlerFn(this, 'handleSend')
		}, [ _('Send') ]);

		this.btnStop = E('button', {
			'class': 'cbi-button cbi-button-negative',
			'style': 'display:none;margin-left:.4em',
			'click': ui.createHandlerFn(this, 'handleStop')
		}, [ _('Interrupt') ]);

		const btnNew = E('button', {
			'class': 'cbi-button cbi-button-action',
			'style': 'margin-left:.4em',
			'click': ui.createHandlerFn(this, 'handleNew')
		}, [ _('New session') ]);

		const body = E([], [
			E('h2', {}, [ _('Hermes Chat') ]),
			this.banner,
			E('div', { 'class': 'cbi-section' }, [
				this.meta,
				this.log,
				this.activity,
				this.prompt,
				this.input,
				E('div', { 'style': 'margin-top:.4em' }, [ this.btnSend, this.btnStop, btnNew ])
			])
		]);

		this.setLink(st);

		// Attach to whatever session the bridge already had (a reload, or a turn
		// started from the CLI), otherwise open one. Either way the first poll
		// after this picks the stream up from the offset load() established.
		const boot = (st.running === true && st.connected === true)
			? (this.sid
				? this.send('session.history', { session_id: this.sid })
					.then(res => this.loadHistory(res))
				: this.startSession())
			: Promise.resolve();

		boot.catch(err => this.fail(err)).then(() => {
			this.primed = true;
			poll.add(L.bind(this.pump, this), POLL_INTERVAL);
		});

		return body;
	}
});
