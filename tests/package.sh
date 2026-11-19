#!/bin/sh
# 在已刷新软件源的干净 OpenWrt 测试系统上运行，APK 测试须先导入对应公钥。
set -eu
package=${1:?用法: sh tests/package.sh /tmp/安装包}
result=$(/usr/libexec/package-manager-call install "$package")
printf '%s\n' "$result"
test "$(printf '%s' "$result" | jsonfilter -e '@.code')" = 0
ubus -t 10 wait_for small-tailscale small-tailscale.network
test -x /usr/libexec/rpcd/small-tailscale
/usr/libexec/rpcd/small-tailscale list | grep -q '"status"'
test -x /usr/libexec/rpcd/small-tailscale.network
/usr/libexec/rpcd/small-tailscale.network list | grep -q '"preview"'
test -x /usr/share/small-tailscale/scripts/tailscale_up_generator.sh
test "$(/usr/share/small-tailscale/source)" = none
test -s /www/luci-static/resources/view/small-tailscale/manage.js
test -s /www/luci-static/resources/view/small-tailscale/logs.js
test -s /usr/share/luci/menu.d/luci-app-small-tailscale.json
test -s /usr/share/rpcd/acl.d/luci-app-small-tailscale.json
