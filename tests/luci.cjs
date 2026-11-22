// 在开发机为测试安装浏览器依赖：
// npm install --prefix /tmp/smallts-browser playwright
// /tmp/smallts-browser/node_modules/.bin/playwright install chromium
// NODE_PATH=/tmp/smallts-browser/node_modules node --test tests/luci.cjs
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { chromium } = require('playwright');

const root = path.join(__dirname, '..');
const resources = path.join(root, 'luci-app-small-tailscale/htdocs/luci-static/resources/view/small-tailscale');
const options = execFileSync('sh', [path.join(root, 'scripts/tailscale_up_generator.sh'), '--list'], { encoding: 'utf8' })
	.trim().split('\n').map(line => {
		const [, key, type, description] = line.match(/^--([\w-]+):(flag|value|secret):(.+)$/);
		return { key, type, description };
	});
let browser;
before(async () => { browser = await chromium.launch(); });
after(async () => { await browser?.close(); });

async function openView(t, name, replies = {}, writable = true) {
	const source = readFileSync(path.join(resources, name + '.js'), 'utf8');
	const page = await browser.newPage({ viewport: { width: 375, height: 812 } });
	page.setDefaultTimeout(1800);
	t.after(() => page.close());
	const state = Object.assign({
		status: { source: 'none', installed: false, state: 'Stopped', ips: [], version: '', busy: false },
		config: { mode: 'local', pinned_version: '', mirror: 'https://github.com', auto_update: false, params: {}, options }
	}, replies);
	await page.evaluate(async ({ source, state, writable }) => {
		window.replies = state;
		window.calls = [];
		const callbacks = [];
		window.refresh = () => Promise.all(callbacks.map(fn => fn()));
		// LuCI 提供模块加载、E()、定时轮询及 ubus 传输。页面逻辑与控件在真实浏览器中运行。
		function E(tag, attrs, children) {
			const node = document.createElement(tag);
			for (const [key, value] of Object.entries(attrs || {})) {
				if (typeof value === 'function') node.addEventListener(key, value);
				else if (value != null) node.setAttribute(key, value);
			}
			if (Array.isArray(children)) node.append(...children);
			else if (children instanceof Node) node.append(children);
			else if (children != null) node.innerHTML = children;
			return node;
		}
		const rpc = { declare(spec) {
			return async (...args) => {
				const data = Object.fromEntries((spec.params || []).map((p, i) => [p, args[i]]));
				window.calls.push({ object: spec.object, method: spec.method, data: structuredClone(data) });
				const reply = window.replies[spec.method === 'status_auth' ? 'status' : spec.method];
				return structuredClone(spec.method === 'logs' ? reply[data.kind] : (reply || { ok: true }));
			};
		} };
		const poll = { add: fn => callbacks.push(fn) };
		const view = { extend: opts => opts };
		const L = { hasViewPermission: () => writable, url: (...parts) => '/' + parts.join('/') };
		const app = Function('view', 'rpc', 'poll', 'E', 'L', source)(view, rpc, poll, E, L);
		document.body.append(await app.render(app.load ? await app.load() : undefined));
	}, { source, state, writable });
	return page;
}

test('首次下载先保存安装选择，任务解锁后以路由器实际报告为准', async t => {
	const page = await openView(t, 'manage');
	assert.equal(await page.getByLabel('安装位置').inputValue(), 'local');
	assert.ok(await page.getByText('跟随最新', { exact: true }).first().count());
	const start = page.getByRole('button', { name: '启动并连接' });
	assert.equal(await start.count(), 0);
	await page.getByLabel('安装位置').selectOption('tmp');
	const download = page.getByRole('button', { name: '保存并下载安装', exact: true });
	await download.click();
	const calls = await page.evaluate(() => window.calls.filter(x => ['install', 'save', 'start'].includes(x.method)));
	assert.deepEqual(calls.map(x => x.method), ['save', 'install']);
	assert.equal(calls[0].data.mode, 'tmp');
	assert.equal(calls[0].data.pinned_version, '');
	assert.ok(await page.getByText(/任务已提交/).isVisible());
	assert.ok(await page.getByRole('button', { name: '下载安装', exact: true }).isDisabled());
	await page.evaluate(async () => {
		Object.assign(window.replies.status, { busy: true });
		await window.refresh();
	});
	assert.ok(await page.getByText(/路由器报告操作进行中/).isVisible());
	await page.evaluate(async () => {
		Object.assign(window.replies.status, { busy: false, source: 'project', installed: true, version: 'v1.92.3' });
		await window.refresh();
	});
	assert.ok(await start.isEnabled());
	assert.ok(await page.getByText(/路由器检测到客户端已安装/).isVisible());
});

