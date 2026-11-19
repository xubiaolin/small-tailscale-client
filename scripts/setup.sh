#!/bin/sh

set -e
. /etc/tailscale/tools.sh
RECORD_INSTALL_LOG=true
has_args=false
requested_mode=""
requested_update=""
requested_version=""
while [ "$#" -gt 0 ]; do
    has_args=true
    case "$1" in
        --local) requested_mode=local ;;
        --tmp) requested_mode=tmp ;;
        --auto-update) requested_update=true ;;
        --no-auto-update) requested_update=false ;;
        --version=*)
            requested_version=${1#*=}
            if [ "$requested_version" != latest ] && ! valid_version "$requested_version"; then
                log_error "无效的发布版本：$requested_version"
                exit 1
            fi
            ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
    shift
done

# 若无参数，进入交互模式
if [ "$has_args" = false ]; then
    log_info
    log_info "📮  请选择安装 Tailscale 模式："
    log_info "     1/y/Y/直接回车). 本地安装  🏠"
    log_info "     2/n/N        ). 内存安装  💻"
    log_info "     0/e/E/其他字符). 退出安装  ⛔"
    log_info "⏳  请输入选项: " 1
    read mode_input

    case "$mode_input" in
        1|"y"|"Y"|"") requested_mode="local" ;;
        2|"n"|"N") requested_mode="tmp" ;;
        *) log_error "❌  已取消安装"; exit 1 ;;
    esac

    log_info
    log_info "🔄  是否启用 Tailscale 自动更新？"
    log_info "     1/y/Y/直接回车). 启用更新  ✅"
    log_info "     2/n/N        ). 禁用更新  ❌"
    log_info "     0/e/E/其他字符). 退出安装  ⛔"
    log_info "⏳  请输入选项: " 1
    read update_input

    case "$update_input" in
        1|"y"|"Y"|"") requested_update=true ;;
        2|"n"|"N") requested_update=false ;;
        *) log_error "⛔  已取消安装"; exit 1 ;;
    esac
fi

lock_config
safe_source "$INST_CONF"
MODE=${requested_mode:-${MODE:-local}}
AUTO_UPDATE=${requested_update:-${AUTO_UPDATE:-false}}
case "$MODE" in local|tmp) ;; *) log_error "无效的安装模式：$MODE"; exit 1 ;; esac
case "$AUTO_UPDATE" in true|false) ;; *) log_error "无效的自动更新设置"; exit 1 ;; esac
case "$requested_version" in
    latest) PINNED_VERSION= ;;
    '') ;;
    *) PINNED_VERSION=$requested_version ;;
esac
version=${PINNED_VERSION:-latest}
ARCH=$(detect_arch)
HOST_NAME=$(uci -q get 'system.@system[0].hostname' || echo OpenWrt)
tmp=$(mktemp "$INST_CONF.XXXXXX")
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<EOF
# 安装配置记录
MODE=$MODE
AUTO_UPDATE=$AUTO_UPDATE
VERSION=$version
PINNED_VERSION=$PINNED_VERSION
ARCH=$ARCH
HOST_NAME=$HOST_NAME
TIMESTAMP=$(date +%s)
EOF

log_info "正在安装 $version ($MODE, $ARCH)，下载地址 $GITHUB_DOWNLOAD_BASE_URL"
"$CONFIG_DIR/fetch_and_install.sh" --mode="$MODE" --version="$version"
mv "$tmp" "$INST_CONF"
unlock_config
SMALL_TS_SKIP_START_UPDATE=1 "$CONFIG_DIR/setup_service.sh"
"$CONFIG_DIR/setup_cron.sh" --auto-update="$AUTO_UPDATE"
