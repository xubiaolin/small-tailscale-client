"""从仓库根目录运行。发布前检查包和 README，发布后匿名核对下载。"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


PACKAGE = "luci-app-small-tailscale"
# 首个正式版本 luci-v1.0.0-r1 分发给路由器的 APK 验签公钥。
KEY_SHA256 = "ae5322847afa7a3261450797dd70613c24969115d08b5cd144f564e590971a48"
KEY = "small-tailscale.pem"
SUMS = "SHA256SUMS"


def release_files(tag, repo):
    build = Path(PACKAGE, "build.sh").read_text()
    match = re.search(r"^version=([0-9][0-9A-Za-z._+~-]*-r[0-9]+)$", build, re.MULTILINE)
    if not match:
        raise SystemExit("无法从 build.sh 读取包版本")
    version = match[1]
    if tag != f"luci-v{version}":
        raise SystemExit(f"标签 {tag} 与包版本 {version} 不符")
    ipk = f"{PACKAGE}_{version}_all.ipk"
    apk = f"{PACKAGE}-{version}.apk"
    base = f"https://github.com/{repo}/releases"
    urls = {name: f"{base}/download/{tag}/{name}" for name in (ipk, apk, KEY, SUMS)}
    expected = set(urls.values()) | {f"{base}/tag/{tag}"}
    for filename in ("README.md", "README_EN.md"):
        readme = Path(filename).read_text()
        targets = re.findall(r"\]\(([^\s)]+)\)", readme)
        luci_links = {url for url in targets if re.search(r"/releases/(?:download|tag)/luci-v", url)}
        if luci_links != expected:
            raise SystemExit(f"{filename} 的 LuCI Release 链接与 {tag} 的四项资产或版本页不符")
        for branch, name in (("24.10", ipk), ("25.12", apk)):
            row = re.search(rf"^\|\s*{re.escape(branch)}\s*\|(.+)$", readme, re.MULTILINE)
            if not row or f"]({urls[name]})" not in row[1]:
                raise SystemExit(f"{filename} 的 OpenWrt {branch} 安装链接与 {name} 不符")
    return urls


def verify_files(directory, names):
    if {p.name for p in directory.iterdir()} != set(names):
        raise SystemExit(f"{directory} 必须且只能包含 {', '.join(names)}")
    digests = {}
    for name in names:
        path = directory / name
        if path.is_symlink() or not path.is_file() or not path.stat().st_size:
            raise SystemExit(f"无效的资产文件 {path}")
        digests[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    if digests[KEY] != KEY_SHA256:
        raise SystemExit("APK 公钥与已分发的正式公钥不符")
    expected = sorted(f"{digest}  {name}" for name, digest in digests.items() if name != SUMS)
    if sorted((directory / SUMS).read_text().splitlines()) != expected:
        raise SystemExit(f"{directory / SUMS} 与 IPK、APK 或公钥不符")
    return digests


def download(urls, destination):
    destination.mkdir(parents=True, exist_ok=True)
    for name, url in urls.items():
        # -q 必须是第一个参数，避免从用户的 .curlrc 继承认证信息。
        subprocess.run(["curl", "-q", "--fail", "--silent", "--show-error", "--location",
                        "--proto", "=https", "--proto-redir", "=https", "--max-time", "120",
                        "--retry", "4", "--retry-all-errors", "--output", destination / name, url],
                       check=True)
    return verify_files(destination, urls)


def find_release(repo, tag):
    # 列表包含当前令牌可见的草稿。查询失败会中止，只有成功查无结果才允许创建。
    result = subprocess.check_output(["gh", "api", "--paginate", f"repos/{repo}/releases?per_page=100",
                                      "--jq", f'.[] | select(.tag_name == "{tag}")'], text=True)
    return json.loads(result) if result.strip() else None


def missing_assets(release, digests):
    missing = set(digests)
    for asset in release["assets"]:
        name = asset["name"]
        if (name not in missing or asset["state"] != "uploaded"
                or asset["digest"] != f"sha256:{digests[name]}"):
            raise SystemExit(f"Release 资产 {name} 与本地构建不符")
        missing.remove(name)
    return missing


def publish(tag, repo, directory, digests):
    gh = ["gh", "release"]
    options = ["--repo", repo]
    release = find_release(repo, tag)
    if release is None:
        notes = "OpenWrt 24.10 使用 IPK，25.12 使用 APK。请核对 SHA256SUMS，首次安装 APK 时导入 small-tailscale.pem。"
        subprocess.run([*gh, "create", tag, *options, "--verify-tag", "--draft", "--latest=false",
                        "--target", os.environ["GITHUB_SHA"], "--title", tag, "--notes", notes], check=True)
        release = find_release(repo, tag)
        if release is None:
            raise SystemExit("无法读取新建的 Release 草稿")
    missing = missing_assets(release, digests)
    if not release["draft"]:
        if missing:
            raise SystemExit(f"已发布的 {tag} 缺少 {', '.join(sorted(missing))}")
        print(f"{tag} 已发布，四项资产摘要均与本地构建一致")
        return
    if missing:
        subprocess.run([*gh, "upload", tag, *options, *(directory / name for name in sorted(missing))], check=True)
    release = find_release(repo, tag)
    if release is None or missing_assets(release, digests):
        raise SystemExit("草稿资产不完整")
    if release["draft"]:
        subprocess.run([*gh, "edit", tag, *options, "--verify-tag", "--draft=false", "--latest=false"], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "xubiaolin/small-tailscale-client"))
    parser.add_argument("tag")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("links")
    for command in ("verify", "publish", "download"):
        sub = commands.add_parser(command)
        sub.add_argument("directory", type=Path)
        if command == "download":
            sub.add_argument("--compare", type=Path)
    args = parser.parse_args()
    urls = release_files(args.tag, args.repo)
    if args.command == "download":
        downloaded = download(urls, args.directory)
        if args.compare and downloaded != verify_files(args.compare, urls):
            raise SystemExit("README 下载的资产与本地构建不一致")
    elif args.command != "links":
        digests = verify_files(args.directory, urls)
        if args.command == "publish":
            publish(args.tag, args.repo, args.directory, digests)


if __name__ == "__main__":
    main()
