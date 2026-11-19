#!/bin/sh
set -e
. /etc/tailscale/tools.sh

case "${1:-}" in
    ''|--auto-update=true|--auto-update=false|--remove) ;;
    *) log_error "无效的定时任务选项：$1"; exit 1 ;;
esac
lock_config
crontab=/etc/crontabs/root
if [ "${1:-}" = --remove ] && [ ! -f "$crontab" ]; then exit 0; fi
tmp=$(mktemp "$crontab.XXXXXX")
trap 'rm -f "$tmp"' EXIT
if [ -f "$crontab" ]; then
    # 只替换本项目生成的两种每日任务，保留管理员添加的参数、重定向和其他命令。
    awk -v dir="$CONFIG_DIR/" '
        NF == 6 && $1 ~ /^[0-9]+$/ && $3 == "*" && $4 == "*" && $5 == "*" {
            if ($6 == dir "autoupdate.sh" && $2 ~ /^[456]$/) next
            if ($6 == dir "test_mirrors.sh" && $2 ~ /^[23]$/) next
        }
        {print}
    ' "$crontab" > "$tmp"
fi
if [ "${1:-}" != --remove ]; then
    awk -v seed="$(date +%s)" -v dir="$CONFIG_DIR" 'BEGIN {
        srand(seed); printf "%d %d * * * %s/autoupdate.sh\n", int(rand()*60), 4+int(rand()*3), dir
    }' >> "$tmp"
fi
mv "$tmp" "$crontab"
/etc/init.d/cron restart
