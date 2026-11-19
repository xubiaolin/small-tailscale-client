"""Download a checksum-pinned x86/64 OpenWrt test rootfs or unpack its SDK."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile


RELEASES = {
    "24.10.8": ("13.3.0",
                "6c94190246a54088e3984fc0c4cbbb518972abb2b10a28e30a0c41554eea8b9d",
                "ac4a0405d2eea821b06f93c14ba13ffa90ad0457648903df7dde02570027ab21"),
    "25.12.6": ("14.3.0",
                "55e52bb34de582a1ebe56bd50f94ff54ac7c77f5bca9cae807656d1930456da4",
                "1864152619092e781fa36a401960c8e9ae42d6a364c44ee5f0b197ca5f3c0fcc"),
}


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["sdk", "rootfs"])
    parser.add_argument("version", choices=RELEASES)
    parser.add_argument("cache", type=Path)
    args = parser.parse_args()
    gcc, root_hash, sdk_hash = RELEASES[args.version]
    if args.kind == "sdk":
        filename = f"openwrt-sdk-{args.version}-x86-64_gcc-{gcc}_musl.Linux-x86_64.tar.zst"
        digest = sdk_hash
    else:
        filename = f"openwrt-{args.version}-x86-64-rootfs.tar.gz"
        digest = root_hash
    cache = args.cache.resolve()
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / filename
    if not archive.exists() or sha256(archive) != digest:
        url = f"https://downloads.openwrt.org/releases/{args.version}/targets/x86/64/{filename}"
        with tempfile.TemporaryDirectory(dir=cache) as staging:
            download = Path(staging) / filename
            subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location",
                            "--retry", "3", "--max-time", "600", "--output", download, url],
                           check=True)
            if sha256(download) != digest:
                raise SystemExit(f"SHA256 mismatch for {filename}")
            download.replace(archive)
    if args.kind == "rootfs":
        print(archive)
        return
    directory = filename.removesuffix(".tar.zst")
    staging = tempfile.mkdtemp(prefix="sdk-", dir=cache)
    subprocess.run(["tar", "--zstd", "-xf", archive, "-C", staging], check=True)
    print(Path(staging) / directory)


if __name__ == "__main__":
    main()
