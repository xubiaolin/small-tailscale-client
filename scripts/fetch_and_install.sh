#!/bin/sh

set -e

. /etc/tailscale/tools.sh
[ ! -s "$INST_CONF" ] || safe_source "$INST_CONF"
ensure_arch || exit 1

release_base="$GITHUB_DOWNLOAD_BASE_URL/CH3NGYZ/small-tailscale-openwrt/releases"

get_latest_version() {
    local version_file version=""
    version_file=$(mktemp) || return 1
    if webget "$version_file" "$release_base/latest/download/version.txt" "echooff"; then
        version=$(awk '
            NR == 1 { sub(/\r$/, ""); tag = $0 }
            END { if (NR == 1 && tag ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) print tag }
        ' "$version_file")
    fi
    rm -f "$version_file"
    [ -n "$version" ] || return 1
    printf '%s\n' "$version"
}

get_checksum() {
    local sums_file=$1
    local target_name=$2
    local digest_length=$3
    awk -v name="$target_name" -v size="$digest_length" \
        '$2 == name && length($1) == size && $1 ~ /^[[:xdigit:]]+$/ {print $1; exit}' "$sums_file"
}

# 主安装流程
install_tailscale() {
    local version=$1
    local mode=$2

    local arch="$ARCH"
    local tailscale_temp_path="/tmp/tailscaled.$$"
    local release_arch_filename="tailscaled-linux-$arch"
    local release_url="$release_base/download/$version"

    log_info "🔗  准备校验文件..."
    local sum_file checksum
    sum_file=$(mktemp)
    checksum=""
    if webget "$sum_file" "$release_url/SHA256SUMS.txt" "echooff"; then
        checksum=$(get_checksum "$sum_file" "$release_arch_filename" 64)
    fi
    if [ -z "$checksum" ] && webget "$sum_file" "$release_url/MD5SUMS.txt" "echooff"; then
        checksum=$(get_checksum "$sum_file" "$release_arch_filename" 32)
    fi
    rm -f "$sum_file"
    if [ -z "$checksum" ]; then
        log_error "❌  无法获取 $release_arch_filename 的校验值"
        return 1
    fi

    log_info "🔗  正在下载 Tailscale $version ($arch)..."
    if ! webget "$tailscale_temp_path" "$release_url/$release_arch_filename" "echooff" ||
       ! verify_checksum "$tailscale_temp_path" "$checksum"; then
        log_error "❌  下载或校验失败，安装中止"
        rm -f "$tailscale_temp_path"
        return 1
    fi

    # 安装
    chmod +x "$tailscale_temp_path"
    if [ "$mode" = "local" ]; then
        mkdir -p /usr/local/bin
        mv "$tailscale_temp_path" /usr/local/bin/tailscaled
        ln -sf /usr/local/bin/tailscaled /usr/bin/tailscaled
        ln -sf /usr/local/bin/tailscaled /usr/bin/tailscale
        log_info "✅  安装到 /usr/local/bin/"
    else
        mv "$tailscale_temp_path" /tmp/tailscaled
        ln -sf /tmp/tailscaled /usr/bin/tailscaled
        ln -sf /tmp/tailscaled /usr/bin/tailscale
        log_info "✅  安装到 /tmp (内存模式)"
    fi

    echo "$version" > "$VERSION_FILE"
}

# 参数解析
MODE="local"
VERSION="latest"
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --mode=*) MODE="${1#*=}"; shift ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        --mirror-list=*) shift ;;  # 兼容旧调用，下载地址由环境变量决定
        --dry-run) DRY_RUN=true; shift ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
done

if [ "$VERSION" = "latest" ]; then
    attempt=1
    max_attempts=10
    until VERSION=$(get_latest_version); do
        if [ "$attempt" -ge "$max_attempts" ]; then
            log_error "❌  无法从 version.txt 读取最新版本号" >&2
            exit 1
        fi
        log_warn "⚠️  获取最新版本失败 ($attempt/$max_attempts)，重试中..." >&2
        sleep 2
        attempt=$((attempt + 1))
    done
fi

# 干跑模式（只输出版本号）
if [ "$DRY_RUN" = "true" ]; then
    echo "$VERSION"
    exit 0
fi

# 执行安装
install_tailscale "$VERSION" "$MODE"
