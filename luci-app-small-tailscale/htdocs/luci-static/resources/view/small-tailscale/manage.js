'use strict';
'require view';
'require rpc';
'require poll';

function method(name, params, object) {
	const call = rpc.declare({ object: object || 'small-tailscale', method: name, params: params || [], reject: true });
	return async function() {
		const result = await call(...arguments);
		if (!result || result.error) throw new Error(result && result.error || '路由器未返回操作结果');
		return result;
	};
}

const status = method('status');
const config = method('config');
const save = method('save', ['mode', 'auto_update', 'pinned_version', 'mirror', 'params']);
const install = method('install');
const start = method('start');
const preview = method('preview', ['routes'], 'small-tailscale.network');
const apply = method('apply', ['routes', 'token'], 'small-tailscale.network');
const states = {
	Stopped: '已停止', Starting: '启动中', Running: '已连接', NeedsLogin: '待授权',
	NeedsMachineAuth: '等待管理员批准设备', NoState: '等待服务就绪', InUseOtherUser: '已被其他用户使用'
};

function authLink(node) {
	if (node.state !== 'NeedsLogin' || !node.auth_url) return [];
	try {
		const url = new URL(node.auth_url);
		if (['https:', 'http:'].includes(url.protocol))
			return [E('a', { href: url.href, target: '_blank', rel: 'noopener noreferrer' }, ['打开授权页面'])];
	}
	catch (_) {}
	return [];
}

function fact(label, value) {
	return E('div', { class: 'cbi-value' }, [
		E('span', { class: 'cbi-value-title' }, [label]), E('div', { class: 'cbi-value-field' }, [value])
	]);
}

function choice(id, choices, value) {
	const select = E('select', { id, class: 'cbi-input-select' }, choices.map(function(pair) {
		return E('option', { value: pair[0] }, [pair[1]]);
	}));
	select.value = value;
	return select;
}

function field(label, control, hint) {
	const children = [control];
	if (hint) children.push(E('div', { class: 'cbi-value-description' }, [hint]));
	return E('div', { class: 'cbi-value' }, [
		E('label', { for: control.id, class: 'cbi-value-title' }, [label]),
		E('div', { class: 'cbi-value-field' }, children)
	]);
}

function section(title, contents) {
	return E('div', { class: 'cbi-section' }, [E('h3', {}, [title]), ...contents]);
}

function button(label, action, primary) {
	return E('button', { type: 'button', class: 'cbi-button ' + (primary ? 'cbi-button-apply' : 'cbi-button-action'), click: action }, [label]);
}

