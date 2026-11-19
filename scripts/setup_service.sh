#!/bin/sh
set -e
. /etc/tailscale/tools.sh

# --refresh 供接入老节点时使用，仅替换本项目生成的启动脚本。
init=/etc/init.d/tailscale
tmp=$(mktemp "$init.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<'EOF'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=90
STOP=1

. /etc/tailscale/tools.sh

start_service() {
    safe_source "$INST_CONF"
    local binary
    case "$MODE" in
        local) binary=/usr/local/bin/tailscaled ;;
        tmp) binary=/tmp/tailscaled ;;
        *) log_error "未配置有效的安装模式"; return 1 ;;
    esac

    if [ "${SMALL_TS_SKIP_START_UPDATE:-}" != 1 ]; then
        # 由本次 start_service 完成启动；即使更新失败，也可继续启动现有程序。
        "$CONFIG_DIR/autoupdate.sh" --on-start || log_warn "开机更新失败，请查看安装日志"
    fi
    [ -x "$binary" ] || { log_error "找不到 $binary"; return 1; }
    "$binary" --cleanup >/dev/null 2>&1 || true
    procd_open_instance
    procd_set_param name tailscale
    procd_set_param env TS_DEBUG_FIREWALL_MODE=auto
    procd_set_param command "$binary" --port 41641 --state /etc/config/tailscaled.state
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    if [ -x /usr/bin/tailscaled ]; then /usr/bin/tailscaled --cleanup >/dev/null 2>&1 || true; fi
}
EOF
chmod 755 "$tmp"
mv "$tmp" "$init"
[ "${1:-}" != --refresh ] || exit 0
"$init" enable
"$init" restart
log_info "Tailscale 服务已启动"
