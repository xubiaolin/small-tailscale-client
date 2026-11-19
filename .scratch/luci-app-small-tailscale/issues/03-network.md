# 子网转发预览与显式应用

Status: claimed
Type: task

新增独立 RPC small-tailscale.network（路径 luci-app-small-tailscale/root/usr/libexec/rpcd/small-tailscale.network），preview(routes:string) / apply(routes:string, token:string) 返回 {preview:string,token:string} 或 {error:string}。只允许从 tailscale0 到所选网段的转发、保留已有路由器管理访问。考虑重复应用、变更网段、既有接口/区冲突和失败。直接 RPC 也须拒绝外部安装的应用请求。

验收以[首版规格](../spec.md)为准。

## Comments