const groups = [
	['常用设置', ['hostname', 'accept-dns', 'advertise-routes', 'accept-routes', 'advertise-exit-node', 'exit-node', 'login-server']],
	['身份与授权', ['auth-key', 'client-id', 'client-secret', 'id-token', 'advertise-tags', 'force-reauth']],
	['路由与防火墙', ['exit-node-allow-lan-access', 'advertise-connector', 'netfilter-mode', 'snat-subnet-routes', 'stateful-filtering']],
	['访问控制', ['operator', 'ssh', 'shields-up', 'accept-risk']]
];
const labels = {
	hostname: '主机名', 'accept-dns': '接受 DNS 配置', 'advertise-routes': '通告子网路由',
	'accept-routes': '接受其他节点的路由', 'advertise-exit-node': '提供出口节点',
	'exit-node': '使用出口节点', 'login-server': '控制服务器', 'auth-key': '节点授权密钥',
	'client-id': '客户端 ID', 'client-secret': '客户端密钥', 'id-token': '身份令牌'
};
const secrets = ['auth-key', 'client-secret', 'id-token'];

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
		let statusRequest = 0;
		let statusError = '';
		const summary = E('div');
		const editor = E('fieldset', { style: 'min-width:0;border:0;padding:0;margin:0' });
		const message = E('p', { role: 'status' });
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
		const sections = groups.map(() => []);
		const other = [];
		for (const opt of settings.options) {
			const id = 'smallts-' + opt.key;
			const value = settings.params[opt.key] || '';
			const ctrl = opt.type === 'flag'
				? choice(id, [['', '使用默认值'], ['true', '启用'], ['false', '禁用']], value)
				: input(id, value, secrets.includes(opt.key) ? 'password' : 'text');
			controls[opt.key] = ctrl;
			const group = groups.findIndex(g => g[1].includes(opt.key));
			const row = field(labels[opt.key] || '--' + opt.key, ctrl, opt.description);
			(group < 0 ? other : sections[group]).push(row);
		}
		const download = button('下载安装', () => run(install, '已提交下载任务，请在安装与更新记录中查看进度。'));
		const connect = button('启动并连接', () => run(start, '已提交启动任务，正在读取连接状态。'), true);
		const persist = button('保存设置', () => run(null, '设置已保存。'));
		const routes = controls['advertise-routes'];
		let token = '';
		const changes = E('pre', { role: 'status', style: 'white-space:pre-wrap;overflow-wrap:anywhere' });
		const review = button('预览网络配置', () => network(false));
		const confirm = button('应用网络配置', () => network(true), true);
		if (routes) routes.addEventListener('input', function() {
			token = '';
			changes.textContent = '';
			update();
		});

		async function network(applying) {
			if (pending || !routes || (applying && !token)) return;
			pending = true;
			update();
			try {
				const result = applying ? await apply(routes.value, token) : await preview(routes.value);
				token = applying ? '' : result.token;
				changes.textContent = result.preview;
			}
			catch (err) { token = ''; changes.textContent = err.message; }
			finally { pending = false; update(); }
		}

		function update() {
			const managed = ['none', 'project'].includes(node.source);
			const locked = pending || node.busy || statusError || !managed || !L.hasViewPermission();
			editor.disabled = locked;
			editor.hidden = !managed;
			review.disabled = locked || !routes;
			confirm.disabled = locked || !token;
			persist.disabled = download.disabled = locked;
			connect.disabled = locked || !node.installed;
			const source = { none: '尚未安装', project: '本项目脚本', external: '外部安装' };
			summary.replaceChildren(
				fact('安装来源', source[node.source] || '来源未知'),
				...(node.source === 'external' ? [E('p', { class: 'alert-message warning' }, [
					'请通过原安装渠道管理现有 Tailscale。如需迁移，请先备份节点状态，再处理原安装。'
				])] : []),
				fact('当前安装版本', node.version || (node.installed ? '未知' : '尚未安装')),
				...(managed ? [
					fact('版本策略', settings.pinned_version ? '锁定 ' + settings.pinned_version : '跟随最新'),
					fact('连接状态', states[node.state] || node.state || '未知')
				] : []),
				...(node.ips && node.ips.length ? [fact('Tailscale IP', node.ips.join(' · '))] : []),
				...authLink(node),
				...(node.busy ? [E('p', { class: 'spinning' }, ['操作进行中，可在日志页查看进度。'])] : []),
				...(statusError ? [E('p', { role: 'alert' }, [statusError])] : [])
			);
		}

		async function refresh() {
			const seq = ++statusRequest;
			try {
				const next = await status();
				if (seq !== statusRequest) return;
				node = next;
				statusError = '';
			}
			catch (err) {
				if (seq !== statusRequest) return;
				statusError = '读取状态失败：' + err.message;
			}
			update();
		}

		async function run(action, success) {
			if (pending) return;
			pending = true;
			update();
			try {
				const version = policy.value === 'pinned' ? pinned.value.trim() : '';
				if (policy.value === 'pinned' && !/^v\d+\.\d+\.\d+$/.test(version))
					throw new Error('请填写锁定版本号，例如 v1.88.3。');
				const params = {};
				for (const [key, ctrl] of Object.entries(controls)) {
					if (ctrl.value !== '') params[key] = ctrl.value;
				}
				await save(mode.value, automatic.checked, version, mirror.value.trim(), params);
				settings.pinned_version = version;
				for (const key of secrets) {
					if (params[key]) controls[key].value = '••••';
				}
				if (action) await action();
				message.textContent = success;
				await refresh();
			}
			catch (err) { message.textContent = err.message; }
			finally { pending = false; update(); }
		}
		update();
		poll.add(refresh, 5);
		editor.append(section('安装设置', [
			field('安装位置', mode, '本地安装保存在持久存储中。内存安装会在重启时重新下载。'),
			field('自动更新', automatic)
		]), section(groups[0][0], sections[0]));
		const advanced = E('details', { class: 'cbi-section' }, [
			E('summary', { style: 'cursor:pointer;font-weight:bold' }, ['高级设置']),
			E('h4', {}, ['版本与下载']), field('版本选择', policy), pinnedField, field('下载镜像', mirror)
		]);
		for (let i = 1; i < groups.length; i++) {
			if (sections[i].length) advanced.append(E('h4', {}, [groups[i][0]]), ...sections[i]);
		}
		if (other.length) advanced.append(E('h4', {}, ['命令行为与输出']), ...other);
		editor.append(advanced, section('子网转发', [
			E('p', {}, ['按上方填写的通告子网路由预览接口和防火墙变更。清空网段后可预览移除旧规则。']),
			review, changes, confirm
		]));
		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, ['精简版 Tailscale']),
			section('节点状态', [summary, E('a', { href: L.url('admin', 'services', 'small-tailscale', 'logs') }, ['查看日志'])]),
			editor,
			E('div', { class: 'cbi-page-actions' }, [persist, download, connect]), message
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
