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
build_force="${WORKFLOW_FORCE_SELF:-false}"
requested_step="${WORKFLOW_REQUESTED_STEP:-}"
seen_steps_file="${WORKFLOW_SEEN_STEPS_FILE:-${GITHUB_WORKSPACE:-${repo_root}}/workflow-seen-steps.log}"
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

# repo = owner/repo_name
repo_name="${repo#*/}"
repo_owner="${repo%/*}"

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

    if ! release_id="$(github_gh api "repos/${repo}/releases/tags/${release_tag}" --jq '.id' 2>>"$LOG_FILE")"; then
        echo "Missing release for dependency artifact pattern: tag='${release_tag}' name='${release_name}' pattern='${workflow_name}'" >&2
        exit 3
    fi

    if ! asset_names="$(github_gh api --paginate \
        "repos/${repo}/releases/${release_id}/assets?per_page=100" \
        --jq '.[].name' 2>>"$LOG_FILE")"; then
        echo "Failed to list dependency artifacts: tag='${release_tag}' name='${release_name}'" >&2
        exit 3
    fi

    dependencies="$(
        printf '%s\n' "$asset_names" |
        while IFS= read -r asset_name; do
            [[ "$asset_name" == "${asset_prefix}"*.zip ]] || continue
            dep="${asset_name#"$asset_prefix"}"
            dep="${dep%.zip}"
            [[ "$dep" == ffmpeg-kit-* ]] && continue
            if [[ "$dep" == $workflow_name ]]; then
                printf '%s\n' "$dep"
            fi
        done |
        sort -u |
        xargs
    )"

    if [[ -z "$dependencies" ]]; then
        echo "Missing dependency artifacts: tag='${release_tag}' name='${release_name}' pattern='${workflow_name}'" >&2
        exit 3
    fi
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

	rm -f "$archive_path"
	if ! github_gh release download "$release_tag" \
		--repo "$repo" \
		--pattern "$asset_name" \
		--output "$archive_path" \
		--clobber >>"$LOG_FILE" 2>&1; then
		echo "Missing dependency artifact: ${asset_name}" >&2
		exit 3
	fi

    if [[ "$asset_name" == "${platform}-${arch}-ffmpeg-"*.zip ]]; then
        echo "Extracting ffmpeg archive detected: ${archive_path}"
        dir_name="${asset_name#"${platform}-${arch}-"}"
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

        find "$staging_dir" -type f -exec grep -Il --null . {} + |
            xargs -0 gsed -i \
                -e "s|/__w/${repo_name}/${repo_name}|${repo_root_sed}|g" \
                -e "s|/Users/runner/work/${repo_name}/${repo_name}|${repo_root_sed}|g" \
                -e "s|/Users/runner/${repo_name}/${repo_name}|${repo_root_sed}|g"
        
        find "${workspace}/prebuilt/${platform}-${arch}" -type l -print0 | while IFS= read -r -d '' link; do
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
