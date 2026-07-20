#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 <library-directory> [runpath]" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

lib_dir="$1"
runpath="${2:-\$ORIGIN:\$ORIGIN/pulseaudio}"

if [[ ! -d "$lib_dir" ]]; then
  echo "ERROR: Linux shared library directory not found: $lib_dir" >&2
  exit 1
fi

if ! command -v patchelf >/dev/null 2>&1; then
  echo "ERROR: patchelf is required to normalize Linux bundled shared libraries." >&2
  exit 1
fi

if ! command -v readelf >/dev/null 2>&1; then
  echo "ERROR: readelf is required to inspect Linux bundled shared libraries." >&2
  exit 1
fi

is_elf_shared_library() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  readelf -h "$file" >/dev/null 2>&1 || return 1
  readelf -d "$file" >/dev/null 2>&1 || return 1
}

canonical_shared_name() {
  local name="$1"

  if [[ "$name" =~ ^(libgomp)-[A-Za-z0-9_]+\.so(\..*)?$ ]]; then
    printf '%s.so\n' "${BASH_REMATCH[1]}"
    return
  fi

  if [[ "$name" =~ ^(lib.+\.so)(\..*)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi

  printf '%s\n' "$name"
}

declare -A normalized_by_name
declare -A normalized_by_soname
declare -a elf_files

while IFS= read -r -d '' file; do
  if is_elf_shared_library "$file"; then
    elf_files+=("$file")
  fi
done < <(find "$lib_dir" -maxdepth 1 -type f \( -name "*.so" -o -name "*.so.*" \) -print0)

for file in "${elf_files[@]}"; do
  name="$(basename "$file")"
  normalized_name="$(canonical_shared_name "$name")"
  normalized_path="$(dirname "$file")/$normalized_name"

  if [[ "$name" != "$normalized_name" && ! -e "$normalized_path" ]]; then
    cp -f "$file" "$normalized_path"
    chmod --reference="$file" "$normalized_path" 2>/dev/null || true
    echo "Normalized Linux shared library filename: $name -> $normalized_name"
  fi

  normalized_by_name["$name"]="$normalized_name"
  normalized_by_name["$normalized_name"]="$normalized_name"

  soname="$(patchelf --print-soname "$file" 2>/dev/null || true)"
  if [[ -n "$soname" ]]; then
    normalized_soname="$(canonical_shared_name "$soname")"
    normalized_by_soname["$soname"]="$normalized_soname"
    normalized_by_name["$soname"]="$normalized_soname"
  fi
done

while IFS= read -r -d '' file; do
  if is_elf_shared_library "$file"; then
    name="$(basename "$file")"
    elf_files+=("$file")
    normalized_by_name["$name"]="$(canonical_shared_name "$name")"
  fi
done < <(find "$lib_dir" -maxdepth 1 -type f \( -name "*.so" -o -name "*.so.*" \) -print0)

for file in "${elf_files[@]}"; do
  [[ -f "$file" ]] || continue
  is_elf_shared_library "$file" || continue

  name="$(basename "$file")"
  normalized_name="${normalized_by_name[$name]:-$(canonical_shared_name "$name")}"

  if [[ "$name" == "$normalized_name" ]]; then
    current_soname="$(patchelf --print-soname "$file" 2>/dev/null || true)"
    if [[ -n "$current_soname" && "$current_soname" != "$normalized_name" ]]; then
      patchelf --set-soname "$normalized_name" "$file"
      echo "Normalized Linux shared library SONAME: $current_soname -> $normalized_name"
    fi

    patchelf --set-rpath "$runpath" "$file"

    while IFS= read -r needed; do
      replacement="${normalized_by_name[$needed]:-${normalized_by_soname[$needed]:-}}"
      if [[ -z "$replacement" ]]; then
        canonical_needed="$(canonical_shared_name "$needed")"
        if [[ "$canonical_needed" != "$needed" && -e "$lib_dir/$canonical_needed" ]]; then
          replacement="$canonical_needed"
        fi
      fi

      if [[ -n "$replacement" && "$replacement" != "$needed" ]]; then
        patchelf --replace-needed "$needed" "$replacement" "$file"
        echo "Normalized Linux DT_NEEDED in $name: $needed -> $replacement"
      fi
    done < <(patchelf --print-needed "$file" 2>/dev/null || true)
  fi
done
