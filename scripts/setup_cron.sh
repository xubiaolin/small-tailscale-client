#!/bin/sh

set -e
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh

# 参数解析
AUTO_UPDATE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --auto-update=*) 
            AUTO_UPDATE="${1#*=}"
            if [ "$AUTO_UPDATE" != "true" ] && [ "$AUTO_UPDATE" != "false" ]; then
                log_error "❌  错误：--auto-update 参数值应为 true 或 false"
                exit 1
            fi
            shift
            ;;
        *)
            log_error "❌  错误：未知参数: $1"
            exit 1
            ;;
    esac
done


# 清除旧配置
log_info "⏰  清除旧的定时任务配置..."
if [ -f /etc/crontabs/root ]; then
    sed -i "\|$CONFIG_DIR/|d" /etc/crontabs/root || { log_error "❌  清除旧配置失败"; exit 1; }
else
    log_info "⚠️  /etc/crontabs/root 文件不存在，跳过清除操作"
fi

# 自动更新任务（4~6）
UPDATE_HOUR=$((4 + $(awk -v seed=$(date +%s) 'BEGIN{srand(seed+2000); print int(rand()*3)}')))
UPDATE_MIN=$(awk -v seed=$(date +%s) 'BEGIN{srand(seed+3000); print int(rand()*60)}')

# 添加自动更新任务
log_info "⏰  添加自动更新任务..."
echo "$UPDATE_MIN $UPDATE_HOUR * * * $CONFIG_DIR/autoupdate.sh" >> /etc/crontabs/root || { log_error "❌  添加自动更新任务失败"; exit 1; }
log_info "⏰  自动更新任务运行时间已设定为 $UPDATE_HOUR 点 $UPDATE_MIN 分"

# 重启cron服务
log_info "⏰  重启cron服务..."
/etc/init.d/cron restart || { log_error "❌  重启cron服务失败"; exit 1; }

log_info "⏰  定时任务配置完成！"
