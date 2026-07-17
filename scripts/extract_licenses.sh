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

# Refined License Extraction Script
# 
# Features:
# 1. Content-based deduplication (MD5) across the component.
# 2. Merges all unique licenses into a single output file per repository.
# 3. Enhanced discovery (Standard files, SPDX headers, README fallback).
# 4. Clean formatting with source path headers.

set -e

SOURCE_BASE="$1"
OUTPUT_TARGET="$2"

if [ -z "$SOURCE_BASE" ] || [ -z "$OUTPUT_TARGET" ]; then
    echo "Usage: $0 <source_dir> <output_dir_or_file>"
    exit 1
fi

# Determine if output is a directory or a file
# If it doesn't exist, we assume it's a directory for backward compatibility with function.sh
if [ -d "$OUTPUT_TARGET" ] || [[ ! -e "$OUTPUT_TARGET" && "$OUTPUT_TARGET" != *.txt ]]; then
    mkdir -p "$OUTPUT_TARGET"
    COMPONENT_NAME=$(basename "$SOURCE_BASE")
    MERGED_FILE="$OUTPUT_TARGET/${COMPONENT_NAME}_LICENSE.txt"
else
    mkdir -p "$(dirname "$OUTPUT_TARGET")"
    MERGED_FILE="$OUTPUT_TARGET"
fi

if [ ! -d "$SOURCE_BASE" ]; then
    echo "Error: Source directory '$SOURCE_BASE' does not exist"
    exit 1
fi

echo "--- License Extraction & Merging ---"
echo "Source: $SOURCE_BASE"
echo "Output: $MERGED_FILE"

# Prepare/Clear output file
: > "$MERGED_FILE"

# Configurable options
IGNORE_DIRS=("pkgconfig" "ffmpeg-kit_shared" "ffmpeg-kit_static" "build" "cross_compilers" "meson" "build-aux" "m4")
LICENSE_PATTERNS=(
    "*LICENSE*" "*COPYING*" "*COPYRIGHT*" "*NOTICE*" "*LEGAL*"
    "*PATENTS*" "*AUTHORS*" "UNLICENSE"
)

# State
declare -A seen_hashes
license_count=0

# Helper to append unique license text
append_license() {
    local src="$1"
    local rel_path="$2"
    
    [ -f "$src" ] || return 0
    
    # Calculate hash for deduplication
    local hash
    hash=$(md5sum "$src" | awk '{print $1}')
    
    if [[ -n "${seen_hashes[$hash]}" ]]; then
        # Already included this exact license text
        return 0
    fi
    
    {
        echo "================================================================================"
        echo "COMPONENT: $(basename "$SOURCE_BASE")"
        echo "FILE:      $rel_path"
        echo "================================================================================"
        cat "$src"
        echo -e "\n\n"
    } >> "$MERGED_FILE"
    
    seen_hashes[$hash]=1
    license_count=$((license_count + 1))
    
    echo "  [MERGED] $rel_path"
}

# 1. Primary Search - Standard License Files (Depth 0-2)
echo "Scanning for standard license files..."
FIND_ARGS=()
for p in "${LICENSE_PATTERNS[@]}"; do
    FIND_ARGS+=( -iname "$p" -o )
done
unset 'FIND_ARGS[${#FIND_ARGS[@]}-1]'

while read -r file; do
    skip=0
    for d in "${IGNORE_DIRS[@]}"; do
        if [[ "$file" == */$d/* ]]; then
            skip=1
            break
        fi
    done
    [ $skip -eq 1 ] && continue
    
    rel_path="${file#"$SOURCE_BASE"/}"
    append_license "$file" "$rel_path"
done < <(find "$SOURCE_BASE" -maxdepth 2 -type f \( "${FIND_ARGS[@]}" \) 2>/dev/null)

# 2. Advanced Search - SPDX Identifiers (Fallback)
if [ "$license_count" -lt 1 ]; then
    echo "No standard licenses found. Searching for SPDX identifiers..."
    while read -r file; do
        if grep -q "SPDX-License-Identifier" "$file"; then
            rel_path="${file#"$SOURCE_BASE"/}"
            append_license "$file" "spdx_header_from_${rel_path}"
        fi
    done < <(find "$SOURCE_BASE" -maxdepth 1 -type f \( -name "*.c" -o -name "*.h" -o -name "*.md" -o -name "*.S" -o -name "*.sh" -o -name "*.py" \) 2>/dev/null)
fi

# 3. Fallback - Copyright mentions in README
if [ "$license_count" -lt 1 ]; then
    echo "Checking README for copyright/license info..."
    while read -r readme; do
        if grep -qiE "copyright|license" "$readme"; then
            rel_path="${readme#"$SOURCE_BASE"/}"
            append_license "$readme" "$rel_path"
        fi
    done < <(find "$SOURCE_BASE" -maxdepth 1 -iname "README*" 2>/dev/null)
fi

# Final check
if [ "$license_count" -eq 0 ]; then
    rm -f "$MERGED_FILE"
    echo "--- Summary ---"
    echo "WARNING: No licenses found for $(basename "$SOURCE_BASE"). Output file removed."
else
    echo "--- Summary ---"
    echo "Total unique licenses merged: $license_count"
    echo "License file created at: $MERGED_FILE"
fi
echo