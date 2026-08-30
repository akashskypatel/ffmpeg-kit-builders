from pathlib import Path


def replace_between(text: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[:start] + replacement + text[end:]


# -----------------------------------------------------------------------------
# scripts/function.sh
# -----------------------------------------------------------------------------
p = Path("scripts/function.sh")
text = p.read_text()

text = replace_between(
    text,
    "authorize_github() {",
    "create_github_release() {",
    r'''authorize_github() {
  local github_token="${1:-}"
  local github_repo="${2:-${GITHUB_REPO:-}}"
  local github_owner="${3:-${GITHUB_USERNAME:-}}"

  [[ -n "$github_token" ]] || return 1
  [[ -n "$github_repo" ]] || return 1
  [[ -n "$github_owner" ]] || return 1

  GH_TOKEN="$github_token" gh api "repos/${github_owner}/${github_repo}" --silent >/dev/null 2>&1
}

# Run a gh command with credentials in priority order:
#   1. Actions-generated GITHUB_TOKEN
#   2. long-lived fine-grained PAT in GH_TOKEN
#   3. long-lived classic PAT in GH_TOKEN_CLASSIC
# Local keystore credentials are appended only when all environment credentials fail.
github_gh() {
  local -a credential_names=("GITHUB_TOKEN" "GH_TOKEN" "GH_TOKEN_CLASSIC")
  local -a credential_values=("${GITHUB_TOKEN:-}" "${GH_TOKEN:-}" "${GH_TOKEN_CLASSIC:-}")
  local i credential keystore stored_token stored_classic

  for i in "${!credential_values[@]}"; do
    credential="${credential_values[$i]}"
    [[ -n "$credential" ]] || continue

    if GH_TOKEN="$credential" gh "$@"; then
      if (( i > 0 )); then
        echo "INFO: GitHub operation succeeded with fallback credential ${credential_names[$i]}." >>"$LOG_FILE"
      fi
      return 0
    fi

    echo "WARNING: GitHub operation failed while using ${credential_names[$i]}; trying the next credential." >>"$LOG_FILE"
  done

  # Preserve local/non-CI keystore behavior. get_keystore_file executes in a
  # command substitution so its historical exit_message behavior cannot exit
  # this shell when no local keystore exists.
  keystore="$(get_keystore_file 2>/dev/null)" || keystore=""
  if [[ -n "$keystore" && -f "$keystore" ]]; then
    stored_token="$(grep '^GH_TOKEN=' "$keystore" | cut -d '=' -f2- | tr -d '\r')"
    stored_classic="$(grep '^GH_TOKEN_CLASSIC=' "$keystore" | cut -d '=' -f2- | tr -d '\r')"

    for credential in "$stored_token" "$stored_classic"; do
      [[ -n "$credential" ]] || continue
      if GH_TOKEN="$credential" gh "$@"; then
        echo "INFO: GitHub operation succeeded with a local keystore fallback credential." >>"$LOG_FILE"
        return 0
      fi
    done
  fi

  return 1
}

''',
)

text = replace_between(
    text,
    "create_github_release() {",
    "upload_release_asset() {",
    r'''create_github_release() {
  local attachment="$1"
  local version tag target_commit
  local repo="${GITHUB_REPO:-}"
  local owner="${GITHUB_USERNAME:-}"

  version="$(get_version)"
  tag="v$version-$host_platform"

  if [[ -z "$attachment" || ! -f "$attachment" ]]; then
    echo "Invalid attachment. File doesn't exist or attachment is blank: $attachment" | tee -a "$LOG_FILE"
    return 1
  fi

  if [[ -z "$repo" ]]; then
    repo="$(get_github_repo)" || return 1
  fi
  if [[ -z "$owner" ]]; then
    owner="$(get_github_owner)" || return 1
  fi

  if github_gh release view "$tag" --repo "$owner/$repo" >/dev/null 2>>"$LOG_FILE"; then
    echo "Release $tag already exists." | tee -a "$LOG_FILE"
    upload_release_asset "$attachment"
    return $?
  fi

  echo "Creating release $tag..." | tee -a "$LOG_FILE"
  local release_notes
  release_notes="$(get_changes_from_changelog)"
  target_commit="$(git rev-parse HEAD)"

  # Let GitHub create the tag at the current commit. This avoids relying on the
  # checkout action's persisted Git credential after a long-running build.
  if github_gh release create "$tag" \
      --repo "$owner/$repo" \
      --target "$target_commit" \
      --title "$tag" \
      --notes "$release_notes" \
      --prerelease \
      --discussion-category "Releases" \
      --generate-notes \
      --latest >>"$LOG_FILE" 2>&1; then
    echo "Release $tag created successfully." | tee -a "$LOG_FILE"
    upload_release_asset "$attachment"
  else
    # A concurrent run may have created the release after the initial lookup.
    if github_gh release view "$tag" --repo "$owner/$repo" >/dev/null 2>>"$LOG_FILE"; then
      echo "Release $tag became available after create attempt. Continuing..." | tee -a "$LOG_FILE"
      upload_release_asset "$attachment"
    else
      echo "Failed to create release $tag." | tee -a "$LOG_FILE"
      return 1
    fi
  fi
}

''',
)

text = replace_between(
    text,
    "upload_release_asset() {",
    "check_existing_package() {",
    r'''upload_release_asset() {
  local attachment="$1"
  local version tag
  local repo="${GITHUB_REPO:-}"
  local owner="${GITHUB_USERNAME:-}"

  version="$(get_version)"
  tag="v$version-$host_platform"

  if [[ -z "$repo" ]]; then
    repo="$(get_github_repo)" || return 1
  fi
  if [[ -z "$owner" ]]; then
    owner="$(get_github_owner)" || return 1
  fi

  if ! github_gh release view "$tag" --repo "$owner/$repo" >/dev/null 2>>"$LOG_FILE"; then
    echo "Error: Could not find release for tag $tag" | tee -a "$LOG_FILE"
    return 1
  fi

  echo "Uploading $attachment as release asset for $tag..." | tee -a "$LOG_FILE"
  if github_gh release upload "$tag" "$attachment" \
      --repo "$owner/$repo" \
      --clobber >>"$LOG_FILE" 2>&1; then
    echo "Uploaded $attachment successfully." | tee -a "$LOG_FILE"
  else
    exit_message 1 "Failed to upload $attachment. Please check the logs."
  fi
}

''',
)

text = replace_between(
    text,
    "check_existing_package() {",
    "delete_existing_package() {",
    r'''check_existing_package() {
  local package_name="$1"
  local package_version="$2"
  local package_type="maven"
  local owner="${GITHUB_USERNAME:-}"
  local versions_json version_id

  if [[ -z "$owner" ]]; then
    owner="$(get_github_owner)" || return 1
  fi

  echo "Checking for existing package $package_name version $package_version..." >>"${LOG_FILE}"

  if ! versions_json="$(github_gh api --paginate --slurp \
      "users/$owner/packages/$package_type/$package_name/versions?per_page=100" 2>>"$LOG_FILE")"; then
    echo "Error: package $package_name could not be queried" >>"${LOG_FILE}"
    return 1
  fi
  versions_json="$(printf '%s' "$versions_json" | jq -c '[.[][]]')"

  version_id="$(printf '%s' "$versions_json" | jq -r --arg version "$package_version" '.[]? | select(.name == $version) | .id')"
  if [[ -n "$version_id" && "$version_id" != "null" ]]; then
    echo "Found existing package version: $version_id" >>"${LOG_FILE}"
    echo "$version_id"
    return 0
  fi

  return 1
}

''',
)

text = replace_between(
    text,
    "delete_existing_package() {",
    "check_maven_package_status() {",
    r'''delete_existing_package() {
  local package_name="$1"
  local package_version="$2"
  local package_type="maven"
  local owner="${GITHUB_USERNAME:-}"
  local versions_json version_count version_id delete_endpoint

  if [[ -z "$owner" ]]; then
    owner="$(get_github_owner)" || return 1
  fi

  if ! versions_json="$(github_gh api --paginate --slurp \
      "users/$owner/packages/$package_type/$package_name/versions?per_page=100" 2>>"$LOG_FILE")"; then
    echo "Package $package_name does not exist in registry yet. Proceeding..." | tee -a "$LOG_FILE"
    return 0
  fi
  versions_json="$(printf '%s' "$versions_json" | jq -c '[.[][]]')"

  version_count="$(printf '%s' "$versions_json" | jq 'length')"
  version_id="$(printf '%s' "$versions_json" | jq -r --arg version "$package_version" '.[]? | select(.name == $version) | .id')"

  if [[ -z "$version_id" || "$version_id" == "null" ]]; then
    echo "Version $package_version not found. Proceeding..." | tee -a "$LOG_FILE"
    return 0
  fi

  if [[ "$version_count" -eq 1 ]]; then
    echo "Last version detected. Deleting entire package: $package_name..." | tee -a "$LOG_FILE"
    delete_endpoint="users/$owner/packages/$package_type/$package_name"
  else
    echo "Multiple versions exist. Deleting specific version ID: $version_id..." | tee -a "$LOG_FILE"
    delete_endpoint="users/$owner/packages/$package_type/$package_name/versions/$version_id"
  fi

  if github_gh api --method DELETE "$delete_endpoint" --silent >>"$LOG_FILE" 2>&1; then
    echo "Successfully deleted." | tee -a "$LOG_FILE"
  else
    echo "Warning: Delete failed. Conflict may occur." | tee -a "$LOG_FILE"
  fi
}

''',
)

text = replace_between(
    text,
    "check_maven_package_status() {",
    "disable_git_lfs_and_checkout() {",
    r'''check_maven_package_status() {
  local package_name="$1"
  local package_version="$2"
  local username="${OSSRH_USERNAME:-$(get_maven_username)}"
  local password="${OSSRH_PASSWORD:-$(get_maven_password)}"
  local endpoint="https://central.sonatype.com/api/v1/publisher/published"
  local owner="${GITHUB_USERNAME:-}"
  local namespace auth_token status_json error_msg status

  if [[ -z "$owner" ]]; then
    owner="$(get_github_owner)" || return 1
  fi
  namespace="io.github.$owner.ffmpegkit"

  echo "Checking for existing package $package_name version $package_version on Maven Central..." >>"${LOG_FILE}"
  auth_token="$(echo -n "$username:$password" | base64)"
  status_json="$(curl -fsS -X GET \
    "$endpoint?namespace=$namespace&name=$package_name&version=$package_version" \
    -H 'accept: application/json' \
    -H "Authorization: Basic $auth_token")" || return 1

  error_msg="$(echo "$status_json" | jq -r 'if type == "object" then .message else empty end')"
  if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
    echo "Error checking package status: $error_msg body: $status_json" >>"${LOG_FILE}"
    return 1
  fi

  status="$(echo "$status_json" | jq -r '.published')"
  if [[ -n "$status" && "$status" != "null" ]]; then
    echo "Package status: $status" >>"${LOG_FILE}"
    [[ "$status" == "true" ]]
    return $?
  fi

  return 1
}

''',
)

p.write_text(text)


# -----------------------------------------------------------------------------
# scripts/workflow-get-deps.sh
# -----------------------------------------------------------------------------
p = Path("scripts/workflow-get-deps.sh")
text = p.read_text()
start = text.index('token="${GH_TOKEN:')
end = text.index('repo="${GITHUB_REPOSITORY:', start)
text = text[:start] + text[end:]

text = replace_between(
    text,
    "check_github_auth() {",
    'case "$platform" in',
    '''# repo = owner/repo_name\nrepo_name="${repo#*/}"\nrepo_owner="${repo%/*}"\n\ncase "$platform" in''',
)

text = replace_between(
    text,
    'if [[ "$mode" == "--artifact-pattern" ]]; then',
    'elif [[ "$mode" == "--artifact" ]]; then',
    r'''if [[ "$mode" == "--artifact-pattern" ]]; then
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
''',
)

start = text.index('\trm -f "$archive_path"')
end = text.index('    staging_dir="$(mktemp -d)"', start)
text = text[:start] + r'''	rm -f "$archive_path"
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
''' + text[end:]
p.write_text(text)


# -----------------------------------------------------------------------------
# scripts/upload-deps-release.sh
# -----------------------------------------------------------------------------
p = Path("scripts/upload-deps-release.sh")
text = p.read_text()
start = text.index('token="${GH_TOKEN:')
end = text.index('repo="${GITHUB_REPOSITORY:', start)
text = text[:start] + text[end:]
start = text.index("check_github_auth() {")
text = text[:start] + r'''repo_name="${repo#*/}"
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
'''
p.write_text(text)


# -----------------------------------------------------------------------------
# Reusable workflow environment: expose all three credentials distinctly.
# -----------------------------------------------------------------------------
for path in (".github/workflows/build_on_linux.yaml", ".github/workflows/build_on_macos.yaml"):
    p = Path(path)
    text = p.read_text()
    old = "env:\n  GH_TOKEN: ${{ secrets.GH_TOKEN }}\n"
    new = (
        "env:\n"
        "  GITHUB_TOKEN: ${{ github.token }}\n"
        "  GH_TOKEN: ${{ secrets.GH_TOKEN }}\n"
        "  GH_TOKEN_CLASSIC: ${{ secrets.GH_TOKEN_CLASSIC }}\n"
    )
    if old not in text:
        raise RuntimeError(f"{path}: expected env block not found")
    p.write_text(text.replace(old, new, 1))
