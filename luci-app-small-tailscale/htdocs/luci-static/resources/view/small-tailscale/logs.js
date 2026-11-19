'use strict';
'require view';
'require rpc';
'require poll';

const logs = rpc.declare({ object: 'small-tailscale', method: 'logs', params: ['kind'], reject: true });

function logPanel(title, kind) {
	const error = E('p', { role: 'status' });
	const output = E('pre', { tabindex: '0', 'aria-label': title,
		style: 'white-space:pre-wrap;overflow-wrap:anywhere;max-height:24rem;overflow:auto' });
	return {
		node: E('div', { class: 'cbi-section' }, [E('h3', {}, [title]), error, output]),
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
		return E('div', { class: 'cbi-map' }, [E('h2', {}, ['Tailscale 日志']), ...panels.map(panel => panel.node)]);
	},
	handleSave: null, handleSaveApply: null, handleReset: null
});
