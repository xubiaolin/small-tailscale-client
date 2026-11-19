# LuCI 服务管理与日志 RPC

Status: resolved
Type: task

新增 luci-app-small-tailscale/root/usr/libexec/rpcd/small-tailscale；只处理明确数据与操作。读状态、保存配置、异步下载及授权、读取两类日志、持久脚本接入和可靠识别外部安装。安装包提供全套源脚本于 /usr/share/small-tailscale/scripts；可在项目拥有的 /etc/tailscale 中同步更新而不触碰节点状态，创建 helper 链接。与 01 约定文件格式和脚本入口见该工单。RPC status/config/save/install/start/logs，详细 JSON 协议由实现者尽早写于 /tmp/small-ts-rpc-contract.md 给 UI。

验收以[首版规格](../spec.md)为准。

## Answer

管理 RPC 已通过两代官方 rootfs 的 ubus 测试（8d9148a）。

## Comments
