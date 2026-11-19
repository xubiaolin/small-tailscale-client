#!/bin/sh

set -e
set -o pipefail 2>/dev/null || true

# 仅在交互终端清屏，避免无 TERM 时出错
[ -t 1 ] && clear 2>/dev/null || true

TIME_OUT=20
CONFIG_DIR="/etc/tailscale"
# 安装脚本独立运行，此时脚本包中的 tools.sh 可能尚未安装。
if [ -r "$CONFIG_DIR/github-download.env" ]; then
    : "${GITHUB_DOWNLOAD_BASE_URL=$(sed -n 's/^GITHUB_DOWNLOAD_BASE_URL=//p' "$CONFIG_DIR/github-download.env" | tail -n 1)}"
fi
GITHUB_DOWNLOAD_BASE_URL=${GITHUB_DOWNLOAD_BASE_URL:-https://github.com}

SCRIPTS_TGZ_URL_SUFFIX="xubiaolin/small-tailscale-client/raw/refs/heads/main/tailscale-openwrt-scripts.tar.gz"

# 预先计算的校验和（由 GitHub Actions 自动回填）
EXPECTED_CHECKSUM_SHA256="7004f8b6a86bec1f589a7956fd86f8d8d09d222d5f9b516b9998e3d5852e1ebb"
EXPECTED_CHECKSUM_MD5="23d979eb105af9c2dbf7b38ba94d9e8d"

# -------------------- 日志 --------------------
log_info() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [INSTALL] [INFO] $1"
    [ $# -eq 2 ] || echo
}

log_warn() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [INSTALL] [WARN] $1"
    [ $# -eq 2 ] || echo
}

log_error() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [INSTALL] [ERROR] $1"
    [ $# -eq 2 ] || echo
}

is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

# -------------------- 包管理器适配(opkg/apk) --------------------
PKG_MGR=""
if command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
else
    log_error "❌  未检测到 opkg 或 apk 命令，当前系统可能不是 OpenWrt 或缺少包管理器"
    log_error "❌  无法继续执行安装脚本"
    exit 1
fi

pkg_list_installed() {
    case "$PKG_MGR" in
        opkg) opkg list-installed ;;
        apk) apk info ;;
    esac
}

pkg_is_installed() {
    # $1: pkg name
    local pkg="$1"
    case "$PKG_MGR" in
        # 允许数字后缀（如 libustream-mbedtls20201210）
        opkg) echo "$INSTALLED_PKGS" | grep -Eq "^${pkg}([0-9]+)? -" ;;
        apk) echo "$INSTALLED_PKGS" | grep -qx "$pkg" ;;
    esac
}

pkg_update() {
    case "$PKG_MGR" in
        opkg) opkg update ;;
        apk) apk update ;;
    esac
}

pkg_install() {
    case "$PKG_MGR" in
        opkg) opkg install "$1" ;;
        apk) apk add "$1" ;;
    esac
}

# -------------------- 时间同步（尽量在 HTTPS 前校时） --------------------
sync_time() {
    log_info "正在同步系统时间..."

    # 尝试 NTP
    for server in ntp.aliyun.com time1.cloud.tencent.com pool.ntp.org; do
        if command -v ntpdate >/dev/null 2>&1; then
            if ntpdate -u "$server" >/dev/null 2>&1; then
                log_info "时间同步成功（$server）"
                return 0
            fi
        fi
        if command -v ntpd >/dev/null 2>&1; then
            if ntpd -q -n -p "$server" >/dev/null 2>&1; then
                log_info "时间同步成功（$server）"
                return 0
            fi
        fi
    done

    # HTTP 头时间（依赖 curl/wget 任一可用即可）
    log_warn "所有 NTP 服务器都失败或未安装 ntpdate/ntpd，尝试使用 HTTP 头时间"

    http_date_line=""
    if command -v curl >/dev/null 2>&1; then
        http_date_line=$(curl -fsSI -A "Tailscale-Helper" --connect-timeout 5 https://www.baidu.com 2>/dev/null | grep -i '^date:' | head -n1 || true)
    elif command -v wget >/dev/null 2>&1; then
        # wget 会把响应头写到 stderr
        http_date_line=$(wget -S --spider --timeout=5 --user-agent="Tailscale-Helper" https://www.baidu.com 2>&1 | grep -i '^  Date:' | head -n1 | sed 's/^  //')
        http_date_line=$(echo "$http_date_line" | sed 's/^Date:/date:/I')
    fi

    [ -z "$http_date_line" ] && log_warn "无法获取 HTTP 头时间（可能缺少 curl/wget 或网络受限）" && return 1

    http_time=$(echo "$http_date_line" | awk '{
        # 解析 RFC1123: date: Fri, 13 Mar 2026 03:11:54 GMT
        split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", months, " ");
        for (i=1; i<=12; i++) m[months[i]] = i;
        # 去掉逗号
        gsub(/,/, "", $3);
        # $4=13  $5=Mar $6=2026 $7=03:11:54
        if ($4 ~ /^[0-9]+$/) {
            printf "%04d-%02d-%02d %s", $6, m[$5], $4, $7
        } else {
            # 兼容部分实现差异
            printf "%04d-%02d-%02d %s", $5, m[$4], $3, $6
        }
    }')

    if [ -n "$http_time" ] && date -u -s "$http_time" >/dev/null 2>&1; then
        log_info "已用 HTTP 头设置时间"
        return 0
    fi

    log_warn "HTTP 头时间解析/设置失败"
    return 1
}

# 尝试一次：尽早校时，避免 TLS 证书时间错误
sync_time || true

# -------------------- 依赖检查与安装 --------------------
# 先缓存已安装包列表（避免循环中多次调用包管理器）
INSTALLED_PKGS=$(pkg_list_installed 2>/dev/null || true)

# 依赖包列表（按包管理器区分）
REQUIRED_PACKAGES=""

case "$PKG_MGR" in
    opkg)
        # 如果已安装 libustream-mbedtls（含数字后缀），则跳过 libustream-openssl
        if pkg_is_installed "libustream-mbedtls"; then
            SKIP_OPENSSL=1
        else
            SKIP_OPENSSL=0
        fi

        REQUIRED_PACKAGES="ca-bundle kmod-tun coreutils-timeout curl"
        [ "$SKIP_OPENSSL" -eq 0 ] && REQUIRED_PACKAGES="libustream-openssl $REQUIRED_PACKAGES"
        ;;
    apk)
        REQUIRED_PACKAGES="ca-certificates kmod-tun curl coreutils-timeout"
        ;;
    *)
        log_error "❌  不支持的包管理器: $PKG_MGR"
        exit 1
        ;;
