#!/bin/sh

set -e
clear
. /etc/tailscale/tools.sh || { log_error "❌  加载 tools.sh 失败"; exit 1; }
log_info "加载公共函数..."

log_info "加载配置文件..."
safe_source "$INST_CONF" || log_warn "⚠️  INST_CONF 未找到或无效，使用默认配置"

# 默认值
MODE=""
AUTO_UPDATE=""
VERSION="latest"
ARCH=$(detect_arch)
HOST_NAME=$(uci show system.@system[0].hostname | awk -F"'" '{print $2}')

has_args=false  # 🔧  新增：标记是否传入了参数

# 若有参数, 接受 --tmp为使用内存模式, --auto-update为自动更新
while [ $# -gt 0 ]; do
    has_args=true  # 🔧  有参数，关闭交互模式
    case "$1" in
        --tmp) MODE="tmp"; shift ;;
        --auto-update) AUTO_UPDATE=true; shift ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
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
        1|"y"|"Y"|"") MODE="local" ;;
        2|"n"|"N") MODE="tmp" ;;
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
        1|"y"|"Y"|"") AUTO_UPDATE=true ;;
        2|"n"|"N") AUTO_UPDATE=false ;;
        *) log_error "⛔  已取消安装"; exit 1 ;;
    esac
fi


# 兜底
MODE=${MODE:-local}
AUTO_UPDATE=${AUTO_UPDATE:-false}
VERSION=${VERSION:-latest}

cat > "$INST_CONF" <<EOF
# 安装配置记录
MODE=$MODE
AUTO_UPDATE=$AUTO_UPDATE
VERSION=$VERSION
ARCH=$ARCH
HOST_NAME=$HOST_NAME
TIMESTAMP=$(date +%s)
EOF

# 显示当前配置
echo
log_info "🎯  当前安装配置："
log_info "🎯  模式: $MODE"
log_info "🎯  更新: $AUTO_UPDATE"
log_info "🎯  版本: $VERSION"
log_info "🎯  架构: $ARCH"
log_info "🎯  昵称: $HOST_NAME"
log_info "🎯  GitHub 下载地址: $GITHUB_DOWNLOAD_BASE_URL"

echo

# 停止服务之前，检查服务文件是否存在
if [ -f /etc/init.d/tailscale ]; then
    log_info "🔴  停止 tailscaled 服务..."
    /etc/init.d/tailscale stop 2>/dev/null || log_warn "⚠️  停止 tailscaled 服务失败，继续清理残留文件"
else
    log_warn "⚠️  未找到 tailscale 服务文件，跳过停止服务步骤"
fi

# 清理残留文件
log_info "🧹  清理残留文件..."
if [ "$MODE" = "local" ]; then
    log_info "🗑️  删除本地安装的残留文件..."
    rm -f /usr/local/bin/tailscale
    rm -f /usr/local/bin/tailscaled
fi

if [ "$MODE" = "tmp" ]; then
    log_info "🗑️  删除/tmp中的残留文件..."
    rm -f /tmp/tailscale
    rm -f /tmp/tailscaled
fi

# 安装开始
log_info "🚀  开始安装 Tailscale..."
"$CONFIG_DIR/fetch_and_install.sh" \
    --mode="$MODE" \
    --version="$VERSION"

# 初始化服务
log_info "🛠️  初始化服务..."
"$CONFIG_DIR/setup_service.sh" --mode="$MODE"

# 设置定时任务
log_info "⏰  设置定时任务..."
"$CONFIG_DIR/setup_cron.sh" --auto-update="$AUTO_UPDATE"
