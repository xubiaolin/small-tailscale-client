#!/bin/sh
set -eu

mode=build
if [ "$#" -eq 1 ] && [ "$1" = --check ]; then
    mode=check
elif [ "$#" -ne 0 ]; then
    echo "用法: sh tools/package-cli.sh [--check]" >&2
    exit 2
fi

export LC_ALL=C
unset TAR_OPTIONS GZIP
cd "$(dirname "$0")/.."
archive=tailscale-openwrt-scripts.tar.gz
work=$(mktemp -d "$PWD/.package-cli.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# 将脚本直接解压到安装目录，归档中不记录安装目录自身的权限。
(
    cd scripts
    tar --format=ustar --sort=name --mtime=@0 --owner=0 --group=0 \
        --numeric-owner --mode=0755 --hard-dereference -cf "$work/scripts.tar" -- ./*
)
gzip -n -9 -c "$work/scripts.tar" > "$work/$archive"
sha256=$(sha256sum < "$work/$archive")
md5=$(md5sum < "$work/$archive")

awk -v sha="${sha256%% *}" -v md5="${md5%% *}" '
    /^EXPECTED_CHECKSUM_SHA256=/ { print "EXPECTED_CHECKSUM_SHA256=\"" sha "\""; sha_lines++; next }
    /^EXPECTED_CHECKSUM_MD5=/ { print "EXPECTED_CHECKSUM_MD5=\"" md5 "\""; md5_lines++; next }
    { print }
    END { if (sha_lines != 1 || md5_lines != 1) exit 1 }
' install.sh > "$work/install.sh" || {
    echo "install.sh 应分别包含一个 SHA256 和 MD5 校验值定义" >&2
    exit 1
}

if [ "$mode" = check ]; then
    if ! cmp "$archive" "$work/$archive" || ! cmp install.sh "$work/install.sh"; then
        echo "请运行 sh tools/package-cli.sh 更新归档和校验值" >&2
        exit 1
    fi
else
    chmod 0644 "$work/$archive"
    chmod --reference=install.sh "$work/install.sh"
    mv -f "$work/$archive" "$archive"
    mv -f "$work/install.sh" install.sh
fi
