#!/bin/sh
# 在隔离的 BusyBox 文件系统中运行。宿主机仅需 Docker。
set -eu
if [ "${1:-}" != "--container" ]; then
    repo=$(cd "$(dirname "$0")/.." && pwd)
    exec docker run --rm --network none -v "$repo:/repo:ro" alpine:3.22 sh /repo/tests/cli.sh --container
fi
[ -f /.dockerenv ] && [ -f /repo/scripts/setup.sh ] || exit 1
cd /etc
mkdir -p tailscale init.d crontabs /usr/local/bin
cp /repo/scripts/*.sh tailscale/
chmod +x tailscale/*.sh
cd tailscale
cat >/usr/local/bin/tailscale <<'MOCK'
#!/bin/sh
printf '%s\n' "$@"
MOCK
chmod +x /usr/local/bin/tailscale

cat >tailscale_up.conf <<'CONF'
--accept-dns="false"
--hostname="test node *"
CONF
actual=$(printf '0\n' | ./tailscale_up_generator.sh --run)
expected=$(printf '%s\n' up --accept-dns=false '--hostname=test node *')
[ "$actual" = "$expected" ] || { echo "启动时未逐项传递已保存参数" >&2; exit 1; }

./github_direct_ctl.sh https://mirror.example/github/ >/dev/null
[ "$(cat github-download.env)" = 'GITHUB_DOWNLOAD_BASE_URL=https://mirror.example/github' ]
./github_direct_ctl.sh </dev/null | grep -Fq https://mirror.example/github

cat >install.conf <<'CONF'
MODE=tmp
AUTO_UPDATE=true
VERSION=v1.89.0
CONF
echo v1.90.0 >current_version
./update_ctl.sh --version=v1.90.0 >/dev/null
grep -qx 'PINNED_VERSION=v1.90.0' install.conf
./update_ctl.sh --version=latest >/dev/null
grep -qx 'PINNED_VERSION=' install.conf

# 模拟发布镜像，只允许访问持久保存的地址。使用真实的 SHA256 校验。
cat >/usr/local/bin/curl <<'MOCK'
#!/bin/sh
while [ "$#" -gt 1 ]; do
    if [ "$1" = -o ]; then shift; out=$1; fi
    shift
done
case "$1" in
    https://mirror.example/github/*) ;;
    *) printf 404; exit 0 ;;
esac
release=${1%/*}
tag=${release##*/}
bin="tailscaled-linux-amd64"
case "${1##*/}" in
    version.txt) echo v1.92.0 > "$out" ;;
    SHA256SUMS.txt) printf '%s\n' "$tag" | sha256sum | sed "s/  -/  $bin/" > "$out" ;;
    "$bin") printf '%s\n' "$tag" > "$out" ;;
    *) printf 404; exit 0 ;;
esac
printf 200
MOCK
chmod +x /usr/local/bin/curl
echo ARCH=amd64 >>install.conf
# 接入旧节点时，历史的安装 VERSION 不能变成锁定选择。
sed -i '/^PINNED_VERSION=/d' install.conf
./autoupdate.sh --on-start >/dev/null
grep -qx v1.92.0 /tmp/tailscaled
./update_ctl.sh --version=v1.90.0 >/dev/null
rm /tmp/tailscaled
./autoupdate.sh --on-start >/dev/null
[ "$(cat /tmp/tailscaled)" = v1.90.0 ] || { echo '重启下载了错误版本' >&2; exit 1; }

./update_ctl.sh --version=latest >/dev/null
./autoupdate.sh --on-start >/dev/null
[ "$(cat /tmp/tailscaled)" = v1.92.0 ]
grep -qx 'v1.92.0' current_version
./update_ctl.sh off >/dev/null
./update_ctl.sh --version=v1.89.0 >/dev/null
./autoupdate.sh --on-start >/dev/null
[ "$(cat /tmp/tailscaled)" = v1.89.0 ]
./autoupdate.sh --manual >/dev/null
cp install.conf /tmp/config-before
cat >/etc/init.d/tailscale <<'MOCK'
#!/bin/sh
# /etc/tailscale/tools.sh
echo "$1" >>/tmp/service-actions
MOCK
chmod +x /etc/init.d/tailscale
printf '#!/bin/sh\necho router\n' >/usr/local/bin/uci
chmod +x /usr/local/bin/uci
./github_direct_ctl.sh https://offline.example >/dev/null
if ./setup.sh --tmp --version=v1.95.0 >/dev/null; then exit 1; fi
cmp install.conf /tmp/config-before
grep -qx v1.89.0 /tmp/tailscaled
grep -qx v1.89.0 current_version
[ ! -e /tmp/service-actions ]
grep -q '校验' /var/log/tailscale_install.log

