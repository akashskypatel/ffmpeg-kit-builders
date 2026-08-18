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

if [[ $# -lt 3 || $# -gt 4 ]]; then
	echo "Usage: $0 <platform> <arch> <workflow_name> [--self|--artifact|--artifact-pattern]" >&2
	exit 2
fi

source "${SCRIPTDIR}/function.sh"

platform="$1"
arch="$2"
workflow_name="$3"
mode="${4:-}"
workspace="${GITHUB_WORKSPACE:-$repo_root}"
token="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN_CLASSIC:-$(get_github_token_classic)}}}"
build_force="${WORKFLOW_FORCE_SELF:-false}"
requested_step="${WORKFLOW_REQUESTED_STEP:-}"
seen_steps_file="${WORKFLOW_SEEN_STEPS_FILE:-${GITHUB_WORKSPACE:-${repo_root}}/workflow-seen-steps.log}"

if [[ -z "$token" ]]; then
	echo "GH_TOKEN or GITHUB_TOKEN must be set to download dependency release assets" >&2
	exit 1
fi

repo="${GITHUB_REPOSITORY:-"$(get_github_owner)/$(get_github_repo)"}"
if [[ -z "$repo" ]]; then
	repo="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null | gsed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"
fi
if [[ -z "$repo" ]]; then
	echo "GITHUB_REPOSITORY must be set or remote.origin.url must point to GitHub" >&2
	exit 1
fi

echo ""
echo "==================================="
echo "workflow-get-deps:"
echo "platform: $platform"
echo "arch: $arch"
echo "workflow_name: $workflow_name"
echo "mode: $mode"
echo "workspace: $workspace"
echo "build_force: $build_force"
echo "requested_step: $requested_step"
echo "seen_steps_file: $seen_steps_file"
echo "repo: $repo"
echo "==================================="

get_workflow_seen_steps() {
	local seen="${WORKFLOW_SEEN_STEPS:-}"
	if [[ -f "$seen_steps_file" ]]; then
		seen="${seen} $(tr '\n' ' ' < "$seen_steps_file")"
	fi
	seen="${seen//,/ }"
	printf '%s\n' "$seen"
}

workflow_step_seen() {
	local key="$1"
	local raw="${2:-$key}"
	local seen
	seen="$(get_workflow_seen_steps)"
	[[ " $seen " == *" $key "* || " $seen " == *" $raw "* ]]
}

mark_workflow_step_seen() {
	local key="$1"
	local seen
	mkdir -p "$(dirname "$seen_steps_file")"
	if [[ ! -f "$seen_steps_file" ]] || ! grep -Fxq "$key" "$seen_steps_file"; then
		printf '%s\n' "$key" >> "$seen_steps_file"
	fi
	seen="$(get_workflow_seen_steps | xargs)"
	export WORKFLOW_SEEN_STEPS="$seen"
	if [[ -n "${GITHUB_ENV:-}" ]]; then
		printf 'WORKFLOW_SEEN_STEPS=%s\n' "$seen" >> "$GITHUB_ENV"
	fi
}

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

# repo = owner/repo_name
# authorize_github token repo_name owner
repo_name="${repo#*/}"
repo_owner="${repo%/*}"

check_github_auth

case "$platform" in
	iphonesimulator)
		deps_platform="ios"
		;;
    appletvsimulator)
        deps_platform="appletvos"
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

if [[ "$mode" == "--artifact-pattern" ]]; then
    if truthy "$build_force"; then
		echo "Force rebuild requested; skipping self dependency release lookup for ${workflow_name} on ${platform}-${arch}"
		exit 4
	fi
	release_tag="${platform}-${arch}-deps"
	release_name="${platform}-${arch}-dependencies"
	asset_prefix="${platform}-${arch}-"
	dependencies="$(python3 - "$repo" "$release_tag" "$release_name" "$asset_prefix" "$workflow_name" "$token" <<'PY'
import fnmatch
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, tag, release_name, asset_prefix, pattern, token = sys.argv[1:]
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
        f"Missing release for dependency artifact pattern: tag='{tag}' name='{release_name}' pattern='{pattern}'"
    )
if status == 401:
    raise SystemExit(
        f"Unauthorized to access release for dependency artifact pattern: tag='{tag}' name='{release_name}' pattern='{pattern}' in repo '{repo}'. Please check your GH_TOKEN/GITHUB_TOKEN."
    )
if status >= 400:
    raise SystemExit(
        f"Failed to access release for dependency artifact pattern: tag='{tag}' name='{release_name}' pattern='{pattern}' in repo '{repo}'. Status: {status}"
    )

