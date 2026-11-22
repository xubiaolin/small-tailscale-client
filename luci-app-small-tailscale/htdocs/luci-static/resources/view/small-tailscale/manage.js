'use strict';
'require view';
'require rpc';
'require poll';

const styles = `
.smallts {
	--smallts-accent: var(--primary, #4c58cf);
	--smallts-border: color-mix(in srgb, currentColor 18%, transparent);
	overflow-wrap: anywhere;
}
.smallts [hidden] { display: none !important; }
.smallts :is(p, dl, dd, h3, h4) { margin: 0; }
.smallts .cbi-section h3, .smallts .cbi-section h4 { width: auto; padding: 0; background: none; line-height: 1.4; }
.smallts :is(a, button, input, select, summary, h3):focus-visible {
	outline: 2px solid var(--smallts-accent);
	outline-offset: 3px;
}
.smallts .cbi-section {
	min-width: 0;
	padding: clamp(14px, 2vw, 22px);
	margin: 0 0 14px;
	border: 1px solid var(--smallts-border);
	border-radius: 7px;
}
.smallts .smallts-editor { min-width: 0; margin: 0; padding: 0; border: 0; }
.smallts .smallts-hint, .smallts dt { font-size: .9em; }
.smallts :is(.smallts-card-head, .smallts-actions, .smallts-status, .smallts-footer, .smallts-check) {
	display: flex;
	gap: 8px 12px;
	align-items: center;
	flex-wrap: wrap;
}
.smallts :is(.smallts-card-head, .smallts-footer) { justify-content: space-between; }
.smallts .smallts-card-head a { padding-block: 8px; }
.smallts .smallts-status { margin: 8px 0 12px; }
.smallts .smallts-pill {
	padding: 3px 9px;
	border-radius: 5px;
	background: color-mix(in srgb, currentColor 10%, transparent);
	font-weight: 700;
}
.smallts .smallts-pill::before { content: "●"; margin-inline-end: 7px; }
.smallts .smallts-pill[data-state="Running"]::before { color: #37845d; }
.smallts .smallts-pill:is([data-state="NeedsLogin"], [data-state="NeedsMachineAuth"])::before { color: #ae7518; }
.smallts :is(.smallts-facts, .smallts-chain) { padding-top: 12px; border-top: 1px solid var(--smallts-border); }
.smallts :is(.smallts-facts, .smallts-subfacts, .smallts-subgrid, .smallts-settings, .smallts-two) {
	display: grid;
	gap: 10px 16px;
	grid-template-columns: repeat(2, minmax(0, 1fr));
}
.smallts .smallts-facts { grid-template-columns: repeat(auto-fit, minmax(min(100%, 145px), 1fr)); }
.smallts .smallts-settings { grid-template-columns: minmax(0, 1fr) minmax(0, 1.8fr); gap: 0 14px; }
.smallts .smallts-field { display: grid; gap: 4px; align-content: start; min-width: 0; }
.smallts .smallts-field :is(input,select) { min-width: 0; max-width: 100%; width: 100%; box-sizing: border-box; }
.smallts :is(button, .smallts-field input, .smallts-field select) { min-height: 40px; }
.smallts .smallts-check { min-height: 40px; }
.smallts .smallts-check input { appearance: auto; margin: 0; }
.smallts :is(.smallts-field label, summary, dd) { font-weight: 600; }
.smallts :is(.smallts-subgrid, .smallts-subfacts, .smallts-chain, .smallts-actions, .smallts-notice, .smallts-maintenance, .smallts-two) {
	margin-top: 10px;
}
.smallts :is(.smallts-preview, .smallts-maintenance, .smallts-notice) {
	background: color-mix(in srgb, currentColor 4%, transparent);
	border: 1px solid var(--smallts-border);
	border-radius: 5px;
	padding: 12px;
}
.smallts .smallts-preview { display: grid; gap: 6px; align-content: start; }
.smallts .smallts-preview ul { margin: 0; padding-inline-start: 19px; }
.smallts .smallts-preview ul:empty, .smallts [role="status"]:empty { display: none; }
.smallts .smallts-notice a { margin-inline-start: 8px; }
.smallts summary { cursor: pointer; padding-block: 4px; }
.smallts .smallts-fold-content { padding-top: 10px; }
.smallts .smallts-fold-content h4:not(:first-child) { margin-top: 14px; }
.smallts dialog {
	width: min(28rem, calc(100% - 32px));
	box-sizing: border-box;
	border: 1px solid var(--smallts-border);
	border-radius: 7px;
	padding: 20px;
	color: CanvasText;
	background: Canvas;
}
.smallts dialog::backdrop { background: #232b4f77; }
@media (max-width: 900px) {
	.smallts :is(.smallts-subgrid, .smallts-settings) { grid-template-columns: minmax(0, 1fr); }
}
@media (max-width: 490px) {
	.smallts .smallts-two { grid-template-columns: minmax(0, 1fr); }
}
`;

