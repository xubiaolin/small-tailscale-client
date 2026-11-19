#!/bin/sh

. /etc/tailscale/tools.sh
RECORD_INSTALL_LOG=true
reason=${1:-}
case "$reason" in ''|--manual|--on-start) ;; *) exit 1 ;; esac
lock_config || exit 1
safe_source "$INST_CONF"

case "$MODE" in
    local) binary=/usr/local/bin/tailscaled ;;
    tmp)   binary=/tmp/tailscaled ;;
    *) log_error "❌  未配置有效的安装模式"; exit 1 ;;
esac
recorded=$(cat "$VERSION_FILE" 2>/dev/null)
if [ "$reason" != --manual ] && [ "$AUTO_UPDATE" != true ] && [ -x "$binary" ]; then
    log_info "自动更新已关闭，使用当前版本"
    exit 0
fi

if [ -n "$PINNED_VERSION" ]; then
    version=$PINNED_VERSION
elif [ "$AUTO_UPDATE" = true ] || [ "$reason" = --manual ]; then
    version=latest
else
    # 旧节点关闭自动更新时，内存安装应补回最后实际安装的版本。
    case "$recorded" in ''|latest) version=${VERSION:-latest} ;; *) version=$recorded ;; esac
fi
if [ "$version" = latest ]; then
    version=$("$CONFIG_DIR/fetch_and_install.sh" --dry-run) || {
        log_error "无法查询 Tailscale 最新版本"
        if should_notify emergency; then send_notify "Tailscale 更新失败" "无法查询最新版本"; fi
        exit 1
    }
fi
if [ "$version" = "$recorded" ] && [ -x "$binary" ]; then
    log_info "已安装目标版本 $version"
    exit 0
fi

log_info "正在安装 Tailscale $version ($MODE)"
if ! "$CONFIG_DIR/fetch_and_install.sh" --version="$version" --mode="$MODE"; then
    log_error "Tailscale $version 安装失败"
    if should_notify emergency; then send_notify "Tailscale 安装失败" "版本 $version 安装失败，请检查日志"; fi
    exit 1
fi
unlock_config
if [ "$reason" != --on-start ] && [ -x /etc/init.d/tailscale ]; then
    SMALL_TS_SKIP_START_UPDATE=1 /etc/init.d/tailscale restart || { log_error "重启服务失败"; exit 1; }
fi
if should_notify update; then send_notify "Tailscale 已更新" "已安装版本 $version"; fi
