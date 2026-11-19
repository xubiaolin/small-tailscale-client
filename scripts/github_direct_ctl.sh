#!/bin/sh

. /etc/tailscale/tools.sh

log_info "GitHub 下载地址: $GITHUB_DOWNLOAD_BASE_URL"
log_info "可通过环境变量 GITHUB_DOWNLOAD_BASE_URL 指定地址。"
