#!/bin/sh

set -e
. /etc/tailscale/tools.sh
log_info "GitHub 下载地址: $GITHUB_DOWNLOAD_BASE_URL"
if [ "$#" -eq 0 ]; then
    printf '输入新的镜像地址，输入 default 恢复官方地址，直接回车保留：'
    IFS= read -r mirror || exit 0
    [ -n "$mirror" ] || exit 0
else
    mirror=$1
fi
[ "$mirror" != default ] || mirror=https://github.com
case "$mirror" in http://?*|https://?*) ;; *) log_error "请输入 HTTP 或 HTTPS 地址"; exit 1 ;; esac
case "$mirror" in *[[:space:]]*) log_error "地址中不能包含空白字符"; exit 1 ;; esac
lock_config
file="$CONFIG_DIR/github-download.env"
tmp=$(mktemp "$file.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf 'GITHUB_DOWNLOAD_BASE_URL=%s\n' "${mirror%/}" > "$tmp"
mv "$tmp" "$file"
log_info "已保存下载地址：${mirror%/}"