./github_direct_ctl.sh https://mirror.example/github >/dev/null
cat >/etc/rc.common <<'MOCK'
#!/bin/sh
echo "$2" >>/tmp/service-actions
MOCK
printf '#!/bin/sh\nexit 0\n' >/etc/init.d/cron
chmod +x /etc/init.d/cron
backup_job='0 1 * * * tar -czf /tmp/node-backup.tgz /etc/tailscale/'
echo "$backup_job" >/etc/crontabs/root
./setup.sh --local --version=v1.95.0 --auto-update >/dev/null
grep -qx PINNED_VERSION=v1.95.0 install.conf
grep -qx v1.95.0 /usr/local/bin/tailscaled
grep -qx enable /tmp/service-actions
grep -qx restart /tmp/service-actions
[ ! -e /tmp/tailscaled ]
grep -Fxq "$backup_job" /etc/crontabs/root
rm /tmp/service-actions
./setup_service.sh --refresh >/dev/null
[ ! -e /tmp/service-actions ] || { echo '刷新脚本时操作了正在运行的服务' >&2; exit 1; }

# 网页保存待安装模式。下载失败后，启动仍选择 local；下一次成功下载才切换为 tmp。
echo REQUESTED_MODE=tmp >> install.conf
./github_direct_ctl.sh https://offline.example >/dev/null
if ./setup.sh --saved >/dev/null; then exit 1; fi
(
    . /etc/init.d/tailscale
    procd_open_instance() { :; }
    procd_close_instance() { :; }
    procd_set_param() { if [ "$1" = command ]; then echo "$2" > /tmp/boot-binary; fi; }
    start_service
) >/dev/null
grep -qx /usr/local/bin/tailscaled /tmp/boot-binary
grep -qx v1.95.0 /usr/local/bin/tailscaled
[ "$(readlink /usr/bin/tailscale)" = /usr/local/bin/tailscaled ]
./github_direct_ctl.sh https://mirror.example/github >/dev/null
./setup.sh --saved >/dev/null
grep -qx MODE=tmp install.conf
[ "$(readlink /usr/bin/tailscale)" = /tmp/tailscaled ]
grep -qx v1.95.0 /tmp/tailscaled
[ ! -e /usr/local/bin/tailscaled ]

# 从旧节点的菜单直接登录、启动和手动更新。
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >>/tmp/menu-arguments\n' >/usr/local/bin/tailscale
chmod +x /usr/local/bin/tailscale
printf '2\n\n0\n' | TERM=xterm timeout 5 ./helper.sh >/dev/null
grep -qxF -- '--hostname=test node *' /tmp/menu-arguments

# --list 可以在首次接入（包括外部安装）之前读取。
mv /etc/tailscale /tmp/scripts
/tmp/scripts/tailscale_up_generator.sh --list | grep -q '^--login-server:value:'
[ ! -e /etc/tailscale ]
mv /tmp/scripts /etc/tailscale
# 生成可粘贴的命令；它必须与 --run 传递相同的参数。
preview=$(printf 'g\nn\n0\n' | ./tailscale_up_generator.sh)
printf '%s\n' "$preview" | grep -q "tailscale up '--accept-dns=false' '--hostname=test node \*'"

printf '%s\n' '--auth-key="fixture-secret"' >>tailscale_up.conf
preview=$(printf 'g\nn\n0\n' | ./tailscale_up_generator.sh)
printf '%s\n' "$preview" | grep -Fq -- '--auth-key=••••'
if printf '%s\n' "$preview" | grep -Fq fixture-secret; then exit 1; fi
./tailscale_up_generator.sh --run
grep -qxF -- '--auth-key=fixture-secret' /tmp/menu-arguments

