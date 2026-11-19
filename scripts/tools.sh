#!/bin/sh
# /etc/tailscale/tools.sh
CONFIG_DIR="/etc/tailscale"
mkdir -p "$CONFIG_DIR"
LOG_FILE="/var/log/tailscale_install.log"
VERSION_FILE="$CONFIG_DIR/current_version"
NTF_CONF="$CONFIG_DIR/notify.conf"
INST_CONF="$CONFIG_DIR/install.conf"
TIME_OUT=30

# 架构探测（统一入口）
detect_arch() {
    local arch_raw="${1:-$(uname -m)}"
    local arch=""
    local endian=""

    case "$arch_raw" in
        i386|i486|i586|i686)
            arch="386"
            ;;
        x86_64)
            arch="amd64"
            ;;
        armv7l|armv7|armhf|armv6l)
            arch="arm"
            ;;
        aarch64|arm64|armv8l)
            arch="arm64"
            ;;
        mips|mipsel|mipsel_24kc|mips64|mips64el)
            arch="$arch_raw"
            ;;
        *)
            log_error "❌  不支持的架构: $arch_raw"
            log_error "❌  请在 https://github.com/CH3NGYZ/small-tailscale-openwrt/issues 反馈此架构"
            return 1
            ;;
    esac

    case "$arch" in
        mips)
            if command -v hexdump >/dev/null 2>&1 && command -v awk >/dev/null 2>&1; then
                endian=$(echo -n I | hexdump -o 2>/dev/null | awk '{ print (substr($2,6,1)=="1") ? "le" : ""; exit }')
                echo "mips${endian}"
            else
                echo "mips"
            fi
            ;;
        mipsel|mipsel_24kc)
            echo "mipsle"
            ;;
        mips64)
            echo "mips64"
            ;;
        mips64el)
            echo "mips64le"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# 如果未在配置中指定 ARCH，则尝试自动探测一次（懒加载）
ensure_arch() {
    if [ -n "$ARCH" ]; then
        return 0
    fi
    ARCH="$(detect_arch)" || return 1
}

# 进程环境优先。定时任务和开机更新也可以读取同一份 NAME=URL 配置。
if [ -r "$CONFIG_DIR/github-download.env" ]; then
    : "${GITHUB_DOWNLOAD_BASE_URL=$(sed -n 's/^GITHUB_DOWNLOAD_BASE_URL=//p' "$CONFIG_DIR/github-download.env" | tail -n 1)}"
fi
GITHUB_DOWNLOAD_BASE_URL=${GITHUB_DOWNLOAD_BASE_URL:-https://github.com}
GITHUB_DOWNLOAD_BASE_URL=${GITHUB_DOWNLOAD_BASE_URL%/}

log_message() {
    local level=$1 line
    shift
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
    if [ "${RECORD_INSTALL_LOG:-}" = true ]; then
        printf '%s\n' "$line" >> "$LOG_FILE"
    fi
    if [ "$#" -eq 2 ]; then printf '%s' "$line"; else printf '%s\n' "$line"; fi
}
log_info() { log_message INFO "$@"; }
log_warn() { log_message WARNING "$@"; }
log_error() { log_message ERROR "$@"; }

# 配置文件来自 CLI 和 LuCI，仅解析受支持的字段。
safe_source() {
    local file=$1 line key value
    [ -r "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in *=*) ;; *) continue ;; esac
        key=${line%%=*}
        case "$key" in
            MODE|AUTO_UPDATE|VERSION|PINNED_VERSION|ARCH|HOST_NAME|TIMESTAMP|\
            NOTIFY_UPDATE|NOTIFY_MIRROR_FAIL|NOTIFY_EMERGENCY|NOTIFY_SERVERCHAN|SERVERCHAN_KEY|\
            NOTIFY_BARK|BARK_KEY|NOTIFY_NTFY|NTFY_KEY|NOTIFY_PUSHPLUS|PUSHPLUS_TOKEN) ;;
            *) continue ;;
        esac
        value=${line#*=}
        case "$value" in \"*\") value=${value#\"}; value=${value%\"} ;; esac
        IFS= read -r "$key" <<EOF
$value
EOF
    done < "$file"
}

# setup、更新任务和 LuCI 使用同一个文件锁。子脚本继承描述符 9。
lock_config() {
    [ "${SMALL_TS_CONFIG_LOCKED:-}" != 1 ] || return 0
    mkdir -p /var/lock || return 1
    exec 9>>/var/lock/small-tailscale-config.lock
    flock -x 9 || return 1
    export SMALL_TS_CONFIG_LOCKED=1
}

unlock_config() {
    unset SMALL_TS_CONFIG_LOCKED
    exec 9>&-
}

valid_version() {
    case "$1" in ''|*[!v0-9.]*) return 1 ;; esac
    printf '%s\n' "$1" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'
}

