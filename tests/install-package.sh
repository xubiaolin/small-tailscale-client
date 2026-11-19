#!/bin/sh
# 在对应版本的官方 x86/64 rootfs 中通过 LuCI 安装本地发布包。
set -eu
[ "$#" -eq 2 ] || { echo "用法: sh tests/install-package.sh <rootfs.tar.gz> <dist>" >&2; exit 2; }
rootfs=$(realpath "$1")
dist=$(realpath "$2")
tests=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
(cd "$dist" && sha256sum -c SHA256SUMS)
image=$(docker import "$rootfs")
container=''
cleanup() {
    [ -z "$container" ] || docker rm -f "$container" >/dev/null
    docker image rm "$image" >/dev/null || true
}
trap cleanup EXIT
container=$(docker create -i -v "$dist:/dist:ro" -v "$tests:/tests:ro" "$image" /bin/sh -se)
docker start -ai "$container" <<'OPENWRT'
mkdir -p /var/run/ubus /var/lock /tmp/log
/sbin/ubusd &
for i in 1 2 3 4 5; do [ ! -S /var/run/ubus/ubus.sock ] || break; sleep 1; done
/sbin/procd &
ubus -t 15 wait_for service
/etc/init.d/rpcd start
ubus -t 15 wait_for session

name=luci-app-small-tailscale
if command -v apk >/dev/null; then
    set -- /dist/"$name"-*.apk
    [ "$#" = 1 ] && [ -f "$1" ]
    file=${1##*/}
    version=${file#"$name"-}
    version=${version%.apk}
    cp /dist/small-tailscale.pem /etc/apk/keys/small-tailscale.pem
    apk update
    cp "$1" /tmp/upload.apk
    sh /tests/package.sh /tmp/upload.apk
    apk query --installed --fields name,version,arch --format json "$name" > /tmp/package.json
    [ "$(jsonfilter -i /tmp/package.json -e '@[0].name')" = "$name" ]
    [ "$(jsonfilter -i /tmp/package.json -e '@[0].version')" = "$version" ]
    [ "$(jsonfilter -i /tmp/package.json -e '@[0].arch')" = noarch ]
else
    set -- /dist/"$name"_*_all.ipk
    [ "$#" = 1 ] && [ -f "$1" ]
    file=${1##*/}
    version=${file#"$name"_}
    version=${version%_all.ipk}
    opkg update
    cp "$1" /tmp/upload.ipk
    sh /tests/package.sh /tmp/upload.ipk
    opkg status "$name" > /tmp/package.control
    grep -Fx "Package: $name" /tmp/package.control
    grep -Fx "Version: $version" /tmp/package.control
    grep -Fx "Architecture: all" /tmp/package.control
fi
# 单独移除 LuCI 时，包管理器应执行卸载钩子，保留节点和后续清理入口。
touch /etc/config/network
uci set network.smallts=interface
uci set network.smallts.device=tailscale0
uci set network.smallts.proto=none
uci set network.smallts.small_tailscale_managed=1
uci commit network
if command -v apk >/dev/null; then apk del "$name"; else opkg remove "$name"; fi
test ! -e /usr/libexec/rpcd/small-tailscale.network
test -x /usr/libexec/small-tailscale-network-cleanup
test "$(uci get network.smallts.device)" = tailscale0

OPENWRT
