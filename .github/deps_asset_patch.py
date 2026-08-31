from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# Add stdout-isolated gh helpers. Each credential attempt writes to its own
# temporary file so an expired token cannot contaminate output produced by a
# later fallback token (especially important for binary release assets).
p = Path("scripts/function.sh")
text = p.read_text()
if "github_gh_to_file() {" not in text:
    marker = "\ncreate_github_release() {"
    helpers = r'''

# Run a gh command with the same credential fallback as github_gh(), but isolate
# stdout for each attempt and atomically publish only the successful result.
github_gh_to_file() {
  local output_path="$1"
  shift
  local -a credential_names=("GITHUB_TOKEN" "GH_TOKEN" "GH_TOKEN_CLASSIC")
  local -a credential_values=("${GITHUB_TOKEN:-}" "${GH_TOKEN:-}" "${GH_TOKEN_CLASSIC:-}")
  local i credential tmp_path keystore stored_token stored_classic

  tmp_path="${output_path}.tmp.$$"
  rm -f "$tmp_path" "$output_path"

  for i in "${!credential_values[@]}"; do
    credential="${credential_values[$i]}"
    [[ -n "$credential" ]] || continue
    rm -f "$tmp_path"

    if GH_TOKEN="$credential" gh "$@" >"$tmp_path" 2>>"$LOG_FILE"; then
      mv -f "$tmp_path" "$output_path"
      if (( i > 0 )); then
        echo "INFO: GitHub operation succeeded with fallback credential ${credential_names[$i]}." >>"$LOG_FILE"
      fi
      return 0
    fi

    rm -f "$tmp_path"
    echo "WARNING: GitHub operation failed while using ${credential_names[$i]}; trying the next credential." >>"$LOG_FILE"
  done

  keystore="$(get_keystore_file 2>/dev/null)" || keystore=""
  if [[ -n "$keystore" && -f "$keystore" ]]; then
    stored_token="$(grep '^GH_TOKEN=' "$keystore" | cut -d '=' -f2- | tr -d '\r')"
    stored_classic="$(grep '^GH_TOKEN_CLASSIC=' "$keystore" | cut -d '=' -f2- | tr -d '\r')"

    for credential in "$stored_token" "$stored_classic"; do
      [[ -n "$credential" ]] || continue
      rm -f "$tmp_path"
      if GH_TOKEN="$credential" gh "$@" >"$tmp_path" 2>>"$LOG_FILE"; then
        mv -f "$tmp_path" "$output_path"
        echo "INFO: GitHub operation succeeded with a local keystore fallback credential." >>"$LOG_FILE"
        return 0
      fi
      rm -f "$tmp_path"
    done
  fi

  rm -f "$tmp_path" "$output_path"
  return 1
}

# Capture stdout from github_gh_to_file() without allowing failed credential
# attempts to leak partial/error response bodies into the captured value.
github_gh_capture() {
  local capture_file
  capture_file="$(mktemp)"

  if github_gh_to_file "$capture_file" "$@"; then
    cat "$capture_file"
    rm -f "$capture_file"
    return 0
  fi

  rm -f "$capture_file"
  return 1
}
'''
    text = replace_once(text, marker, helpers + marker, "function helper insertion")
p.write_text(text)


p = Path("scripts/workflow-get-deps.sh")
text = p.read_text()

# Use isolated capture for existing paginated release discovery too.
text = text.replace('release_id="$(github_gh api ', 'release_id="$(github_gh_capture api ')
text = text.replace('asset_names="$(github_gh api --paginate ', 'asset_names="$(github_gh_capture api --paginate ')

if "resolve_release_asset_id() {" not in text:
    marker = 'repo_owner="${repo%/*}"\n\n'
    resolver = r'''repo_owner="${repo%/*}"

declare -A release_assets_loaded=()
declare -A release_asset_ids=()
resolved_asset_id=""

# Resolve an exact asset name from all release-asset pages. Releases in this
# repository can exceed GitHub's 100-item page size, so gh release download's
# pattern lookup is not sufficient for assets on later pages.
resolve_release_asset_id() {
    local tag="$1"
    local wanted_asset="$2"
    local release_id asset_rows candidate_name candidate_id cache_key

    if [[ -z "${release_assets_loaded[$tag]:-}" ]]; then
        if ! release_id="$(github_gh_capture api \
            "repos/${repo}/releases/tags/${tag}" \
            --jq '.id' 2>>"$LOG_FILE")"; then
            echo "Failed to resolve dependency release: ${tag}" >&2
            return 1
        fi

        if ! asset_rows="$(github_gh_capture api --paginate \
            "repos/${repo}/releases/${release_id}/assets?per_page=100" \
            --jq '.[] | [.name, (.id | tostring)] | @tsv' 2>>"$LOG_FILE")"; then
            echo "Failed to enumerate dependency release assets: ${tag}" >&2
            return 1
        fi

        while IFS=$'\t' read -r candidate_name candidate_id; do
            [[ -n "$candidate_name" && -n "$candidate_id" ]] || continue
            release_asset_ids["${tag}|${candidate_name}"]="$candidate_id"
        done <<< "$asset_rows"
        release_assets_loaded["$tag"]=1
    fi

    cache_key="${tag}|${wanted_asset}"
    resolved_asset_id="${release_asset_ids[$cache_key]:-}"
    [[ -n "$resolved_asset_id" ]] || return 2
}

'''
    text = replace_once(text, marker, resolver, "asset resolver insertion")

old_download = r'''	rm -f "$archive_path"
	if ! github_gh release download "$release_tag" \
		--repo "$repo" \
		--pattern "$asset_name" \
		--output "$archive_path" \
		--clobber >>"$LOG_FILE" 2>&1; then
		echo "Missing dependency artifact: ${asset_name}" >&2
		exit 3
	fi
'''
new_download = r'''	rm -f "$archive_path"
    if resolve_release_asset_id "$release_tag" "$asset_name"; then
        if ! github_gh_to_file "$archive_path" api \
            -H "Accept: application/octet-stream" \
            "repos/${repo}/releases/assets/${resolved_asset_id}"; then
            echo "Failed to download dependency artifact: ${asset_name} (asset id ${resolved_asset_id})" >&2
            exit 3
        fi
        if [[ ! -s "$archive_path" ]]; then
            echo "Downloaded dependency artifact is empty: ${asset_name}" >&2
            rm -f "$archive_path"
            exit 3
        fi
    else
        resolve_status=$?
        if [[ "$resolve_status" -eq 2 ]]; then
            echo "Missing dependency artifact: ${asset_name}" >&2
        else
            echo "Failed to resolve dependency artifact: ${asset_name}" >&2
        fi
        exit 3
    fi
'''
text = replace_once(text, old_download, new_download, "dependency download replacement")
p.write_text(text)