webget() {
    # $1 输出文件
    # $2 URL
    # $3 是否静默: echooff
    # $4 禁止重定向: rediroff
    local outfile="$1"
    local url="$2"

    local ua="Tailscale-Helper"

    # 是否静默
    local quiet=""
    [ "$3" = "echooff" ] && quiet="-s"

    # 是否禁用重定向
    local redirect="-L"
    [ "$4" = "rediroff" ] && redirect=""

    # ----  优先使用 curl ----
    if command -v curl >/dev/null 2>&1; then
        http_code=$(timeout "$TIME_OUT" curl $quiet $redirect \
            -A "$ua" \
            -w "%{http_code}" \
            -o "$outfile" \
            "$url" 2>/dev/null)

        case "$http_code" in 2*) return 0 ;; *) return 1 ;; esac
    fi

    # ----  回退到 wget ----
    if command -v wget >/dev/null 2>&1; then
        local q="--show-progress"
        [ "$3" = "echooff" ] && q="-q"

        local r=""
        [ "$4" = "rediroff" ] && r="--max-redirect=0"

        # wget 不直接返回 HTTP 状态码，需要解析 headers
        headers=$(mktemp)
        timeout "$TIME_OUT" wget $q $r \
            --server-response --no-check-certificate \
            --header="User-Agent: $ua" \
            -O "$outfile" "$url" 2>"$headers"

        # 提取最后的 HTTP 状态码
        http_code=$(grep -oE 'HTTP/[0-9\.]+ [0-9]+' "$headers" | tail -n1 | awk '{print $2}')
        rm -f "$headers"

        case "$http_code" in 2*) return 0 ;; *) return 1 ;; esac
    fi

    log_error "❌ curl 和 wget 都不存在"
    return 1
}

