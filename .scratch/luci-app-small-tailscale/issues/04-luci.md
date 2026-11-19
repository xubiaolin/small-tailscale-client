# LuCI 页面、菜单与 ACL

Status: resolved
Type: task
Blocked by: 01

实现原生中文 LuCI 视图、菜单和最小 ACL。使用 02、03 工单已确定的 API，随实现共同验收。覆盖首次安装、项目/外部安装、参数类别、授权、日志轮询与网络预览确认。

验收以[首版规格](../spec.md)为准。

## Answer

管理与日志视图、菜单和 ACL 已集成。8 个 Chromium 回归通过，另外在官方 OpenWrt 25.12.6 虚拟路由器中打开 LuCI，验证节点 IP、锁定版本和开机重下日志。

## Comments
