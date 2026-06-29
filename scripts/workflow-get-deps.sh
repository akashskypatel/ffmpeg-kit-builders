#!/usr/bin/env bash
set -euo pipefail

source "${SCRIPTDIR}/function.sh"

if [[ $# -lt 3 || $# -gt 4 ]]; then
	echo "Usage: $0 <platform> <arch> <workflow_name> [--self]" >&2
	exit 2
fi

platform="$1"
arch="$2"
workflow_name="$3"
mode="${4:-}"
workspace="${GITHUB_WORKSPACE:-$(pwd)}"
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
build_force="${WORKFLOW_FORCE_SELF:-false}"

echo ""
echo "==================================="
echo "workflow-get-deps:"
echo "platform: $platform"
echo "arch: $arch"
echo "workflow_name: $workflow_name"
echo "mode: $mode"
echo "workspace: $workspace"
echo "build_force: $build_force"
echo "==================================="

if [[ -z "$token" ]]; then
	echo "GH_TOKEN or GITHUB_TOKEN must be set to download dependency release assets" >&2
	exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="${GITHUB_REPOSITORY:-}"
if [[ -z "$repo" ]]; then
	repo="$(git -C "$script_dir/.." config --get remote.origin.url 2>/dev/null | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"
fi
if [[ -z "$repo" ]]; then
	echo "GITHUB_REPOSITORY must be set or remote.origin.url must point to GitHub" >&2
	exit 1
fi

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

if [[ "$mode" == "--self" ]]; then
	if truthy "$build_force"; then
		echo "Force rebuild requested; skipping self dependency release lookup for ${workflow_name} on ${platform}-${arch}"
		exit 4
	fi
	dependencies="$workflow_name"
else
	dependencies="${SUB_DEPENDENCIES[$workflow_name]-}"
fi

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

	if ! python3 - "$repo" "$release_tag" "$release_name" "$asset_name" "$archive_path" <<'PY'
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
	then
		echo "Missing dependency artifact: ${asset_name}" >&2
		exit 3
	fi

	unzip -oq "$archive_path" -d "$libraries_dir"
	rm -f "$archive_path"
done
