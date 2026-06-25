#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <platform> <arch>" >&2
	exit 2
fi

platform="$1"
arch="$2"
workflow_name="${GITHUB_WORKFLOW:?GITHUB_WORKFLOW must be set}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
workspace="${GITHUB_WORKSPACE:-$(pwd)}"
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if [[ -z "$token" ]]; then
	echo "GH_TOKEN or GITHUB_TOKEN must be set to download dependency release assets" >&2
	exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$platform" in
	iphonesimulator)
		deps_platform="ios"
		;;
	*)
		deps_platform="$platform"
		;;
esac

deps_file="${script_dir}/deps-${deps_platform}.sh"
if [[ ! -f "$deps_file" ]]; then
	echo "Dependency declaration file not found for platform '${platform}': ${deps_file}" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$deps_file"

dependencies="${SUB_DEPENDENCIES[$workflow_name]-}"
if [[ -z "$dependencies" ]]; then
	echo "No release dependencies declared for ${workflow_name} on ${platform}-${arch}"
	exit 0
fi

libraries_dir="${workspace}/prebuilt/${platform}-${arch}/libraries"
mkdir -p "$libraries_dir"

for dependency in $dependencies; do
	dep="${dependency#build_}"
	asset_name="${platform}-${arch}-${dep}.zip"
	release_tag="${platform}-${arch}-deps"
	release_name="${platform}-${arch}-dependencies"
	archive_path="${RUNNER_TEMP:-/tmp}/${asset_name}"

	echo "Fetching dependency ${dependency} from release '${release_name}' (${release_tag}) asset '${asset_name}'"

	python3 - "$repo" "$release_tag" "$release_name" "$asset_name" "$archive_path" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, tag, release_name, asset_name, archive_path = sys.argv[1:]
token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
api = "https://api.github.com"
headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}

def request_json(method, url, allow_404=False):
    req = urllib.request.Request(url, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            content = response.read()
            return response.status, json.loads(content) if content else None
    except urllib.error.HTTPError as exc:
        if allow_404 and exc.code == 404:
            return exc.code, None
        raise

status, release = request_json(
    "GET",
    f"{api}/repos/{repo}/releases/tags/{urllib.parse.quote(tag, safe='')}",
    allow_404=True,
)
if status == 404:
    raise SystemExit(
        f"Missing release for dependency artifact: tag='{tag}' name='{release_name}' asset='{asset_name}'"
    )

asset = None
page = 1
while True:
    _, assets = request_json("GET", f"{release['assets_url']}?per_page=100&page={page}")
    if not assets:
        break
    for candidate in assets:
        if candidate["name"] == asset_name:
            asset = candidate
            break
    if asset or len(assets) < 100:
        break
    page += 1

if asset is None:
    raise SystemExit(
        f"Missing dependency artifact: tag='{tag}' name='{release_name}' asset='{asset_name}'"
    )

download_headers = dict(headers)
download_headers["Accept"] = "application/octet-stream"
req = urllib.request.Request(asset["url"], headers=download_headers, method="GET")
with urllib.request.urlopen(req) as response, open(archive_path, "wb") as output:
    output.write(response.read())
PY

	unzip -oq "$archive_path" -d "$libraries_dir"
	rm -f "$archive_path"
done
