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

repo_name="${repo#*/}"
repo_owner="${repo%/*}"

if ! github_gh release view "$release_tag" --repo "$repo" >/dev/null 2>>"$LOG_FILE"; then
  echo "Creating release ${release_tag}..." | tee -a "$LOG_FILE"
  if ! github_gh release create "$release_tag" \
      --repo "$repo" \
      --title "$release_name" \
      --prerelease \
      --notes "" >>"$LOG_FILE" 2>&1; then
    if ! github_gh release view "$release_tag" --repo "$repo" >/dev/null 2>>"$LOG_FILE"; then
      echo "Failed to create release ${release_tag}." >&2
      exit 1
    fi
    echo "Release ${release_tag} became available after create attempt. Continuing..." | tee -a "$LOG_FILE"
  fi
fi

if ! github_gh release upload "$release_tag" \
    "${workspace}/${archive_name}" \
    --repo "$repo" \
    --clobber >>"$LOG_FILE" 2>&1; then
  echo "Failed to upload release asset: ${archive_name}" >&2
  exit 1
fi