esac

need_install=0
for package in $REQUIRED_PACKAGES; do
    if ! pkg_is_installed "$package"; then
        log_warn "⚠️  包 $package 未安装"
        need_install=1
    fi
done

if [ "$need_install" -eq 1 ]; then
    log_info "🔄  正在更新 $PKG_MGR 源..."
    if ! pkg_update 2>&1; then
        log_warn "⚠️  $PKG_MGR update 失败（可能网络/源异常），继续尝试安装..."
    else
        log_info "✅  $PKG_MGR update 成功"
    fi

    for package in $REQUIRED_PACKAGES; do
        if pkg_is_installed "$package"; then
            continue
        fi

        log_warn "⚠️  包 $package 未安装，开始安装..."
        if pkg_install "$package" 2>&1; then
            log_info "✅  包 $package 安装成功"
        else
            # coreutils-timeout 失败：尝试 coreutils
            if [ "$PKG_MGR" = "opkg" ] && [ "$package" = "coreutils-timeout" ]; then
                alt="coreutils"
                log_warn "⚠️  安装 $package 失败，尝试安装 $alt 替代..."
                if pkg_install "$alt" 2>&1; then
                    log_info "✅  $alt 安装成功"
                    continue
                fi
            fi

            log_error "❌  安装 $package 失败，无法继续，请手动安装后重试"
            exit 1
        fi
    done

    # 重新刷新已安装列表
    INSTALLED_PKGS=$(pkg_list_installed 2>/dev/null || true)
else
    log_info "✅  已安装所有必要组件"
fi

# 安装完依赖后再尝试校时（提高 curl/wget 可用概率）
sync_time || true

# 最终检查关键命令
for cmd in timeout tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "❌  未检测到 $cmd 命令，请安装后重新执行脚本"
        exit 1
    fi
done

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    log_error "❌  curl 和 wget 都不可用，无法继续"
    exit 1
fi

verify_checksum() {
    # $1 file  $2 type(sha256/md5)  $3 expected
    local file="$1"
    local type="$2"
    local expected="$3"
    local actual=""

    case "$type" in
        sha256)
            if command -v sha256sum >/dev/null 2>&1; then
                actual=$(sha256sum "$file" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                actual=$(openssl dgst -sha256 "$file" | awk '{print $2}')
            else
                log_error "❌  系统缺少 sha256sum 或 openssl, 无法校验文件"
                return 1
            fi
            ;;
        md5)
            if command -v md5sum >/dev/null 2>&1; then
                actual=$(md5sum "$file" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                actual=$(openssl dgst -md5 "$file" | awk '{print $2}')
            else
                log_error "❌  系统缺少 md5sum 或 openssl, 无法校验文件"
                return 1
            fi
            ;;
        *)
            log_error "❌  校验类型无效: $type"
            return 1
            ;;
    esac

    if [ "$actual" != "$expected" ]; then
        log_error "❌  校验失败！预期: $expected, 实际: $actual"
        return 1
    fi

    return 0
}