# 本地版本先交给 procd，启动后的版本检查在后台执行。
./setup.sh --local --version=v1.95.0 --auto-update >/dev/null
./update_ctl.sh --version=latest >/dev/null
mv autoupdate.sh autoupdate.saved
cat > autoupdate.sh <<'MOCK'
#!/bin/sh
touch /tmp/boot-download
while [ ! -f /tmp/boot-returned ]; do sleep 0.1; done
MOCK
chmod +x autoupdate.sh
(
    . /etc/init.d/tailscale
    procd_open_instance() { :; }
    procd_close_instance() { :; }
    procd_set_param() { if [ "$1" = command ]; then echo "$2" > /tmp/boot-binary; fi; }
    start_service
    [ ! -e /tmp/boot-download ]
    service_started
    touch /tmp/boot-returned
) >/dev/null
for attempt in 1 2 3 4 5; do [ ! -f /tmp/boot-download ] || break; sleep 0.1; done
[ -f /tmp/boot-download ]
grep -qx /usr/local/bin/tailscaled /tmp/boot-binary
mv autoupdate.saved autoupdate.sh

# 更新已校验写入。即使关闭了自动更新，下一次调用也要重试失败的服务重启。
cat >/etc/rc.common <<'MOCK'
#!/bin/sh
echo "$2" >> /tmp/restarts
[ "$2" != restart ] || [ ! -f /tmp/fail-restart ]
MOCK
./update_ctl.sh --version=v1.95.1 >/dev/null
touch /tmp/fail-restart
if ./autoupdate.sh --manual >/dev/null; then exit 1; fi
grep -qx v1.95.1 current_version
rm /tmp/fail-restart
./update_ctl.sh off >/dev/null
./autoupdate.sh >/dev/null
./autoupdate.sh >/dev/null
[ "$(grep -cx restart /tmp/restarts)" = 2 ]

touch /tmp/fail-restart
if ./setup.sh --tmp --version=v1.95.1 >/dev/null; then exit 1; fi
[ -x /usr/local/bin/tailscaled ]
rm /tmp/fail-restart
./autoupdate.sh --manual >/dev/null
[ ! -e /usr/local/bin/tailscaled ]
./setup.sh --local --version=v1.95.1 >/dev/null

# 系统软件源接管后保护服务、程序和节点身份；旧拼写的本项目 helper 仍可接入。
mkdir -p /etc/config
echo identity > /etc/config/tailscaled.state
mv helper.sh helper.saved
sed 's/tailscale_up_generator/tailscale_up_generater/g' helper.saved > helper.sh
[ "$(./source.sh)" = project ]
mv helper.saved helper.sh
touch /etc/config/tailscale
[ "$(./source.sh)" = external ]
for action in './setup.sh --saved' './autoupdate.sh --manual' './uninstall.sh'; do
    if $action >/dev/null 2>&1; then exit 1; fi
done
[ -x /etc/init.d/tailscale ]
grep -qx identity /etc/config/tailscaled.state
grep -qx v1.95.1 /usr/local/bin/tailscaled
rm /etc/config/tailscale

# 清理失败时可重试；成功后保留不属于项目的备份、脚本和任务。
mkdir -p /usr/libexec/rpcd
network=/usr/libexec/rpcd/small-tailscale.network
printf '#!/bin/sh\n[ "$1" = cleanup ] && [ ! -e /tmp/network-error ]\n' > "$network"
chmod +x "$network"
touch /tmp/network-error /usr/local/bin/tailscale-backup /etc/config/tailscaled.state.bak
if ./uninstall.sh >/dev/null; then exit 1; fi
[ -x /etc/init.d/tailscale ]
rm /tmp/network-error
./uninstall.sh >/dev/null
[ -f /usr/local/bin/tailscale-backup ]
[ -f /etc/config/tailscaled.state.bak ]
[ ! -e /etc/config/tailscaled.state ]
[ ! -e /usr/local/bin/tailscaled ]
[ "$(cat /etc/crontabs/root)" = "$backup_job" ]
