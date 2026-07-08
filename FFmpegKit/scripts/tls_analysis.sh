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

# Run from ffmpeg-kit-builders project root
TARGET_DIR="FFmpegKit/src"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: $TARGET_DIR not found"
    exit 1
fi

EXCLUDE_FILES=(
    "FFmpegKit/src/ffmpeg_tls.h"
    "FFmpegKit/src/FFmpegKitConfig.cpp"
)

mapfile -t FILE_LIST < <(grep -rl "FFMPEG_THREAD_LOCAL" "$TARGET_DIR")

for file in "${FILE_LIST[@]}"; do
  if [[ "${EXCLUDE_FILES[@]}" =~ "$file" ]]; then
    continue
  fi
    full_path="$(pwd)/$file"
    file=$(echo "$full_path" | tr -d '\r')
    
    # 2. Extract variable names from the current file
    mapfile -t VAR_LINES < <(grep "FFMPEG_THREAD_LOCAL" "$full_path")

    for var_line in "${VAR_LINES[@]}"; do
        # Parsing logic
        if [[ "$var_line" == *"(*"* ]]; then
            name=$(echo "$var_line" | gsed -E 's/.*(\(\*([a-zA-Z0-9_]+)\)).*/\2/')
        else
            name=$(echo "$var_line" | gsed -E 's/.*FFMPEG_THREAD_LOCAL//; s/[[;=].*//; s/.*[[:space:]*]([a-zA-Z0-9_]+)[[:space:]]*$/\1/' | xargs)
        fi

        # Skip if parsing failed or it's a macro definition
        [[ -z "$name" || "$var_line" == *"#define"* ]] && continue

        echo "------------------------------------------------------------"
        echo "VARIABLE: $name (Defined in: $file)"
        echo "------------------------------------------------------------"

        # 3. Find usages: 
        # -w: match whole word only
        # --exclude: don't search the file where it's defined (optional)
        # grep -v: exclude the definition line itself if searching in the same file
        grep -rnw "$TARGET_DIR" -e "$name" | grep -v "FFMPEG_THREAD_LOCAL"
        
        echo ""
    done
done
