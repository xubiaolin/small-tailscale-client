# 命令行与网页共用的安装、版本策略和参数

Status: claimed
Type: task

同时支持老节点、主动锁定以及开机恢复。调整 scripts/ 下已有入口，防止下载失败破坏正在运行的安装。安全无 eval 处理历史 tailscale_up.conf 的 --key="value" 行；提供 /etc/tailscale/tailscale_up_generator.sh --run 直接用共享参数执行 tailscale up，--list 输出原有参数描述清单。网页保存文件后 CLI 能读取，CLI 可明确修改版本策略与持久下载镜像。install.conf 新增 PINNED_VERSION（缺失/空沿用旧行为）。setup.sh --version=TAG 明确锁定。

验收以[首版规格](../spec.md)为准。

## Comments
