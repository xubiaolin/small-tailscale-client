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
./autoupdate.sh --manual >/dev/null
[ "$(cat /tmp/tailscaled)" = v1.89.0 ]
cp install.conf /tmp/config-before
cat >/etc/init.d/tailscale <<'MOCK'
#!/bin/sh
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
./setup.sh --local --version=v1.95.0 --auto-update >/dev/null
grep -qx PINNED_VERSION=v1.95.0 install.conf
grep -qx v1.95.0 /usr/local/bin/tailscaled
grep -qx enable /tmp/service-actions
grep -qx restart /tmp/service-actions
rm /tmp/service-actions
./setup_service.sh --refresh >/dev/null
[ ! -e /tmp/service-actions ] || { echo '刷新脚本时操作了正在运行的服务' >&2; exit 1; }

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