# -------------------- 下载脚本包并校验 --------------------
scripts_tgz_url="${GITHUB_DOWNLOAD_BASE_URL%/}/${SCRIPTS_TGZ_URL_SUFFIX}"

SCRIPTS_TGZ_PATH=$(mktemp)
stage=''
trap 'rm -f "$SCRIPTS_TGZ_PATH"; [ -z "$stage" ] || rm -rf "$stage"' EXIT

download_archive() {
    if command -v curl >/dev/null 2>&1; then
        timeout "$TIME_OUT" curl -fsSL -A Tailscale-Helper -o "$SCRIPTS_TGZ_PATH" "$scripts_tgz_url"
    else
        timeout "$TIME_OUT" wget -q -O "$SCRIPTS_TGZ_PATH" "$scripts_tgz_url"
    fi
}
if download_archive; then
    log_info "📥  下载成功: $scripts_tgz_url"
else
    log_error "❌  下载失败: $scripts_tgz_url"
    exit 1
fi

sha_ok=0
md5_ok=0

if verify_checksum "$SCRIPTS_TGZ_PATH" "sha256" "$EXPECTED_CHECKSUM_SHA256"; then
    log_info "🔐  SHA256 校验通过"
    sha_ok=1
else
    log_warn "⚠️  SHA256 校验失败 (忽略, 尝试 MD5)"
fi

if verify_checksum "$SCRIPTS_TGZ_PATH" "md5" "$EXPECTED_CHECKSUM_MD5"; then
    log_info "🔐  MD5 校验通过"
    md5_ok=1
else
    log_warn "⚠️  MD5 校验失败"
fi

if [ "$sha_ok" -eq 0 ] && [ "$md5_ok" -eq 0 ]; then
    log_error "❌  校验失败，安装中止"
    exit 1
fi

log_info "✅  下载脚本包 + 校验成功!"

# -------------------- 解压脚本包 --------------------
log_info "📦  解压脚本包..."
stage=$(mktemp -d /etc/.smallts-install.XXXXXX)
tar -xzf "$SCRIPTS_TGZ_PATH" -C "$stage"
mkdir -p /var/lock
exec 9>>/var/lock/small-tailscale-config.lock
flock -x 9
case "$(sh "$stage/source.sh")" in
    none|project) ;;
    *) log_error "检测到外部 Tailscale 安装，请先通过原安装渠道管理。"; exit 1 ;;
esac
for script in "$stage"/*.sh; do
    [ ! -d "$CONFIG_DIR/${script##*/}" ] || { log_error "脚本路径已被目录占用"; exit 1; }
done
mkdir -p "$CONFIG_DIR"
for script in "$stage"/*.sh; do
    mv -f "$script" "$CONFIG_DIR/${script##*/}"
done

[ -f "$CONFIG_DIR/install.conf" ] || printf '# Tailscale 安装配置\n' > "$CONFIG_DIR/install.conf"

# 升级旧安装时，移除原先由 setup_cron.sh 生成的每日代理池测速任务。
old_mirror_job='^[0-9]+ [23] \* \* \* /etc/tailscale/test_mirrors\.sh$'
if current_crontab=$(crontab -l 2>/dev/null) && printf '%s\n' "$current_crontab" | grep -Eq "$old_mirror_job"; then
    printf '%s\n' "$current_crontab" | sed -E "\\|$old_mirror_job|d" | crontab -
fi

# 创建 helper 的软连接
ln -sf "$CONFIG_DIR/helper.sh" /usr/bin/tailscale-helper
if [ -L /usr/bin/tailscale-helper ]; then
    log_info "✅  软连接已成功创建：$CONFIG_DIR/helper.sh -> /usr/bin/tailscale-helper"
else
    log_warn "⚠️  创建软连接失败（可能 /usr/bin 不存在或只读）"
fi

# 初始化通知配置（若不存在则创建）
[ -f "$CONFIG_DIR/notify.conf" ] || cat > "$CONFIG_DIR/notify.conf" <<'EOF'
# 通知开关 (1=启用 0=禁用)
NOTIFY_UPDATE=1
NOTIFY_MIRROR_FAIL=1
NOTIFY_EMERGENCY=1

NOTIFY_SERVERCHAN=0
SERVERCHAN_KEY=""
NOTIFY_BARK=0
BARK_KEY=""
NOTIFY_NTFY=0
NTFY_KEY=""
NOTIFY_PUSHPLUS=0
PUSHPLUS_TOKEN=""
EOF

exec 9>&-
log_info "✅  配置工具安装完毕!"
log_info "✅  运行 tailscale-helper 可以打开功能菜单"

# 非交互模式：直接退出，避免 read 阻塞
if ! is_interactive; then
    exit 0
fi

log_info "👋  回车直接执行, 输入其他字符退出: " 1
read -r choice
if [ -z "$choice" ]; then
    tailscale-helper
else
    log_info "👋  退出脚本....."
    sleep 1
    clear 2>/dev/null || true
    exit 0
fi
