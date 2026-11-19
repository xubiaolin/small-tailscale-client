#!/bin/sh

set -o pipefail

SCRIPT_VERSION="v1.2.3"

# 检查并引入 /etc/tailscale/tools.sh 文件
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh
safe_source "$INST_CONF"
ensure_arch || exit 1

INSTALL_SCRIPT_URL_SUFFIX="xubiaolin/small-tailscale-client/raw/refs/heads/main/install.sh"

# 显示菜单
show_menu() {
    log_info "🎉  欢迎使用 Tailscale on OpenWRT 管理脚本 $SCRIPT_VERSION"
    log_info "------------------------------------------"
    log_info "      1).  💾 安装 / 重装 Tailscale"
    log_info "------------------------------------------"
    log_info "      2).  📥 登录 Tailscale"
    log_info "      3).  📝 生成 Tailscale 启动命令"  # 新增选项
    log_info "      4).  📤 登出 Tailscale"
    log_info "      5).  ❌ 卸载 Tailscale"
    log_info "------------------------------------------"
    log_info "      6).  🔄 配置自动更新和版本策略"
    log_info "      7).  🔄 手动运行更新脚本"
    log_info "      8).  🌐 设置 GitHub 下载地址"
    log_info "      9).  📦 查看本地 Tailscale 存在版本"
    log_info "     10).  📦 查看远程 Tailscale 最新版本"
    log_info "     11).  🔔 管理推送通知"
    log_info "     12).  📊 测试配置的下载镜像"
    log_info "     13).  🛠️ 更新脚本包"
    log_info "     14).  📜 显示 Tailscale 更新日志"
    log_info "------------------------------------------"
    log_info "      0).  ⛔ 退出"
    log_info "------------------------------------------"
}

# 处理用户选择
handle_choice() {
    case $1 in
        1)
            $CONFIG_DIR/setup.sh
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        2)
            if ! command -v tailscale >/dev/null 2>&1; then
                log_error "❌  tailscale 未安装或命令未找到"
                log_error "📦  请先安装 tailscale 后再运行本脚本"
            else
                log_info "正在启动 Tailscale，请按提示打开授权链接"
                "$CONFIG_DIR/tailscale_up_generator.sh" --run || log_error "Tailscale 登录失败"
            fi
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        3)  
            $CONFIG_DIR/tailscale_up_generator.sh
            ;;
        4)
            if ! command -v tailscale >/dev/null 2>&1; then
                log_error "❌  tailscale 未安装或命令未找到"
                log_error "📦  请先安装 tailscale 后再运行本脚本"
            else
                log_info "🔓  正在执行 tailscale logout..."
                
                if tailscale logout; then
                    sleep 3
                    if tailscale status 2>&1 | grep -q "Logged out."; then
                        log_info "✅  成功登出 tailscale"
                    else
                        log_error "⚠️  登出后状态未知，请检查 tailscale status 状态"
                    fi
                else
                    log_error "❌  tailscale logout 命令执行失败"
                fi
            fi
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        5)
            $CONFIG_DIR/uninstall.sh
            log_info "✅  请按回车退出..." 1
            read _
            exit 0
            ;;
        6)
            $CONFIG_DIR/update_ctl.sh
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        7)
            "$CONFIG_DIR/autoupdate.sh" --manual
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        8)
            $CONFIG_DIR/github_direct_ctl.sh
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        9)
            if [ -f "$VERSION_FILE" ]; then
                log_info "📦  当前本地版本: $(cat "$VERSION_FILE")"
            else
                log_info "⚠️  本地未记录版本信息, 可能未安装 Tailscale"
            fi
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        10)
            log_info "$($CONFIG_DIR/fetch_and_install.sh --dry-run)"
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        11)
            $CONFIG_DIR/notify_ctl.sh
            ;;
        12)
            $CONFIG_DIR/test_mirrors.sh
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        13)
            if [ -d /usr/share/small-tailscale/scripts ]; then
                log_info "管理脚本随 luci-app-small-tailscale 安装，请使用 opkg 或 apk 升级插件"
                read -r _
                return
            fi
            URL="${GITHUB_DOWNLOAD_BASE_URL}/${INSTALL_SCRIPT_URL_SUFFIX}"
            tmpfile=$(mktemp)
            if webget "$tmpfile" "$URL" "echooff"; then
                # exec 会替换当前进程，不会返回
                exec sh "$tmpfile" < /dev/tty
            else
                log_error "❌ 脚本下载失败，请检查网络和下载地址"
                rm -f "$tmpfile"
                log_info "✅  请按回车继续..." 1
                read _
            fi
            ;;
        14)
            # 检查日志文件是否存在
            if [ -f "$LOG_FILE" ]; then
                # 如果文件存在，则显示日志内容
                log_info "    日志内容如下："
                log_info "    ---------------------------"
                cat "$LOG_FILE"
                log_info "    ---------------------------"
            else
                # 如果文件不存在，则提示用户日志文件未找到
                log_error "❌  没有找到日志文件，更新脚本可能未执行！"
            fi
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        0)
            log_info "👋  退出脚本"
            sleep 1
            clear
            exit 0
            ;;
        *)
            log_info "❌  无效选择, 请重新输入, 按回车继续..." 1
            read _
            ;;
    esac
}

# 主循环
clear
while true; do
    show_menu
    log_info "✅  请输入你的选择: " 1
    IFS= read -r choice || exit 0
    log_info ""
    handle_choice "$choice"
    clear
done
