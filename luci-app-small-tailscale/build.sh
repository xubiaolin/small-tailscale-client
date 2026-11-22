#!/bin/sh
set -eu
umask 022
export LC_ALL=C TZ=UTC
if [ "$#" -ne 2 ]; then
    echo "用法: APK_SIGNING_KEY=/路径/私钥.pem $0 <24.10 SDK 目录> <25.12 SDK 目录>" >&2
    exit 2
fi
app=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=$(dirname "$app")
sdk24=$(realpath "$1")
sdk25=$(realpath "$2")
: "${APK_SIGNING_KEY:?请设置 APK 签名私钥的路径}"
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$project" log -1 --format=%ct -- scripts luci-app-small-tailscale)}
export SOURCE_DATE_EPOCH
package=luci-app-small-tailscale
version=1.0.2-r1
dependencies='luci-base rpcd ucode ucode-mod-fs ucode-mod-uci firewall4 nftables-json kmod-tun ca-bundle curl coreutils-timeout'
description='LuCI management for the small Tailscale client'
out=${DIST_DIR:-"$project/dist"}
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root=$tmp/root
artifacts=$tmp/artifacts
mkdir -p "$artifacts" "$root/www" "$root/usr/share/small-tailscale/scripts"
cp -R "$app/root/." "$root/"
cp -R "$app/htdocs/." "$root/www/"
find "$root" -type d -exec chmod 755 {} +
find "$root" -type f -exec chmod 644 {} +
chmod 755 "$root/usr/libexec/rpcd/"*
for command in job source sync; do chmod 755 "$root/usr/share/small-tailscale/$command"; done
install -m 755 "$project"/scripts/*.sh "$root/usr/share/small-tailscale/scripts/"
mkdir "$root/CONTROL"
cat > "$root/CONTROL/control" <<CONTROL
Package: $package
Version: $version
Architecture: all
Depends: $(printf '%s' "$dependencies" | sed 's/ /, /g')
Section: luci
License: MIT
Installed-Size: 0
Description: $description
CONTROL
install -m 755 "$app/postinst" "$app/prerm" "$root/CONTROL/"
TAR_OPTIONS='--owner=0 --group=0' PKG_SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH \
    "$sdk24/scripts/ipkg-build" "$root" "$artifacts"
rm -r "$root/CONTROL"
# apk 会记录暂存目录内各文件的修改时间和所有者。
find "$root" -exec touch --date="@$SOURCE_DATE_EPOCH" {} +
STAGING_DIR_HOST=$sdk25/staging_dir/host
export STAGING_DIR_HOST
"$STAGING_DIR_HOST/bin/fakeroot" "$STAGING_DIR_HOST/bin/apk" mkpkg \
    --info "name:$package" --info "version:$version" --info arch:noarch \
    --info license:MIT --info "description:$description" --info "depends:$dependencies" \
    --script "post-install:$app/postinst" --script "post-upgrade:$app/postinst" \
    --script "pre-deinstall:$app/prerm" --files "$root" --sign-key "$APK_SIGNING_KEY" --output "$artifacts/$package-$version.apk"
openssl pkey -in "$APK_SIGNING_KEY" -pubout -out "$artifacts/small-tailscale.pem"
(cd "$artifacts" && sha256sum *.ipk *.apk *.pem > SHA256SUMS)
cp "$artifacts/"* "$out/"
