#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292

if (( BASH_VERSINFO[0] < 4 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 4+ is required." >&2
    exit 1
fi

: "${LOG_FILE:=/dev/null}"

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
SCRIPTDIR="${SCRIPTDIR:-$script_dir}"

source "${SCRIPTDIR}/function.sh"
platform="${1:?platform is required}"
arch="${2:?arch is required}"
shift 2
if [[ $# -gt 0 && "$1" != --* ]]; then
  dep="$1"
  shift
else
  dep="${GITHUB_WORKFLOW:-artifact}"
  dep="${dep#build_}"
fi
workspace="${GITHUB_WORKSPACE:-$repo_root}"
artifact_dir=""
archive_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*)
      workspace="${1#*=}"
      shift
      ;;
    --workspace)
      workspace="${2:?--workspace requires a value}"
      shift 2
      ;;
    --artifact-dir=*)
      artifact_dir="${1#*=}"
      shift
      ;;
    --artifact-dir)
      artifact_dir="${2:?--artifact-dir requires a value}"
      shift 2
      ;;
    --archive-name=*)
      archive_name="${1#*=}"
      shift
      ;;
    --archive-name)
      archive_name="${2:?--archive-name requires a value}"
      shift 2
      ;;
    *)
      if [[ -z "${workspace_arg_seen:-}" ]]; then
        workspace="$1"
        workspace_arg_seen=1
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

archive_name="${archive_name:-${platform}-${arch}-${dep}.zip}"
release_tag="${platform}-${arch}-deps"
release_name="${platform}-${arch}-dependencies"
libraries_dir="${workspace}/prebuilt/${platform}-${arch}/libraries"
artifact_dir="${artifact_dir:-$libraries_dir}"
token="${GH_TOKEN:-${GITHUB_TOKEN:-$(get_github_token)}}"
repo="${GITHUB_REPOSITORY:-"$(get_github_owner)/$(get_github_repo)"}"

if [[ -z "$token" ]]; then
  echo "GH_TOKEN or GITHUB_TOKEN must be set for release upload" >&2
  exit 1
fi

if [[ -z "$repo" ]]; then
  repo="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null | gsed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"
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
echo "artifact_dir: $artifact_dir"
echo "repo: $repo"
echo "==================================="

if [[ ! -d "$artifact_dir" ]]; then
  echo "Missing artifact directory: $artifact_dir" >&2
  exit 1
fi

rm -f "${workspace}/${archive_name}"
(cd "$artifact_dir" && zip -qry "${workspace}/${archive_name}" .)

check_github_auth() {
	if [[ -z "$token" ]]; then
		echo "GH_TOKEN or GITHUB_TOKEN must be set to download dependency release assets" >&2
		exit 1
	fi
    if ! authorize_github "$token" "${repo_name}" "${repo_owner}"; then
        token="${GITHUB_TOKEN:-${GH_TOKEN_CLASSIC:-$(get_github_token_classic)}}"
        if ! authorize_github "$token" "${repo_name}" "${repo_owner}"; then
            token="${GH_TOKEN_CLASSIC:-$(get_github_token_classic)}"
            if ! authorize_github "$token" "${repo_name}" "${repo_owner}"; then
                token="$(get_github_token_classic)"
                if ! authorize_github "$token" "${repo_name}" "${repo_owner}"; then
                    echo "Failed to authorize GitHub" >&2
                    exit 1
                fi
            fi
        fi
    fi
}

check_github_auth

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
        "prerelease": True,
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
