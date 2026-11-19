"""为二进制发布工作流选择尚未发布的版本。"""

import json
import os
import re
from urllib.request import Request, urlopen


VERSION = r"[0-9]+\.[0-9]+\.[0-9]+"


def release_tags(repo):
    tags = []
    page = 1
    while True:
        request = Request(f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}",
                          headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"]})
        with urlopen(request, timeout=30) as response:
            releases = json.load(response)
        tags.extend(item["tag_name"].removeprefix("v") for item in releases)
        if len(releases) < 100:
            return tags
        page += 1


def version_key(tag):
    return tuple(map(int, tag.split(".")))


def select_versions(requested, official, published):
    available = [tag for tag in official if re.fullmatch(VERSION, tag)]
    if not available:
        raise ValueError("上游没有可用版本")
    selected = set()
    for part in (requested or available[0]).split(","):
        if not re.fullmatch(rf"{VERSION}(?:-{VERSION})?", part):
            raise ValueError("版本应为三段数字，可用逗号分隔版本或范围")
        start, sep, end = part.partition("-")
        if not sep:
            selected.add(start)
            continue
        low, high = version_key(start), version_key(end)
        if low > high:
            raise ValueError("版本范围的起点不能高于终点")
        selected.update(tag for tag in available if low <= version_key(tag) <= high)
    return sorted(selected.difference(published), key=version_key) or ["skip"]


if __name__ == "__main__":
    versions = select_versions(os.environ["REQUESTED_VERSIONS"], release_tags(os.environ["REPO_OFFICIAL"]),
                               release_tags(os.environ["GITHUB_REPOSITORY"]))
    print("matrix=" + json.dumps(versions, separators=(",", ":")))