matched = []
page = 1
while True:
    _, assets = request_json("GET", f"{release['assets_url']}?per_page=100&page={page}")
    if not assets:
        break
    for asset in assets:
        name = asset["name"]
        if not name.startswith(asset_prefix) or not name.endswith(".zip"):
            continue
        dep = name[len(asset_prefix):-4]
        if dep.startswith("ffmpeg-kit-"):
            continue
        if fnmatch.fnmatchcase(dep, pattern):
            matched.append(dep)
    if len(assets) < 100:
        break
    page += 1

if not matched:
    raise SystemExit(
        f"Missing dependency artifacts: tag='{tag}' name='{release_name}' pattern='{pattern}'"
    )

print(" ".join(sorted(set(matched))))
PY
)"
elif [[ "$mode" == "--artifact" ]]; then
	dependencies="$workflow_name"
elif [[ "$mode" == "--self" ]]; then
	if truthy "$build_force" && [[ -n "$requested_step" && "$workflow_name" == "$requested_step" ]]; then
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
	seen_key="${platform}-${arch}:${dependency}"
	asset_name="${platform}-${arch}-${dep}.zip"
	release_tag="${platform}-${arch}-deps"
	release_name="${platform}-${arch}-dependencies"
	archive_path="${RUNNER_TEMP:-/tmp}/${asset_name}"
	extract_dir="$libraries_dir"

	if workflow_step_seen "$seen_key" "$dependency"; then
		echo "Skipping dependency ${dependency} for ${platform}-${arch}; already present in WORKFLOW_SEEN_STEPS"
		continue
	fi

	if [[ "$mode" == "--artifact" || "$mode" == "--artifact-pattern" ]]; then
		extract_dir="${workspace}/prebuilt/${platform}-${arch}/${dep}"
		rm -rf "$extract_dir"
		mkdir -p "$extract_dir"
	fi

	echo "Fetching dependency ${dependency} from release '${release_name}' (${release_tag}) asset '${asset_name}'"

	if ! python3 - "$repo" "$release_tag" "$release_name" "$asset_name" "$archive_path" "$token" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, tag, release_name, asset_name, archive_path, token = sys.argv[1:]
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
if status == 401:
    raise SystemExit(
        f"Unauthorized to access release for dependency artifact: tag='{tag}' name='{release_name}' asset='{asset_name}' in repo '{repo}'. Please check your GH_TOKEN/GITHUB_TOKEN."
    )
if status >= 400:
    raise SystemExit(
        f"Failed to access release for dependency artifact: tag='{tag}' name='{release_name}' asset='{asset_name}' in repo '{repo}'. Status: {status}"
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
    if [[ "$archive_path" == "${platform}-${arch}-ffmpeg-*" ]]; then
        echo "Extracting ffmpeg archive detected: ${archive_path}"
        dir_name="${archive_path#"${platform}-${arch}-"}"
        dir_name="${dir_name%.zip}"
        extract_dir="${workspace}/prebuilt/${platform}-${arch}/${dir_name}"
        rm -rf "$extract_dir"
        mkdir -p "$extract_dir"
    fi
    staging_dir="$(mktemp -d)"

    echo "Unzipping archive: $archive_path to $staging_dir"
    unzip -oq "$archive_path" -d "$staging_dir"
    echo "Archive extracted successfully"

    rm -fv "$archive_path"

    if [[ "$repo_root" != "/__w/${repo_name}/${repo_name}" &&
        "$repo_root" != "/Users/runner/work/${repo_name}/${repo_name}" &&
        "$repo_root" != "/Users/runner/${repo_name}/${repo_name}" ]]; then

        repo_root_sed="$(
            printf '%s\n' "$repo_root" |
                gsed -e 's/[\/&|]/\\&/g'
        )"

        find "$staging_dir" -type f -exec grep -IlZ . {} + |
            xargs -0 -r gsed -i \
                -e "s|/__w/${repo_name}/${repo_name}|${repo_root_sed}|g" \
                -e "s|/Users/runner/work/${repo_name}/${repo_name}|${repo_root_sed}|g" \
                -e "s|/Users/runner/${repo_name}/${repo_name}|${repo_root_sed}|g"
        
        find "${workspace}/prebuilt/${platform}-${arch}" -xtype l -print0 | while IFS= read -r -d '' link; do
            old_target=$(readlink "$link")
            
            new_target=$(echo "$old_target" | gsed \
                -e "s|/__w/${repo_name}/${repo_name}|${repo_root_sed}|g" \
                -e "s|/Users/runner/work/${repo_name}/${repo_name}|${repo_root_sed}|g" \
                -e "s|/Users/runner/${repo_name}/${repo_name}|${repo_root_sed}|g")
            
            if [ "$old_target" != "$new_target" ]; then
                ln -sf "$new_target" "$link"
            fi
        done
    fi

    cp -a "$staging_dir"/. "$extract_dir"/
    rm -rf "$staging_dir"
    chmod -R a+rwx "$extract_dir"

    mark_workflow_step_seen "$seen_key"
done

exit 0
