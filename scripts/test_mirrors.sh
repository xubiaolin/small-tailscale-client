#!/bin/sh

set -e
. /etc/tailscale/tools.sh

if [ "$GITHUB_DOWNLOAD_BASE_URL" = "https://github.com" ]; then
    log_info "🌐  使用 GitHub 官方地址，跳过加速下载测试"
    exit 0
fi

safe_source "$INST_CONF"
ensure_arch || exit 1

TIME_OUT=20
binary_name="tailscaled-linux-$ARCH"
release_url="$GITHUB_DOWNLOAD_BASE_URL/CH3NGYZ/small-tailscale-openwrt/releases/latest/download"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

test_download() {
    local checksum start elapsed
    webget "$test_dir/SHA256SUMS.txt" "$release_url/SHA256SUMS.txt" "echooff" || return 1
    checksum=$(awk -v name="$binary_name" '$2 == name {print $1; exit}' "$test_dir/SHA256SUMS.txt")
    [ "${#checksum}" -eq 64 ] || return 1

    start=$(now_uptime)
    webget "$test_dir/$binary_name" "$release_url/$binary_name" "echooff" || return 1
    [ "$(sha256_file "$test_dir/$binary_name")" = "$checksum" ] || return 1
    elapsed=$(calc_elapsed "$start" "$(now_uptime)")
    log_info "✅  下载及 SHA256 校验成功，用时 ${elapsed}s"
}

log_info "⏳  测试 GitHub 下载地址 $GITHUB_DOWNLOAD_BASE_URL"
if ! test_download; then
    log_error "❌  下载或 SHA256 校验失败"
    if should_notify "mirror_fail"; then
        send_notify "GitHub 加速下载测试失败" "请检查 GITHUB_DOWNLOAD_BASE_URL 配置及网络连接"
    fi
    exit 1
fi