function method(name, params, object) {
	const call = rpc.declare({ object: object || 'small-tailscale', method: name, params: params || [], reject: true });
	return async function() {
		const result = await call(...arguments);
		if (!result || result.error) throw new Error(result && result.error || '路由器未返回操作结果');
		return result;
	};
}

const readStatus = method('status');
const adminStatus = method('status_auth');
function status() { return L.hasViewPermission() ? adminStatus() : readStatus(); }
const config = method('config');
const save = method('save', ['mode', 'auto_update', 'pinned_version', 'mirror', 'params', 'previous']);
const install = method('install');
const start = method('start');
const preview = method('preview', ['routes'], 'small-tailscale.network');
const apply = method('apply', ['routes', 'token'], 'small-tailscale.network');
const states = {
	Stopped: '已安装 · 未连接', Starting: '启动中', Running: '已连接', NeedsLogin: '待授权',
	NeedsMachineAuth: '等待管理员批准', NoState: '等待服务就绪', InUseOtherUser: '已被其他用户使用'
};
const stateHints = {
	Stopped: '启动服务并使用已保存的连接设置。',
	Starting: '正在读取节点状态，可在运行日志查看进度。',
	Running: '路由器当前报告 Tailscale 已连接。',
	NeedsMachineAuth: '设备授权已提交，请等待控制端管理员批准后再查看连接状态。',
	NoState: '等待服务就绪后继续读取状态。',
	InUseOtherUser: '请查看运行日志，确认当前服务的使用者。'
};

function authAddress(node) {
	if (node.state !== 'NeedsLogin' || !node.auth_url) return '';
	try {
		const url = new URL(node.auth_url);
		if (['https:', 'http:'].includes(url.protocol))
			return url.href;
	}
	catch (_) {}
	return '';
}

function logLink(kind, label) {
	const href = L.url('admin', 'services', 'small-tailscale', 'logs');
	return E('a', { href: href + (kind ? '#log-' + kind : '') }, [label]);
}

function fact(label, value) {
	return E('div', {}, [E('dt', {}, [label]), E('dd', {}, [value])]);
}

function choice(id, choices, value) {
	const select = E('select', { id, class: 'cbi-input-select' }, choices.map(function(pair) {
		return E('option', { value: pair[0] }, [pair[1]]);
	}));
	select.value = value;
	return select;
}

function field(label, control, hint) {
	const description = control.id + '-hint';
	if (hint) control.setAttribute('aria-describedby', description);
	return E('div', { class: 'smallts-field' }, [
		E('label', { for: control.id }, [label]), control,
		...(hint ? [E('p', { id: description, class: 'smallts-hint' }, [hint])] : [])
	]);
}

function section(title, contents) {
	return E('div', { class: 'cbi-section' }, [E('h3', {}, [title]), ...contents]);
}

function button(label, action, primary) {
	return E('button', { type: 'button', class: 'cbi-button ' + (primary ? 'cbi-button-apply' : 'cbi-button-action'), click: action }, [label]);
}