test('项目节点保留实际版本，从待授权轮询至已连接，并显示 Tailscale IP', async t => {
	const page = await openView(t, 'manage', {
		status: { source: 'project', installed: true, state: 'Stopped', version: 'v1.92.3', ips: [] }
	});
	assert.ok(await page.getByText('v1.92.3', { exact: true }).count());
	await page.getByRole('button', { name: '启动并连接' }).click();
	assert.deepEqual(await page.evaluate(() => window.calls.filter(x => ['install', 'start', 'save'].includes(x.method)).map(x => x.method)), ['start']);
	await page.evaluate(async () => {
		Object.assign(window.replies.status, { busy: true, state: 'NeedsLogin', auth_url: 'https://login.example.test/a' });
		await window.refresh();
	});
	assert.equal(await page.getByRole('link', { name: '打开授权页面' }).getAttribute('href'), 'https://login.example.test/a');
	assert.ok(await page.getByRole('button', { name: '保存设置' }).isDisabled());
	await page.evaluate(async () => {
		Object.assign(window.replies.status, { busy: false, state: 'Running', auth_url: '', ips: ['100.101.102.103'] });
		await window.refresh();
	});
	assert.equal(await page.getByRole('link', { name: '打开授权页面' }).count(), 0);
	assert.ok(await page.getByText('100.101.102.103', { exact: true }).isVisible());
	assert.ok(await page.getByText('已连接', { exact: true }).isVisible());
});

test('网页未修改时直接使用设备的最新设置，旧页面提交冲突后保留输入', async t => {
	const page = await openView(t, 'manage', { save: { error: '设置已由其他入口修改，请刷新页面后重新保存。' } });
	await page.evaluate(() => { window.replies.config = { ...window.replies.config, mirror: 'https://cli.example' }; });
	await page.getByRole('button', { name: '下载安装', exact: true }).click();
	assert.deepEqual(await page.evaluate(() => window.calls.filter(x => ['save', 'install'].includes(x.method)).map(x => x.method)), ['install']);
	await page.evaluate(() => window.refresh());
	assert.ok(await page.getByText(/结果待确认/).isVisible());
	await page.getByLabel('主机名', { exact: true }).fill('updated');
	await page.getByRole('button', { name: '保存并下载安装', exact: true }).click();
	assert.ok(await page.getByText(/设置已由其他入口修改/).first().isVisible());
	assert.equal(await page.getByLabel('主机名', { exact: true }).inputValue(), 'updated');
	assert.deepEqual(await page.evaluate(() => window.calls.filter(x => ['save', 'install'].includes(x.method)).map(x => x.method)), ['install', 'save']);
	assert.equal(await page.evaluate(() => window.calls.find(x => x.method === 'save').data.previous.mirror), 'https://github.com');
});