# 校验函数, 自动根据长度判断类型, 支持 openssl 回退
verify_checksum() {
    local file=$1
    local expected=$2
    local actual=""

    if [ ${#expected} -eq 64 ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            actual=$(sha256sum "$file" | awk '{print $1}')
        elif command -v openssl >/dev/null 2>&1; then
            actual=$(openssl dgst -sha256 "$file" | awk '{print $2}')
        else
            log_error "缺少 SHA256 校验工具"
            return 1
        fi
    elif [ ${#expected} -eq 32 ]; then
        if command -v md5sum >/dev/null 2>&1; then
            actual=$(md5sum "$file" | awk '{print $1}')
        elif command -v openssl >/dev/null 2>&1; then
            actual=$(openssl dgst -md5 "$file" | awk '{print $2}')
        else
            log_error "缺少 MD5 校验工具"
            return 1
        fi
    else
        log_error "未知的校验值格式"
        return 1
    fi

    if [ "$expected" = "$actual" ]; then
        log_info "✅  校验通过"
        return 0
    else
        log_error "❌  校验失败！预期: $expected, 实际: $actual"
        return 1
    fi
}

# 读取系统启动时间（优先 /proc/uptime，提供更细粒度的耗时计算）
now_uptime() {
    if [ -r /proc/uptime ]; then
        awk '{print $1}' /proc/uptime
    else
        date +%s
    fi
}

# 计算耗时（保留 2 位小数）
calc_elapsed() {
    local start="$1"
    local end="$2"
    awk -v s="$start" -v e="$end" 'BEGIN{printf "%.2f", (e - s)}'
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
        return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $2}'
        return 0
    fi
    return 1
}

md5_file() {
    local file="$1"
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$file" | awk '{print $1}'
        return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
        openssl dgst -md5 "$file" | awk '{print $2}'
        return 0
    fi
    return 1
}

# URL 编码函数 (纯 shell 内建操作, 无外部命令依赖)
urlencode() {
    local str="$1" c rest
    rest="$str"
    while [ -n "$rest" ]; do
        c="${rest%"${rest#?}"}"
        rest="${rest#?}"
        case "$c" in
            [A-Za-z0-9._~-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}


send_notify() {
    local host_name="$(uci get system.@system[0].hostname 2>/dev/null || echo OpenWrt)"
    local title="$host_name Tailscale通知"
    local user_title="$1"
    shift
    local body_content="$(printf "%s\n" "$@")"
    local content="$(printf "%s\n%s" "$user_title" "$body_content")"

    safe_source "$NTF_CONF"  # 引入配置文件

    # 通用发送函数（curl 优先，wget 兼容）
    # 用法: send_via_curl_or_wget URL [DATA] [METHOD] [HEADER]
    # METHOD: GET / POST(默认当有DATA时)
    send_via_curl_or_wget() {
        local url="$1"
        local data="$2"
        local method="$3"
        local headers="$4"

        if command -v curl > /dev/null; then
            if [ "$method" = "GET" ] || [ -z "$data" ]; then
                curl -sS -A "Tailscale-Helper" "$url"
            else
                curl -sS -A "Tailscale-Helper" -X POST "$url" -d "$data" -H "$headers"
            fi
        elif command -v wget > /dev/null; then
            if [ "$method" = "GET" ] || [ -z "$data" ]; then
                wget --quiet --header="User-Agent: Tailscale-Helper" -O /dev/null "$url"
            else
                echo "$data" | wget --quiet --header="User-Agent: Tailscale-Helper" --method=POST --body-file=- --header="$headers" "$url"
            fi
        else
            log_error "❌  curl 和 wget 都不可用，无法发送通知"
            return 1
        fi
    }

    # Server酱
    if [ "$NOTIFY_SERVERCHAN" = "1" ] && [ -n "$SERVERCHAN_KEY" ]; then
        data="text=$title&desp=$content"
        send_via_curl_or_wget "https://sctapi.ftqq.com/$SERVERCHAN_KEY.send" "$data" "POST" && log_info "✅  Server酱 通知已发送"
    fi

    # Bark
    if [ "$NOTIFY_BARK" = "1" ] && [ -n "$BARK_KEY" ]; then
        title_enc=$(urlencode "$title")
        content_enc=$(urlencode "$content")
        bark_url="${BARK_KEY}/${title_enc}/${content_enc}"
        send_via_curl_or_wget "$bark_url" "" "GET" && log_info "✅  Bark 通知已发送"
    fi

    # ntfy
    if [ "$NOTIFY_NTFY" = "1" ] && [ -n "$NTFY_KEY" ]; then
        headers="Title: $title"
        send_via_curl_or_wget "https://ntfy.sh/$NTFY_KEY" "$content" "POST" "$headers" && log_info "✅  NTFY 通知已发送"
    fi

    # PushPlus
    if [ "$NOTIFY_PUSHPLUS" = "1" ] && [ -n "$PUSHPLUS_TOKEN" ]; then
        pushplus_data="{\"token\":\"$PUSHPLUS_TOKEN\",\"title\":\"$title\",\"content\":\"$content\",\"template\":\"txt\"}"
        send_via_curl_or_wget "http://www.pushplus.plus/send" "$pushplus_data" "POST" "Content-Type: application/json" && log_info "✅  PushPlus 通知已发送"
    fi

    # 无任何通知方式启用
    if [ "$NOTIFY_SERVERCHAN" != "1" ] && [ "$NOTIFY_BARK" != "1" ] && [ "$NOTIFY_NTFY" != "1" ] && [ "$NOTIFY_PUSHPLUS" != "1" ]; then
        log_error "❌  未启用任何通知方式"
    fi
}

# 检查是否需要发送通知
should_notify() {
    local notify_type=$1
    safe_source "$NTF_CONF"
    local notify_var
    case "$notify_type" in
        "update") notify_var="$NOTIFY_UPDATE" ;;
        "mirror_fail") notify_var="$NOTIFY_MIRROR_FAIL" ;;
        "emergency") notify_var="$NOTIFY_EMERGENCY" ;;
        *)
            log_error "❌  未知通知类型: $notify_type"
            return 1
            ;;
    esac
    [ "$notify_var" = "1" ]
}
