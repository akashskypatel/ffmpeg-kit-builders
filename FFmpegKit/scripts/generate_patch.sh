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

##
# Generates a patch file for a given file.
# Usage: ./generate_patch.sh <INPUT_FILE> [FFMPEG_SRC_DIR] [CURRENT_SOURCE_DIR]
# Example: ./generate_patch.sh ffmpeg.c
# Output: ./patches/ffmpeg.c.patch
# FFMPEG_SRC_DIR: Path to the ffmpeg source directory (default: ~/ffmpeg-kit-builders/prebuilt/src/ffmpeg)
# CURRENT_SOURCE_DIR: Path to the current source directory (default: ~/ffmpeg-kit-builders/FFmpegKit/src)
##

set -e
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")" # FFmpegKit/scripts
PROJECT_ROOT="$(realpath "$(dirname "$SCRIPT_DIR")")" # FFmpegKit
FFMPEG_KIT_ROOT="$(realpath "$(dirname "$PROJECT_ROOT")")" # ffmpeg-kit-builders
INPUT_FILE="$1"
FILE_NAME=${INPUT_FILE%.*}
FILE_EXT=${INPUT_FILE##*.}
FFMPEG_SRC_DIR="${2:-$FFMPEG_KIT_ROOT/prebuilt/src/ffmpeg}"
CURRENT_SOURCE_DIR="${3:-$PROJECT_ROOT/src}"
PATCH_DIR="$PROJECT_ROOT/patches"

ffmpeg_src_dir="$FFMPEG_SRC_DIR/fftools"

if [ ! -d "$CURRENT_SOURCE_DIR" ]; then
    echo "Current source directory not found: $CURRENT_SOURCE_DIR"
    exit 1
fi

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <INPUT_FILE>"
    exit 1
fi

if [ ! -f "$(realpath "$ffmpeg_src_dir/$INPUT_FILE")" ]; then
    echo "File not found: $(realpath "$ffmpeg_src_dir/$INPUT_FILE")"
    exit 1
fi

if [ ! -f "$(realpath "$CURRENT_SOURCE_DIR/${FILE_NAME}_bak.$FILE_EXT")" ]; then
    echo "Patched source file not found: $(realpath "$CURRENT_SOURCE_DIR/${FILE_NAME}_bak.$FILE_EXT")"
    exit 1
fi

if [ ! -d "$ffmpeg_src_dir" ]; then
    echo "FFmpeg source directory not found: $ffmpeg_src_dir"
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "Patch directory not found: $PATCH_DIR"
    exit 1
fi

FFTOOLS_SOURCE_FILE="$ffmpeg_src_dir/$INPUT_FILE"
ORIG_SOURCE_FILE="$CURRENT_SOURCE_DIR/${FILE_NAME}_orig.$FILE_EXT"
PATCHED_SOURCE_FILE="$CURRENT_SOURCE_DIR/${FILE_NAME}_bak.$FILE_EXT"
PATCH_FILE="$PATCH_DIR/$INPUT_FILE.patch"

echo "Copying source file from ffmpeg/fftools to $ORIG_SOURCE_FILE"
cp -f "$FFTOOLS_SOURCE_FILE" "$ORIG_SOURCE_FILE"

{ git diff --no-index "$ORIG_SOURCE_FILE" "$PATCHED_SOURCE_FILE" > "$PATCH_FILE" ; } || true

echo "Patch file created: $PATCH_FILE"

SRC_DIR=$(basename "$CURRENT_SOURCE_DIR")

gsed -i "s|a/.*/${FILE_NAME}_orig.$FILE_EXT|a/$SRC_DIR/$FILE_NAME.$FILE_EXT|g" "$PATCH_FILE"
gsed -i "s|b/.*/${FILE_NAME}_bak.$FILE_EXT|b/$SRC_DIR/$FILE_NAME.$FILE_EXT|g" "$PATCH_FILE"

rm -f "$PATCH_FILE.patchbak"

echo "Patch file updated: $PATCH_FILE"