test('已连接时在维护操作中确认重装，先保存并保留任务提交错误，可按原设置重试', async t => {
	const page = await openView(t, 'manage', {
		status: { source: 'project', installed: true, state: 'Running', version: 'v1.92.3', ips: [] },
		install: { error: '无法启动任务' }
	});
	await page.getByLabel('主机名', { exact: true }).fill('router12');
	assert.equal(await page.getByRole('button', { name: '保存并更新或重装' }).count(), 0);
	await page.getByText('维护操作', { exact: true }).click();
	const reinstall = page.getByRole('button', { name: '保存并更新或重装' });
	await reinstall.click();
	const dialog = page.getByRole('dialog');
	assert.ok(await dialog.getByText(/短暂中断连接/).isVisible());
	assert.ok(await dialog.getByRole('button', { name: '返回' }).evaluate(el => el === document.activeElement));
	await page.keyboard.press('Escape');
	assert.ok(await reinstall.evaluate(el => el === document.activeElement));
	await reinstall.click();
	await dialog.getByRole('button', { name: '提交安装任务' }).click();
	assert.ok(await page.getByText(/设置已保存。提交失败。无法启动任务/).isVisible());
	await page.evaluate(() => { window.replies.install = { ok: true }; });
	await page.getByRole('button', { name: '更新或重装', exact: true }).click();
	await dialog.getByRole('button', { name: '提交安装任务' }).click();
	await page.evaluate(() => window.refresh());
	assert.ok(await page.getByText(/结果待确认/).isVisible());
	assert.match(await page.getByRole('link', { name: '安装与更新记录' }).getAttribute('href'), /#log-install$/);
	assert.deepEqual(await page.evaluate(() => window.calls.filter(x => ['save', 'install'].includes(x.method)).map(x => x.method)),
		['save', 'install', 'install']);
	await page.getByRole('button', { name: '应用连接设置' }).click();
	await page.evaluate(() => window.refresh());
	assert.ok(await page.getByText(/结果待确认/).isVisible());
	assert.match(await page.getByRole('link', { name: '运行日志' }).getAttribute('href'), /#log-runtime$/);
});

test('待授权无地址时显示守护进程状态和日志，有地址时可授权并看到批准状态', async t => {
	const page = await openView(t, 'manage', {
		status: { source: 'project', installed: true, state: 'NeedsLogin', version: 'v1.92.3', daemon_running: true, auth_url: '' }
	});
	assert.ok(await page.getByText(/授权地址暂未返回/).isVisible());
	assert.ok(await page.getByText('运行中', { exact: true }).isVisible());
	assert.match(await page.getByRole('link', { name: '运行日志' }).getAttribute('href'), /#log-runtime$/);
	await page.getByText('维护操作', { exact: true }).click();
	assert.ok(await page.getByRole('button', { name: '启动并连接' }).isEnabled());
	await page.evaluate(async () => {
		window.replies.status.auth_url = 'https://login.example.test/a';
		window.replies.status.busy = true;
		await window.refresh();
	});
	const auth = page.getByRole('link', { name: '打开授权页面' });
	assert.equal(await auth.getAttribute('target'), '_blank');
	await auth.focus();
	await page.evaluate(async () => {
		window.replies.status.state = 'NeedsMachineAuth';
		await window.refresh();
	});
	assert.ok(await page.getByText('等待管理员批准', { exact: true }).isVisible());
	assert.ok(await page.getByRole('heading', { name: '节点状态' }).evaluate(el => el === document.activeElement));
});

test('外部安装只显示来源和原渠道管理指引，所有写操作均不可用', async t => {
	const page = await openView(t, 'manage', { status: { source: 'external', installed: true, state: 'Stopped', ips: [] } });
	assert.ok(await page.getByText(/请通过原安装渠道/).isVisible());
	assert.equal(await page.locator('button:enabled').count(), 0);
	assert.equal(await page.getByText('已停止', { exact: true }).count(), 0);
	assert.ok(await page.getByRole('link', { name: '查看日志' }).isVisible());
	assert.equal(await page.getByLabel('安装位置').isEnabled(), false);
	assert.deepEqual(await page.evaluate(() => window.calls.map(x => x.method)), ['status_auth', 'config']);
});

test('共享设置按用途展示，保存版本锁定、镜像和授权参数后可恢复跟随最新', async t => {
	const page = await openView(t, 'manage', { config: {
		mode: 'tmp', auto_update: true, pinned_version: '', mirror: 'https://mirror.example', options,
		params: { 'auth-key': '••••', 'accept-dns': 'false' }
	} });
	for (const label of ['主机名', '接受 DNS 配置', '通告子网路由', '使用出口节点', '控制服务器']) {
		assert.ok(await page.getByLabel(label, { exact: true }).isVisible());
	}
	await page.getByLabel('主机名', { exact: true }).fill('home-router');
	assert.equal(await page.getByLabel('接受 DNS 配置').inputValue(), 'false');
	await page.getByText('高级设置', { exact: true }).click();
	assert.equal(await page.getByLabel('下载镜像').inputValue(), 'https://mirror.example');
	assert.equal(await page.getByLabel('节点授权密钥').getAttribute('type'), 'password');
	assert.equal(await page.getByLabel('节点授权密钥').inputValue(), '••••');
	await page.getByLabel('版本选择').selectOption('pinned');
	await page.getByLabel('锁定版本号').fill('v1.88.3');
	await page.getByLabel('节点授权密钥').fill('test-key');
	await page.getByRole('button', { name: '保存设置' }).click();
	let saved = await page.evaluate(() => window.calls.filter(x => x.method === 'save').at(-1).data);
	assert.deepEqual(saved.params, { hostname: 'home-router', 'auth-key': 'test-key', 'accept-dns': 'false' });
	assert.equal(saved.pinned_version, 'v1.88.3');
	assert.ok(await page.getByText('锁定 v1.88.3', { exact: true }).isVisible());
	assert.equal(await page.getByLabel('节点授权密钥').inputValue(), '••••');
	await page.getByLabel('版本选择').selectOption('latest');
	await page.getByRole('button', { name: '保存设置' }).click();
	saved = await page.evaluate(() => window.calls.filter(x => x.method === 'save').at(-1).data);
	assert.equal(saved.pinned_version, '');
	assert.equal(saved.params['auth-key'], '••••');
});

test('子网预览读取草稿，应用须先保存，失败后重新预览并可清空规则', async t => {
	const page = await openView(t, 'manage', {
		preview: { preview: '仅允许转发至 192.168.1.0/24。', token: 'first' },
		apply: { error: '系统配置已变化，请重新预览。' }
	});
	const routes = page.getByLabel('通告子网路由');
	const preview = page.getByRole('button', { name: '预览网络配置' });
	const apply = page.getByRole('button', { name: '应用本地规则' });
	await routes.fill('192.168.1.0/24');
	assert.ok(await apply.isDisabled());
	await preview.click();
	assert.ok(await apply.isDisabled());
	assert.ok(await page.getByText('仅允许转发至 192.168.1.0/24。', { exact: true }).isVisible());
	assert.deepEqual(await page.evaluate(() => window.calls.filter(x => x.object.endsWith('.network')).map(x => x.method)), ['preview']);
	await routes.fill('10.0.0.0/8');
	assert.ok(await apply.isDisabled());
	await page.evaluate(() => Object.assign(window.replies.preview, { preview: '仅允许转发至 10.0.0.0/8。', token: 'second' }));
	await preview.click();
	const subnet = page.getByRole('region', { name: '子网转发' });
	await subnet.getByRole('button', { name: '保存设置' }).click();
	assert.ok(await subnet.getByText('10.0.0.0/8', { exact: true }).isVisible());
	await apply.click();
	assert.ok(await page.getByText('系统配置已变化，请重新预览。').isVisible());
	assert.ok(await apply.isDisabled());
	assert.deepEqual(await page.evaluate(() => window.calls.find(x => x.method === 'apply').data), { routes: '10.0.0.0/8', token: 'second' });
	await page.evaluate(() => { window.replies.apply = { preview: '已应用网络配置。', routes: ['10.0.0.0/8'] }; });
	await preview.click();
	await apply.click();
	assert.ok(await subnet.getByText(/已应用 OpenWrt 本地规则/).isVisible());
	await subnet.getByRole('button', { name: '清空网段' }).click();
	assert.equal(await routes.inputValue(), '');
	assert.ok(await routes.evaluate(el => el === document.activeElement));
	await page.evaluate(() => {
		window.replies.preview = { preview: '清除插件管理的子网转发规则。', token: 'empty' };
		window.replies.apply = { preview: '已应用网络配置。', routes: [] };
	});
	await preview.click();
	assert.ok(await apply.isDisabled());
	await subnet.getByRole('button', { name: '保存设置' }).click();
	await apply.click();
	assert.ok(await subnet.getByText('已移除', { exact: true }).isVisible());
	assert.ok(await subnet.getByText(/撤回路由通告/).isVisible());
	assert.deepEqual(await page.evaluate(() => window.calls.filter(x => x.method === 'apply').at(-1).data), { routes: '', token: 'empty' });
});

test('服务尚未启动也能读取安装失败记录，两类日志独立更新并按文本展示', async t => {
	const page = await openView(t, 'logs', { logs: {
		runtime: { text: '' }, install: { text: '下载失败：文件不可用 <tag>' }
	} });
	assert.ok(await page.getByText('下载失败：文件不可用 <tag>', { exact: true }).isVisible());
	await page.evaluate(async () => {
		window.replies.logs = { runtime: { text: 'tailscaled 已启动' }, install: { error: '读取失败' } };
		await window.refresh();
	});
	assert.ok(await page.getByText('tailscaled 已启动', { exact: true }).isVisible());
	assert.ok(await page.getByText('读取失败', { exact: true }).isVisible());
	assert.ok(await page.getByText('下载失败：文件不可用 <tag>', { exact: true }).isVisible());
});

test('服务菜单进入节点管理与日志，只读用户可查看配置且不能启动写操作', async t => {
	const share = path.join(root, 'luci-app-small-tailscale/root/usr/share');
	const menu = JSON.parse(readFileSync(path.join(share, 'luci/menu.d/luci-app-small-tailscale.json')));
	const prefix = 'admin/services/small-tailscale';
	assert.equal(menu[prefix].action.type, 'firstchild');
	assert.deepEqual(menu[prefix].depends.acl, ['luci-app-small-tailscale']);
	for (const name of ['manage', 'logs']) assert.equal(menu[prefix + '/' + name].action.path, 'small-tailscale/' + name);
	const acl = JSON.parse(readFileSync(path.join(share, 'rpcd/acl.d/luci-app-small-tailscale.json')))['luci-app-small-tailscale'];
	assert.deepEqual(acl.read, { ubus: { 'small-tailscale': ['status', 'config', 'logs'], 'small-tailscale.network': ['preview'] } });
	assert.deepEqual(acl.write, { ubus: { 'small-tailscale': ['save', 'install', 'start', 'status_auth'], 'small-tailscale.network': ['apply'] } });
	const page = await openView(t, 'manage', {status: {source: 'project', installed: true, state: 'NeedsLogin', auth_url: 'https://login.example/a'}}, false);
	assert.deepEqual(await page.evaluate(() => window.calls.map(x => x.method)), ['status', 'config']);
	assert.equal(await page.getByRole('link', { name: '打开授权页面' }).count(), 0);
	assert.ok(await page.getByRole('button', { name: '保存设置' }).isDisabled());
	assert.equal(await page.getByRole('button', { name: '下载安装' }).count(), 0);
});
