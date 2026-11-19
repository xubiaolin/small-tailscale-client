#!/bin/sh
set -e
. /etc/tailscale/tools.sh

lock_config
"$CONFIG_DIR/source.sh" --require-project
log_info "🛑  开始卸载 Tailscale"
network=/usr/libexec/rpcd/small-tailscale.network
saved_cleanup=/usr/libexec/small-tailscale-network-cleanup
if [ ! -x "$network" ]; then network=$saved_cleanup; fi
if [ -x "$network" ]; then
    "$network" cleanup || { log_error "无法清理项目网络配置，请查看错误后重试"; exit 1; }
    rm -f "$saved_cleanup"
fi

if [ -f /etc/init.d/tailscale ]; then
    /etc/init.d/tailscale stop
    /etc/init.d/tailscale disable
    rm -f /etc/init.d/tailscale
fi

"$CONFIG_DIR/setup_cron.sh" --remove
for link in /usr/bin/tailscale /usr/bin/tailscaled; do
    binary=$(readlink "$link" || :)
    case "$binary" in /usr/local/bin/tailscaled|/tmp/tailscaled) rm -f "$link" "$binary" ;; esac
done
rm -f /etc/config/tailscaled.state "$VERSION_FILE" "$RESTART_PENDING"
log_info "Tailscale 已卸载。可用 tailscale-helper 重新安装。"
