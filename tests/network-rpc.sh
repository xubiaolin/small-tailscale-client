#!/bin/sh
# 在隔离的 OpenWrt x86/64 rootfs 镜像中验证 RPC 和内核实际加载的 fw4 规则。
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
docker run --rm --network none --cap-add NET_ADMIN -i -v "$repo:/src:ro" "${1:-small-ts-openwrt:24.10.8}" sh -eu <<'SCENARIOS'
mkdir -p /var/run/ubus /var/lock /usr/libexec/rpcd /usr/share/small-tailscale/scripts
cp /src/luci-app-small-tailscale/root/usr/libexec/rpcd/small-tailscale* /usr/libexec/rpcd/
cp /src/luci-app-small-tailscale/root/usr/share/small-tailscale/sync /usr/share/small-tailscale/
cp /src/scripts/*.sh /usr/share/small-tailscale/scripts/
echo project > /tmp/source
printf '#!/bin/sh\ncat /tmp/source\n' > /usr/share/small-tailscale/source
chmod +x /usr/share/small-tailscale/source /usr/share/small-tailscale/scripts/*.sh
cat > /etc/config/network <<'UCI'
config interface 'loopback'
	option device 'lo'
	option proto 'none'
UCI
ubusd >/tmp/ubus.log 2>&1 &
for attempt in 1 2 3 4 5; do ubus list >/dev/null 2>/dev/null && break; sleep 1; done
netifd >/tmp/netifd.log 2>&1 &
ubus -t 5 wait_for network
rpcd >/tmp/rpcd.log 2>&1 &
ubus -t 5 wait_for small-tailscale.network
ubus -t 5 wait_for small-tailscale
call() { ubus call small-tailscale.network "$1" "$2"; }
preview() { call preview "{\"routes\":\"$1\"}"; }
field() {
	value=$(jsonfilter -s "$1" -e "@.$2") && [ -n "$value" ] || { echo "$1" >&2; return 1; }
	printf '%s\n' "$value"
}
snapshot() { sha256sum /etc/config/network /etc/config/firewall; }
save_routes() {
	saved=$(ubus call small-tailscale save "{\"mode\":\"local\",\"auto_update\":false,\"pinned_version\":\"\",\"mirror\":\"https://github.com\",\"params\":{\"advertise-routes\":\"$1\"}}")
	[ "$(field "$saved" ok)" = true ]
}
before=$(snapshot)
result=$(preview '192.168.1.0/24')
description=$(field "$result" preview)
echo "$description" | grep -Fq tailscale0
echo "$description" | grep -Fq 192.168.1.0/24
token=$(field "$result" token)
[ "$before" = "$(snapshot)" ]
apply() { call apply "{\"routes\":\"$1\",\"token\":\"$2\"}"; }
fw4 start
input_before=$(nft list chain inet fw4 input)
field "$(preview '192.168.1.7/24')" error >/dev/null
field "$(preview '192.168.1.0/33')" error >/dev/null
field "$(apply '10.0.0.0/8' "$token")" error >/dev/null
field "$(apply '192.168.1.0/24' "$token")" error | grep -Fq '保存'
[ "$before" = "$(snapshot)" ]
save_routes '192.168.1.0/24'
save_routes '10.0.0.0/8'
conflict=$(apply '192.168.1.0/24' "$token")
[ "$(field "$conflict" code)" = saved_routes_changed ]
[ "$(field "$conflict" saved_routes)" = '10.0.0.0/8' ]
[ "$before" = "$(snapshot)" ]
save_routes '192.168.1.0/24'
# 使用登录会话的专有暂存区，既有预览也不能覆盖其他浏览器未提交的更改。
sid=$(field "$(ubus call session create '{}')" ubus_rpc_session)
ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"network\",\"write\"]]}"
ubus call uci set "{\"ubus_rpc_session\":\"$sid\",\"config\":\"network\",\"section\":\"loopback\",\"values\":{\"auto\":\"0\"}}"
field "$(preview '192.168.1.0/24')" error >/dev/null
field "$(apply '192.168.1.0/24' "$token")" error >/dev/null
[ "$before" = "$(snapshot)" ]
ubus call uci revert "{\"ubus_rpc_session\":\"$sid\",\"config\":\"network\"}"
# 已应用、等待确认的 rpcd 回滚快照也能覆盖防火墙。
ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"firewall\",\"write\"]]}"
ubus call uci add "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\",\"type\":\"rule\",\"name\":\"sessiontest\",\"values\":{\"enabled\":\"0\"}}" >/dev/null
ubus call uci apply "{\"ubus_rpc_session\":\"$sid\",\"rollback\":true,\"timeout\":60}"
field "$(preview '192.168.1.0/24')" error >/dev/null
ubus call uci rollback "{\"ubus_rpc_session\":\"$sid\"}"
[ "$before" = "$(snapshot)" ]
ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}"
applied=$(field "$(apply '192.168.1.0/24' "$token")" token)
field "$(apply '192.168.1.0/24' "$applied")" token >/dev/null
uci show network | grep -Fq "device='tailscale0'"
forward=$(nft list chain inet fw4 forward)
echo "$forward" | grep -F 'iifname "tailscale0" ip daddr 192.168.1.0/24' | grep -q accept
[ "$input_before" = "$(nft list chain inet fw4 input)" ]
save_routes ''
conflict=$(apply '192.168.1.0/24' "$token")
[ "$(field "$conflict" code)" = saved_routes_changed ]
echo "$conflict" | grep -Eq '"saved_routes":[[:space:]]*""'
[ "$forward" = "$(nft list chain inet fw4 forward)" ]
# 替换、重复应用和清空网段均以已加载的内核规则为准。
confirm() {
	preview_token=$(field "$(preview "$1")" token)
	save_routes "$1"
	field "$(apply "$1" "$preview_token")" token >/dev/null
}
field "$(apply '10.0.0.0/8' "$token")" error >/dev/null
description=$(field "$(preview '10.8.0.0/16,fd71::/64')" preview)
echo "$description" | grep -Fq 192.168.1.0/24
confirm '10.8.0.0/16,fd71::/64'
confirm '10.8.0.0/16,fd71::/64'
forward=$(nft list chain inet fw4 forward)
[ "$(echo "$forward" | grep -c 'iifname "tailscale0"')" = 2 ]
echo "$forward" | grep -F 'iifname "tailscale0" ip daddr 10.8.0.0/16' | grep -q accept
echo "$forward" | grep -F 'iifname "tailscale0" ip6 daddr fd71::/64' | grep -q accept
confirm ''
forward=$(nft list chain inet fw4 forward)
if echo "$forward" | grep -q tailscale0; then exit 1; fi
# 保留用户已有的同名配置和指向尚未创建接口的防火墙区。
uci set firewall.smallts_subnets=rule
uci set firewall.smallts_subnets.name=User
uci commit firewall
before=$(snapshot)
field "$(preview '192.168.1.0/24')" error >/dev/null
[ "$before" = "$(snapshot)" ]
uci delete firewall.smallts_subnets
uci delete network.smallts
uci set firewall.later=zone
uci set firewall.later.name=existing
uci add_list firewall.later.network=smallts
uci set firewall.later.input=ACCEPT
uci commit
field "$(preview '192.168.1.0/24')" error >/dev/null
uci delete firewall.later
uci commit firewall
token=$(field "$(preview '192.168.1.0/24')" token)
before=$(snapshot)
echo external > /tmp/source
field "$(apply '192.168.1.0/24' "$token")" error >/dev/null
[ "$before" = "$(snapshot)" ]
echo project > /tmp/source
save_routes '192.168.1.0/24'
# 模拟 fw4 校验失败，持久配置和实际转发策略都应恢复。
mv /sbin/fw4 /sbin/fw4.real
printf '#!/bin/sh\n[ "$1" != check ] || exit 1\nexec /sbin/fw4.real "$@"\n' > /sbin/fw4
chmod +x /sbin/fw4
field "$(apply '192.168.1.0/24' "$token")" error >/dev/null
[ "$before" = "$(snapshot)" ]
forward=$(nft list chain inet fw4 forward)
if echo "$forward" | grep -q tailscale0; then exit 1; fi
# 部分 fw4 版本会吞掉 nft 加载的退出码，RPC 以实际规则为准。
printf '#!/bin/sh\n[ "$1" != reload ] || exit 0\nexec /sbin/fw4.real "$@"\n' > /sbin/fw4
field "$(apply '192.168.1.0/24' "$token")" error >/dev/null
[ "$before" = "$(snapshot)" ]
mv /sbin/fw4.real /sbin/fw4
field "$(apply '192.168.1.0/24' "$token")" token >/dev/null
# 单独移除网页插件保留运行中的策略，随后仍可清理节点。
netrpc=/usr/libexec/rpcd/small-tailscale.network
sh /src/luci-app-small-tailscale/prerm
rm "$netrpc"
nft list chain inet fw4 forward | grep -Fq 'iifname "tailscale0"'
/usr/libexec/small-tailscale-network-cleanup cleanup
if uci -q get firewall.smallts_subnets || uci -q get network.smallts; then exit 1; fi
if nft list chain inet fw4 forward | grep -Fq 'iifname "tailscale0"'; then exit 1; fi
# 用户原有的同名接口和已修改的规则必须保留。
cp /usr/libexec/small-tailscale-network-cleanup "$netrpc"
uci set network.smallts=interface
uci set network.smallts.proto=none
uci set network.smallts.device=tailscale0
uci commit network
confirm '10.0.0.0/8'
uci set firewall.smallts_subnets.enabled=0
uci commit firewall
before=$(snapshot)
"$netrpc" cleanup
[ "$before" = "$(snapshot)" ]
SCENARIOS
