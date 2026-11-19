#!/bin/sh
# 在隔离的官方 OpenWrt rootfs 中运行，仓库只读挂载于 /src。
set -e
[ -f /.dockerenv ] && [ -d /src/scripts ] || exit 1
. /src/scripts/tools.sh

[ "$(detect_arch armv8l)" = arm ]
[ "$(detect_arch aarch64)" = arm64 ]
(
    hexdump() { echo "$order"; }
    order=1
    [ "$(detect_arch mips64)" = mips64le ]
    [ "$(detect_arch mips)" = mipsle ]
    order=2
    [ "$(detect_arch mips64)" = mips64 ]
    [ "$(detect_arch mips)" = mips ]
    uname() { echo armv8l; }
    ARCH=arm64
    ensure_arch
    [ "$ARCH" = arm ]
)

# 保留传输错误，即便服务器已经送出 HTTP 200。
(
    curl() { printf 200; return 18; }
    timeout() { shift; "$@"; }
    if webget /tmp/download https://example.test/file echooff; then exit 1; fi
)
# OpenWrt 的 wget 使用原生退出状态，证书验证应保持启用。
(
    command() {
        if [ "$1 $2" = '-v curl' ]; then return 1; fi
        [ "$1 $2" = '-v wget' ]
    }
    timeout() { shift; "$@"; }
    wget() {
        for arg do [ "$arg" != '--no-check-certificate' ] || return 1; done
        [ "$*" = '-q --header=User-Agent: Tailscale-Helper -O /tmp/download https://example.test/file' ]
    }
    webget /tmp/download https://example.test/file echooff
    wget() { return 5; }
    if webget /tmp/download https://example.test/file echooff; then exit 1; fi
)

# 用系统自带的 JSON 编解码器核对多行通知，模拟服务端业务失败。
cat >"$NTF_CONF" <<'CONF'
NOTIFY_PUSHPLUS=1
PUSHPLUS_TOKEN=test-token
CONF
curl() {
    [ "$7" = 'Content-Type: application/json' ] && [ "$8" = --data-binary ] &&
    [ "${10}" = https://www.pushplus.plus/send ] || return 1
    printf '%s' "$9" > /tmp/push-body
    printf '{"code":%s}' "$push_code"
}
push_code=200
send_notify '更新"通知"' '第一行' '第二行' >/dev/null
expected=$(printf '更新"通知"\n第一行\n第二行')
[ "$(jsonfilter -i /tmp/push-body -e '@.content')" = "$expected" ]
[ "$(jsonfilter -i /tmp/push-body -e '@.token')" = test-token ]
push_code=500
if send_notify '测试' '重试' >/dev/null; then exit 1; fi

# 通过真正的 bootstrap 入口，验证依赖和外部节点保护；下载使用受检归档。
rm "$NTF_CONF"
mkdir -p /tmp/mock-bin
export PATH="/tmp/mock-bin:$PATH"
cat >/tmp/mock-bin/curl <<'MOCK'
#!/bin/sh
while [ "$#" -gt 1 ]; do
    if [ "$1" = -o ]; then cp /src/tailscale-openwrt-scripts.tar.gz "$2"; exit; fi
    shift
done
exit 1
MOCK
printf '#!/bin/sh\nexit 0\n' >/tmp/mock-bin/ntpdate
printf '#!/bin/sh\nshift\nexec "$@"\n' >/tmp/mock-bin/timeout
if command -v apk >/dev/null; then
    pm=apk
    list=info
    printf '%s\n' ca-certificates curl coreutils-timeout >/tmp/installed
else
    pm=opkg
    list=list-installed
    printf '%s - 1.0\n' libustream-mbedtls ca-bundle curl coreutils-timeout >/tmp/installed
fi
export list
cat >"/tmp/mock-bin/$pm" <<'MOCK'
#!/bin/sh
case "$1" in
    "$list") [ "$#" = 1 ] && cat /tmp/installed ;;
    add|install) echo "$2" >>/tmp/requested ;;
    update) exit 0 ;;
    *) exit 1 ;;
esac
MOCK
chmod +x /tmp/mock-bin/*
test ! -e /etc/init.d/tailscale
echo '# external service' > /etc/init.d/tailscale
if sh /src/install.sh >/dev/null; then exit 1; fi
[ ! -e /etc/tailscale/helper.sh ]
[ "$(cat /etc/init.d/tailscale)" = '# external service' ]
rm /etc/init.d/tailscale /tmp/requested
sh /src/install.sh >/dev/null
[ "$(cat /tmp/requested)" = kmod-tun ]
[ -x /usr/bin/tailscale-helper ]
[ "$(sh /etc/tailscale/source.sh)" = project ]
