#!/bin/sh

set -e
. /etc/tailscale/tools.sh
safe_source "$INST_CONF"

if [ "$#" -eq 0 ]; then
    log_info "自动更新：${AUTO_UPDATE:-false}，当前安装：$(cat "$VERSION_FILE" 2>/dev/null || echo 未安装)，版本策略：${PINNED_VERSION:-跟随最新}"
    printf '1) 启用自动更新   2) 禁用自动更新   3) 锁定指定版本   4) 跟随最新\n请选择：'
    IFS= read -r choice || exit 0
    if [ "$choice" = 3 ]; then
        printf '输入版本号（例如 v1.90.0）：'
        IFS= read -r version || exit 1
        choice=--version="$version"
    fi
else
    choice=$1
fi

case "$choice" in
    1|on) key=AUTO_UPDATE; value=true ;;
    2|off) key=AUTO_UPDATE; value=false ;;
    4|--version=latest) key=PINNED_VERSION; value= ;;
    --version=*)
        key=PINNED_VERSION
        value=${choice#*=}
        valid_version "$value" || { log_error "无效的发布版本：$value"; exit 1; }
        ;;
    *) exit 1 ;;
esac

lock_config
tmp=$(mktemp "$INST_CONF.XXXXXX")
trap 'rm -f "$tmp"' EXIT
if [ -f "$INST_CONF" ]; then
    awk -v key="$key" 'index($0, key "=") != 1' "$INST_CONF" > "$tmp"
fi
printf '%s=%s\n' "$key" "$value" >> "$tmp"
mv "$tmp" "$INST_CONF"
log_info "已保存 $key=${value:-跟随最新}"