const groups = [
	['常用连接设置', ['hostname', 'login-server', 'accept-dns', 'accept-routes', 'advertise-exit-node', 'exit-node']],
	['身份与授权', ['auth-key', 'client-id', 'client-secret', 'id-token', 'advertise-tags', 'force-reauth']],
	['路由与防火墙', ['exit-node-allow-lan-access', 'advertise-connector', 'netfilter-mode', 'snat-subnet-routes', 'stateful-filtering']],
	['访问控制', ['operator', 'ssh', 'shields-up', 'accept-risk']],
	['命令行为与输出', ['reset', 'timeout', 'json', 'qr', 'qr-format']]
];
const labels = {
	hostname: '主机名', 'accept-dns': '接受 DNS 配置', 'advertise-routes': '通告子网路由',
	'accept-routes': '接受其他节点的路由', 'advertise-exit-node': '提供出口节点',
	'exit-node': '使用出口节点', 'login-server': '控制服务器', 'auth-key': '节点授权密钥',
	'client-id': '客户端 ID', 'client-secret': '客户端密钥', 'id-token': '身份令牌',
	'advertise-tags': '通告标签', 'force-reauth': '强制重新授权',
	'exit-node-allow-lan-access': '允许访问本地网络', 'advertise-connector': '通告应用连接器',
	'netfilter-mode': 'Netfilter 模式', 'snat-subnet-routes': '对子网路由使用 SNAT', 'stateful-filtering': '有状态过滤',
	operator: '操作用户', ssh: '启用 Tailscale SSH', 'shields-up': '屏蔽传入连接', 'accept-risk': '接受的风险',
	reset: '重置未指定设置', timeout: '命令等待时间', json: 'JSON 输出', qr: '显示登录二维码', 'qr-format': '二维码格式'
};

function input(id, value, type) {
	const el = E('input', { id, type: type || 'text', class: 'cbi-input-text',
		autocomplete: type === 'password' ? 'new-password' : 'off', spellcheck: 'false' });
	el.value = value || '';
	return el;
}

