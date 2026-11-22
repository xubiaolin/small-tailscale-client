'use strict';
'require view';
'require rpc';
'require poll';

const logs = rpc.declare({ object: 'small-tailscale', method: 'logs', params: ['kind'], reject: true });
const styles = `
.smallts-logs .smallts-log-head {
	display: flex;
	flex-wrap: wrap;
	align-items: center;
	justify-content: space-between;
	gap: 8px 12px;
	padding: 12px 16px;
}
.smallts-logs .smallts-log-head h3 { width: auto; padding: 0; margin: 0; background: none; line-height: 1.4; }
.smallts-logs :focus-visible { outline: 2px solid var(--primary, #4c58cf); outline-offset: 3px; }
`;

function logPanel(title, kind) {
	const error = E('p', { role: 'status' });
	const heading = E('h3', { id: 'log-' + kind + '-title', tabindex: '-1' }, [title]);
	const output = E('pre', { tabindex: '0', 'aria-labelledby': heading.id,
		style: 'white-space:pre-wrap;overflow-wrap:anywhere;max-height:24rem;overflow:auto' });
	return {
		node: E('section', { class: 'cbi-section', id: 'log-' + kind, 'aria-labelledby': heading.id }, [
			E('div', { class: 'smallts-log-head' }, [
				heading, E('a', { href: L.url('admin', 'services', 'small-tailscale', 'manage') }, ['返回节点管理'])
			]),
			error, output
		]),
		focus() {
			heading.focus({ preventScroll: true });
			this.node.scrollIntoView();
		},
		async refresh() {
			try {
				const result = await logs(kind);
				if (!result || result.error) throw new Error(result && result.error || '无法读取日志');
				const value = result.text || '暂无记录';
				if (output.textContent !== value) {
					const atEnd = output.scrollHeight - output.scrollTop - output.clientHeight <= 1;
					output.textContent = value;
					if (atEnd) output.scrollTop = output.scrollHeight;
				}
				error.textContent = '';
			}
			catch (err) { error.textContent = err.message; }
		}
	};
}

return view.extend({
	async render() {
		const panels = [logPanel('安装与更新记录', 'install'), logPanel('运行日志', 'runtime')];
		const refresh = () => Promise.all(panels.map(panel => panel.refresh()));
		await refresh();
		poll.add(refresh, 5);
		const focusLog = () => panels.find(panel => '#' + panel.node.id === location.hash)?.focus();
		window.addEventListener('hashchange', focusLog);
		requestAnimationFrame(focusLog);
		return E('div', { class: 'cbi-map smallts-logs' }, [
			E('style', {}, [styles]), E('h2', {}, ['Tailscale 日志']), ...panels.map(panel => panel.node)
		]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
