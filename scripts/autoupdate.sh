#!/bin/sh

. /etc/tailscale/tools.sh
safe_source "$INST_CONF"

case "$MODE" in
    local) binary=/usr/local/bin/tailscaled ;;
    tmp)   binary=/tmp/tailscaled ;;
    *) log_error "❌  未配置有效的安装模式"; exit 1 ;;
esac

if [ "$AUTO_UPDATE" != "true" ] && [ -x "$binary" ]; then
    log_info "✅  自动更新已关闭，直接使用已安装的 tailscaled"
    exit 0
fi

recorded=""
[ ! -s "$VERSION_FILE" ] || recorded=$(cat "$VERSION_FILE")

if [ "$AUTO_UPDATE" = "true" ]; then
    if ! version=$("$CONFIG_DIR/fetch_and_install.sh" --dry-run) || [ -z "$version" ]; then
        log_error "❌  无法查询 Tailscale 最新版本"
        if should_notify "emergency"; then
            send_notify "❌  Tailscale 更新失败" "无法查询最新版本，请检查网络连接"
        fi
        exit 1
    fi
    if [ "$version" = "$recorded" ] && [ -x "$binary" ]; then
        log_info "✅  已安装最新版 $version"
        exit 0
    fi
else
    # 自动更新关闭时，补回上次安装的版本。旧记录可能只写了 latest。
    case "$recorded" in
        ""|latest) version=${VERSION:-latest} ;;
        *) version=$recorded ;;
    esac
fi

log_info "📥  正在安装 Tailscale $version ($MODE)..."
if ! "$CONFIG_DIR/fetch_and_install.sh" --version="$version" --mode="$MODE"; then
    log_error "❌  Tailscale $version 安装失败"
    if should_notify "emergency"; then
        send_notify "❌  Tailscale 安装失败" "版本 $version 安装失败，请检查日志"
    fi
    exit 1
fi

# fetch_and_install.sh 已记录实际安装的 tag。
if [ "$AUTO_UPDATE" = "true" ]; then
    if [ "${1:-}" != "--on-start" ]; then
        /etc/init.d/tailscale restart || {
            log_error "❌  重启服务失败，将启动服务"
            /etc/init.d/tailscale start >/dev/null 2>&1 &
        }
    fi
    if should_notify "update"; then
        send_notify "✅  Tailscale 已更新" "已安装版本 $version"
    fi
fi