return view.extend({
	load: function() { return Promise.all([status(), config()]); },

	render: function(data) {
		let [node, settings] = data;
		let pending = false;
		let job;
		let statusRequest = 0;
		let statusError = '';
		const writable = L.hasViewPermission();
		const stateLabel = E('span', { class: 'smallts-pill' });
		const stateHint = E('p', { class: 'smallts-hint' });
		const statusNotice = E('p', { role: 'alert' });
		const authLog = logLink('runtime', '运行日志');
		const facts = E('dl', { class: 'smallts-facts' });
		const editor = E('fieldset', { class: 'smallts-editor' });
		const message = E('p', { role: 'status' });
		const saveHint = E('p', { class: 'smallts-hint' });
		const mode = choice('smallts-mode', [['local', '本地安装'], ['tmp', '内存安装']], settings.mode);
		const automatic = E('input', { id: 'smallts-auto', type: 'checkbox', class: 'cbi-input-checkbox' });
		automatic.checked = settings.auto_update;
		const policy = choice('smallts-policy', [['latest', '跟随最新'], ['pinned', '锁定版本']], settings.pinned_version ? 'pinned' : 'latest');
		const pinned = input('smallts-version', settings.pinned_version);
		pinned.placeholder = 'v1.88.3';
		const pinnedField = field('锁定版本号', pinned);
		function showVersion() { pinnedField.hidden = policy.value !== 'pinned'; }
		policy.addEventListener('change', showVersion);
		showVersion();
		const mirror = input('smallts-mirror', settings.mirror, 'url');
		const controls = {};
		const rows = {};
		for (const opt of settings.options) {
			const id = 'smallts-' + opt.key;
			const value = settings.params[opt.key] || '';
			const ctrl = opt.type === 'flag'
				? choice(id, [['', '使用默认值'], ['true', '启用'], ['false', '禁用']], value)
				: input(id, value, opt.type === 'secret' ? 'password' : 'text');
			controls[opt.key] = ctrl;
			if (opt.key !== 'advertise-routes') {
				const hint = opt.key === 'login-server' ? '更换后可能需要重新授权。' : opt.description;
				rows[opt.key] = field(labels[opt.key] || '--' + opt.key, ctrl, hint);
			}
		}
		const sections = groups.map(([, keys]) => keys.map(key => rows[key]).filter(Boolean));
		const other = Object.keys(rows).filter(key => !groups.some(([, keys]) => keys.includes(key)));
		sections[sections.length - 1].push(...other.map(key => rows[key]));
		const primary = button('', () => run(node.installed ? 'start' : 'install'), true);
		const authorize = E('a', { class: 'cbi-button cbi-button-apply', target: '_blank', rel: 'noopener noreferrer' }, ['打开授权页面']);
		const dirtyHint = E('span', { class: 'smallts-hint' }, ['此操作会先保存整张表单。']);
		const restart = button('', () => run('start'));
		const reinstall = button('', () => openReinstall());
		const maintenanceHint = E('p', { class: 'smallts-hint' }, ['带「保存并」的操作会先保存整张表单。']);
		const maintenanceToggle = E('summary', {}, ['维护操作']);
		const maintenance = E('details', { class: 'smallts-maintenance' }, [
			maintenanceToggle,
			E('div', { class: 'smallts-fold-content' }, [
				E('p', { class: 'smallts-hint' }, ['应用连接设置会运行 tailscale up。更换控制服务器后可能需要重新授权。']),
				E('p', { class: 'smallts-hint' }, ['更新或重装可能重启守护进程。保存后的安装位置在重装时生效。']),
				E('div', { class: 'smallts-actions' }, [restart, reinstall]), maintenanceHint
			])
		]);
		const dialogTitle = E('h3', { id: 'smallts-reinstall-title' });
		const dialogText = E('p');
		const cancelReinstall = button('返回', () => dialog.close());
		const confirmReinstall = button('提交安装任务', () => { dialog.close(); run('install'); }, true);
		cancelReinstall.autofocus = true;
		const dialog = E('dialog', { 'aria-labelledby': dialogTitle.id }, [
			dialogTitle, dialogText, E('div', { class: 'smallts-actions' }, [
				cancelReinstall, confirmReinstall
			])
		]);
		const jobText = E('span');
		const installLog = logLink('install', '安装与更新记录');
		const runtimeLog = logLink('runtime', '运行日志');
		const jobNotice = E('div', { class: 'smallts-notice', role: 'status' }, [jobText, installLog, runtimeLog]);
		const persist = button('保存设置', () => run());
		const routes = controls['advertise-routes'];
		let plan;
		let localRoutes;
		const savedRoutesText = E('code');
		const localRoutesText = E('code', {}, ['暂无操作结果']);
		const planList = E('ul');
		const networkNotice = E('p', { class: 'smallts-hint', role: 'status' });
		const subnetSave = button('保存设置', () => run(null, true));
		const review = button('预览网络配置', () => network(false));
		const confirm = button('应用本地规则', () => network(true));
		const clear = button('清空网段', () => {
			routes.value = '';
			routes.dispatchEvent(new Event('input', { bubbles: true }));
			routes.focus();
		});
		const savedRoutes = () => (settings.params['advertise-routes'] || '').trim();
		const draftRoutes = () => routes.value.trim();
		const canApply = () => plan?.token && plan.routes === draftRoutes() && plan.routes === savedRoutes();
		if (routes) routes.addEventListener('input', function() {
			if (plan || networkNotice.textContent) networkNotice.textContent = '网段已修改，请重新预览。';
			plan = null;
			planList.replaceChildren();
			update();
		});

		async function network(applying) {
			if (locked() || !routes || (applying && !canApply())) return;
			const requested = draftRoutes();
			const token = plan?.token;
			plan = null;
			planList.replaceChildren();
			pending = applying ? 'apply' : 'preview';
			networkNotice.textContent = applying ? '正在应用 OpenWrt 网络和防火墙规则…' : '正在读取网络和防火墙配置…';
			update();
			try {
				if (applying) {
					const result = await apply(requested, token);
					localRoutes = result.routes ? result.routes.join(', ') : requested;
					networkNotice.textContent = localRoutes ?
						'已应用 OpenWrt 本地规则。路由仍需通告并按控制端策略批准。' :
						'已移除 OpenWrt 本地转发规则。请到节点卡应用连接设置，撤回路由通告。';
				}
				else {
					const result = await preview(requested);
					plan = { routes: requested, token: result.token };
					planList.replaceChildren(...result.preview.split('\n').map(line => E('li', {}, [line])));
					networkNotice.textContent = requested === savedRoutes() ? '已预览已保存网段。请确认以下变更。' :
						'已预览表单中的草稿。保存设置会写入整张表单，之后可应用本地规则。';
				}
			}
			catch (err) {
				networkNotice.textContent = err.message + (applying && !err.message.includes('重新预览') ? ' 请重新预览。' : '');
			}
			finally { pending = false; update(); }
		}

		function draft() {
			const params = {};
			for (const [key, ctrl] of Object.entries(controls)) {
				if (ctrl.value !== '') params[key] = ctrl.value;
			}
			return {
				mode: mode.value, auto_update: automatic.checked,
				pinned_version: policy.value === 'pinned' ? pinned.value.trim() : '',
				mirror: mirror.value.trim(), params
			};
		}

		function dirty(next) {
			return Object.keys(next).some(key => key !== 'params' && next[key] !== settings[key]) ||
				Object.keys(controls).some(key => next.params[key] !== settings.params[key]);
		}

		function actionName(kind, changed) {
			const label = kind === 'install' ? (node.installed ? '更新或重装' : '下载安装') :
				(node.state === 'Running' ? '应用连接设置' : '启动并连接');
			return (changed ? '保存并' : '') + label;
		}

		function openReinstall() {
			const changed = dirty(draft());
			dialogTitle.textContent = actionName('install', changed);
			dialogText.textContent = '此操作可能重启守护进程并短暂中断连接。' + (changed ? '页面会先保存整张表单。' : '');
			dialog.showModal();
		}

		function locked() {
			return pending || job?.waiting || node.busy || statusError ||
				!writable || !['none', 'project'].includes(node.source);
		}

		function update() {
			const managed = ['none', 'project'].includes(node.source);
			const blocked = !!locked();
			const changed = dirty(draft());
			const address = managed && writable && authAddress(node);
			const waitingForAddress = managed && writable && node.state === 'NeedsLogin' && !address;
			const active = document.activeElement;
			editor.disabled = blocked;
			editor.hidden = !managed;
			if (routes) {
				const needsSave = draftRoutes() !== savedRoutes();
				savedRoutesText.textContent = savedRoutes() || '未配置';
				localRoutesText.textContent = localRoutes === undefined ? '暂无操作结果' : localRoutes || '已移除';
				review.disabled = blocked;
				confirm.disabled = blocked || !canApply();
				clear.disabled = blocked || !routes.value;
				subnetSave.hidden = !needsSave;
				subnetSave.disabled = blocked;
				review.textContent = pending === 'preview' ? '正在预览…' : '预览网络配置';
				confirm.textContent = pending === 'apply' ? '正在应用…' : '应用本地规则';
				review.classList.toggle('cbi-button-apply', !plan && !blocked);
				confirm.classList.toggle('cbi-button-apply', !confirm.disabled);
				subnetSave.classList.toggle('cbi-button-apply', !!plan && needsSave && !blocked);
			}
			persist.disabled = blocked || !changed;
			footer.hidden = !managed;
			saveHint.textContent = !writable ? '仅有读权限。' : changed ?
				'有待保存的修改。保存设置会写入整张表单。' :
				'设置已保存。连接参数通过节点卡的连接操作生效。';
			const showStart = node.installed && node.state === 'Stopped';
			primary.hidden = !managed || !writable || (node.installed && !showStart);
			primary.disabled = blocked;
			primary.textContent = actionName(node.installed ? 'start' : 'install', changed);
			dirtyHint.hidden = primary.hidden || !changed;
			authorize.hidden = !address;
			if (address) authorize.href = address;
			else authorize.removeAttribute('href');
			maintenance.hidden = !managed || !writable || !node.installed;
			restart.hidden = showStart;
			restart.disabled = reinstall.disabled = blocked;
			confirmReinstall.disabled = blocked;
			cancelReinstall.disabled = !managed;
			restart.textContent = actionName('start', changed);
			reinstall.textContent = actionName('install', changed);
			maintenanceHint.hidden = !changed;
			const notice = node.busy && !job?.waiting && !pending ? '路由器报告操作进行中。' : job?.text || '';
			jobNotice.hidden = !notice;
			if (jobText.textContent !== notice) jobText.textContent = notice;
			installLog.hidden = !job?.showLog || job.kind !== 'install';
			runtimeLog.hidden = !job?.showLog || job.kind !== 'start' || waitingForAddress;
			authLog.hidden = !waitingForAddress;
			const label = !managed ? '外部安装' : !node.installed ? '尚未安装' : states[node.state] || node.state || '未知';
			if (stateLabel.textContent !== label) stateLabel.textContent = label;
			stateLabel.dataset.state = managed ? node.state : '';
			const hint = !managed ? '请通过原安装渠道管理现有 Tailscale。如需迁移，请先备份节点状态，再处理原安装。' :
				!writable ? '当前账号仅有读取权限。可查看配置和日志。' :
				!node.installed ? '下载并安装客户端后，即可启动连接。' :
				node.state === 'NeedsLogin' ? (address ? '请打开授权页面，完成设备登录。' :
					'授权地址暂未返回。可查看运行日志，待操作空闲后重试。') : stateHints[node.state] || '';
			if (stateHint.textContent !== hint) stateHint.textContent = hint;
			const source = { none: '尚未安装', project: '本项目脚本', external: '外部安装' };
			facts.replaceChildren(
				fact('安装来源', source[node.source] || '来源未知'),
				fact('当前安装版本', E('code', {}, [node.version || (node.installed ? '未知' : '尚未安装')])),
				...(managed ? [fact('版本策略', settings.pinned_version ? '锁定 ' + settings.pinned_version : '跟随最新')] : []),
				...(node.ips?.length ? [fact('Tailscale IP', E('code', {}, [node.ips.join(' ')]))] : []),
				...(waitingForAddress ? [fact('守护进程状态', node.daemon_running == null ? '未知' : node.daemon_running ? '运行中' : '未运行')] : [])
			);
			statusNotice.hidden = !statusError;
			if (statusNotice.textContent !== statusError) statusNotice.textContent = statusError;
			if ((active === authorize && authorize.hidden) || (active === primary && primary.hidden))
				nodeTitle.focus({ preventScroll: true });
		}

		async function refresh() {
			const seq = ++statusRequest;
			let installedNow = false;
			try {
				const next = await status();
				if (seq !== statusRequest) return;
				installedNow = job?.waiting && job.kind === 'install' && !job.before.installed && next.installed;
				node = next;
				statusError = '';
				if (job?.waiting) observeJob();
			}
			catch (err) {
				if (seq !== statusRequest) return;
				statusError = '读取状态失败：' + err.message;
			}
			update();
			if (installedNow && !primary.hidden && !primary.disabled && document.activeElement === document.body)
				primary.focus({ preventScroll: true });
		}

		function observeJob() {
			let observation = '';
			if (job.kind === 'install') {
				if (!job.before.installed && node.installed)
					observation = '路由器检测到客户端已安装。接下来可启动并连接。';
				else if (node.version && node.version !== job.before.version)
					observation = '路由器当前报告安装版本为 ' + node.version + '。请查看记录确认更新或重装结果。';
			}
			else if (node.state === 'NeedsLogin' && authAddress(node))
				observation = '路由器已返回授权地址，可以继续登录。';
			else if (node.state === 'NeedsMachineAuth')
				observation = '等待控制端管理员批准此设备。';
			else if (node.state === 'Running' && job.before.state !== 'Running')
				observation = '路由器报告节点已连接。';
			job.waiting = !!node.busy;
			job.text = job.saved + (observation || (node.busy ? '路由器报告操作进行中。' : '操作已解锁，结果待确认。请查看日志，必要时重试。'));
		}

		async function run(kind, fromSubnet) {
			if (locked()) return;
			const next = draft();
			const changed = dirty(next);
			if (!changed && !kind) return;
			pending = true;
			if (changed) message.textContent = '';
			if (fromSubnet) networkNotice.textContent = '正在保存整张表单…';
			const caption = kind && actionName(kind, false);
			if (kind) job = { kind, text: changed ? '正在保存整张表单…' : '正在提交' + caption + '请求…' };
			update();
			try {
				if (changed) {
					if (policy.value === 'pinned' && !/^v\d+\.\d+\.\d+$/.test(next.pinned_version))
						throw new Error('请填写锁定版本号，例如 v1.88.3。');
					const { options, ...previous } = settings;
					await save(next.mode, next.auto_update, next.pinned_version, next.mirror, next.params, previous);
					mirror.value = next.mirror = next.mirror.replace(/\/$/, '');
					for (const opt of options) {
						if (opt.type === 'secret' && next.params[opt.key])
							controls[opt.key].value = next.params[opt.key] = '••••';
					}
					const routesChanged = routes && (next.params['advertise-routes'] || '').trim() !== savedRoutes();
					Object.assign(settings, next);
					message.textContent = '设置已保存。';
					if (fromSubnet || routesChanged)
						networkNotice.textContent = '设置已保存。' + (plan ? '可应用本地规则。' : '请预览网络配置。');
				}
				if (kind) {
					const saved = changed ? '设置已保存。' : '';
					job.text = saved + '正在提交' + caption + '请求…';
					job.before = node;
					job.showLog = true;
					update();
					await (kind === 'install' ? install : start)();
					++statusRequest;
					job.waiting = true;
					job.saved = saved;
					job.text = saved + '任务已提交，等待读取路由器状态。';
				}
			}
			catch (err) {
				if (!kind || !job.before) message.textContent = '保存失败。' + err.message;
				if (fromSubnet) networkNotice.textContent = message.textContent;
				if (kind) job.text = (job.before ? (changed ? '设置已保存。' : '') + '提交失败。' : '保存失败。') + err.message;
			}
			finally { pending = false; update(); }
		}
		networkNotice.textContent = '预览当前输入，确认将要应用的本地规则。';
		const subnetTitle = E('h3', { id: 'smallts-subnet-title' }, ['子网转发']);
		const nodeJump = E('a', { href: '#smallts-node-title', click: event => {
			event.preventDefault();
			nodeTitle.scrollIntoView();
			const target = !authorize.hidden ? authorize : !primary.hidden && !primary.disabled ? primary :
				!maintenance.hidden ? maintenanceToggle : nodeTitle;
			target.focus({ preventScroll: true });
		} }, ['返回节点操作']);
		if (routes) {
			routes.placeholder = '例如 192.0.2.0/24';
			editor.append(E('section', { class: 'cbi-section', 'aria-labelledby': subnetTitle.id }, [
				subnetTitle,
				E('p', { class: 'smallts-hint' }, ['配置要通告的网段，并预览 OpenWrt 接口和防火墙变更。']),
				E('div', { class: 'smallts-subgrid' }, [
					E('div', {}, [
						field('通告子网路由', routes, '用逗号分隔 CIDR 网段。清空后可预览移除规则。'),
						E('dl', { class: 'smallts-subfacts' }, [
							fact('已保存网段', savedRoutesText), fact('本次应用的本地规则', localRoutesText)
						]), clear
					]),
					E('div', { class: 'smallts-preview' }, [
						E('h4', {}, ['网络配置预览']), networkNotice, planList,
						E('div', { class: 'smallts-actions' }, [review, confirm, subnetSave])
					])
				]),
				E('div', { class: 'smallts-chain' }, [
					E('p', { class: 'smallts-hint' }, ['新增或更换网段时，保存网段并应用本地规则，再到节点卡应用连接设置。通告后需按控制端策略批准路由。']),
					E('p', { class: 'smallts-hint' }, ['撤回通告时，请保存空网段，再到节点卡应用连接设置。']),
					nodeJump
				])
			]));
		}
		editor.append(E('div', { class: 'smallts-settings' }, [
			section('安装设置', [
				E('p', { class: 'smallts-hint' }, ['安装位置在下次安装或重装时生效。']),
				field('安装位置', mode, '内存安装在设备重启时重新下载。'),
				E('label', { class: 'smallts-check' }, [automatic, '自动更新'])
			]), section(groups[0][0], [
				E('p', { class: 'smallts-hint' }, ['保存后，通过节点卡启动或应用连接设置。']),
				E('div', { class: 'smallts-two' }, sections[0])
			])
		]));
		const advanced = E('details', { class: 'cbi-section' }, [
			E('summary', {}, ['高级设置'])
		]);
		const advancedContent = E('div', { class: 'smallts-fold-content' }, [
			E('h4', {}, ['版本与下载']),
			E('div', { class: 'smallts-two' }, [field('版本选择', policy), pinnedField, field('下载镜像', mirror)])
		]);
		for (let i = 1; i < groups.length; i++) {
			if (sections[i].length)
				advancedContent.append(E('h4', {}, [groups[i][0]]), E('div', { class: 'smallts-two' }, sections[i]));
		}
		advanced.append(advancedContent);
		editor.append(advanced);
		const nodeTitle = E('h3', { id: 'smallts-node-title', tabindex: '-1' }, ['节点状态']);
		const footer = E('div', { class: 'cbi-section smallts-footer' }, [
			E('div', {}, [E('h3', {}, ['保存设置']), saveHint, message]), persist
		]);
		const content = E('div', { class: 'cbi-map smallts' }, [
			E('style', {}, [styles]),
			E('h2', {}, ['精简版 Tailscale']),
			E('section', { class: 'cbi-section' }, [
				E('div', { class: 'smallts-card-head' }, [nodeTitle, logLink('', '查看日志')]),
				E('div', { class: 'smallts-status', 'aria-live': 'polite' }, [stateLabel, stateHint, authLog]),
				facts, statusNotice,
				E('div', { class: 'smallts-actions' }, [primary, authorize, dirtyHint]),
				jobNotice, maintenance
			]),
			editor,
			footer, dialog
		]);
		editor.addEventListener('input', update);
		editor.addEventListener('change', update);
		update();
		poll.add(refresh, 5);
		return content;
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
