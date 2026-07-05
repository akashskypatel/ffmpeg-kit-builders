#!/usr/bin/env bash
set -euo pipefail

source "${SCRIPTDIR}/function.sh"

platform="$1"
arch="$2"
dep="${3:-${GITHUB_WORKFLOW#build_}}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
workspace="${4:-${GITHUB_WORKSPACE:-$repo_root}}"
archive_name="${platform}-${arch}-${dep}.zip"
release_tag="${platform}-${arch}-deps"
release_name="${platform}-${arch}-dependencies"
libraries_dir="${workspace}/prebuilt/${platform}-${arch}/libraries"
token="${GH_TOKEN:-${GITHUB_TOKEN:-$(get_github_token)}}"
repo="${GITHUB_REPOSITORY:-"$(get_github_owner)/$(get_github_repo)"}"

if [[ -z "$token" ]]; then
  echo "GH_TOKEN or GITHUB_TOKEN must be set for release upload" >&2
  exit 1
fi

if [[ -z "$repo" ]]; then
  repo="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"
fi

if [[ -z "$repo" ]]; then
  echo "GITHUB_REPOSITORY must be set or remote.origin.url must point to GitHub" >&2
  exit 1
fi

echo ""
echo "==================================="
echo "upload-deps-release:"
echo "platform: $platform"
echo "arch: $arch"
echo "dep: $dep"
echo "workspace: $workspace"
echo "archive_name: $archive_name"
echo "release_tag: $release_tag"
echo "release_name: $release_name"
echo "libraries_dir: $libraries_dir"
echo "repo: $repo"
echo "==================================="

if [[ ! -d "$libraries_dir" ]]; then
  echo "Missing libraries directory: $libraries_dir" >&2
  exit 1
fi

rm -f "${workspace}/${archive_name}"
(cd "$libraries_dir" && zip -qry "${workspace}/${archive_name}" .)

if ! authorize_github "$token" "${repo#*/}" "${repo%/*}"; then
  exit 1
fi

python3 - "$repo" "$release_tag" "$release_name" "${workspace}/${archive_name}" "$token" <<'PY'
import json
import mimetypes
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, tag, release_name, asset_path, token = sys.argv[1:]
api = "https://api.github.com"
headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}

def request(method, url, data=None, extra_headers=None, allow_404=False):
    body = None
    request_headers = dict(headers)
    if extra_headers:
        request_headers.update(extra_headers)
    if data is not None:
        body = data if isinstance(data, bytes) else json.dumps(data).encode()
        request_headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=body, headers=request_headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            content = response.read()
            return response.status, json.loads(content) if content else None
    except urllib.error.HTTPError as exc:
        if allow_404 and exc.code == 404:
            return exc.code, None
        raise

status, release = request(
    "GET",
    f"{api}/repos/{repo}/releases/tags/{urllib.parse.quote(tag, safe='')}",
    allow_404=True,
)
if status == 404:
    _, release = request("POST", f"{api}/repos/{repo}/releases", {
        "tag_name": tag,
        "name": release_name,
        "draft": False,
        "prerelease": False,
    })

asset_name = pathlib.Path(asset_path).name
page = 1
while True:
    _, assets = request("GET", f"{release['assets_url']}?per_page=100&page={page}")
    if not assets:
        break
    for asset in assets:
        if asset["name"] == asset_name:
            request("DELETE", asset["url"])
            page = None
            break
    if page is None or len(assets) < 100:
        break
    page += 1

upload_url = release["upload_url"].split("{", 1)[0]
content_type = mimetypes.guess_type(asset_name)[0] or "application/octet-stream"
with open(asset_path, "rb") as asset_file:
    request(
        "POST",
        f"{upload_url}?name={urllib.parse.quote(asset_name)}",
        asset_file.read(),
        {"Content-Type": content_type},
    )
PY
