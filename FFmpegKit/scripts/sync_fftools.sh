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

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")" # FFmpegKit/scripts
PROJECT_ROOT="$(realpath "$(dirname "$SCRIPT_DIR")")" # FFmpegKit
FFMPEG_KIT_ROOT="$(realpath "$(dirname "$PROJECT_ROOT")")" # ffmpeg-kit-builders
PATCH_DIR="${PROJECT_ROOT}/patches"

# Parse optional flags first
NO_PATCH=n
while [ $# -gt 0 ]; do
    case $1 in
        --no-patch)
            NO_PATCH=y
            shift
        ;;
        --ffmpeg-src-dir=*)
            FFMPEG_SRC_DIR="${1#*=}"
            shift
        ;;
        --current-source-dir=*)
            CURRENT_SOURCE_DIR="${1#*=}"
            shift
        ;;
        -*)
            echo "Unknown option: $1"
            shift
        ;;
        *)
            break
        ;;
    esac
done

# Now handle positional arguments
FFMPEG_SRC_DIR="${FFMPEG_SRC_DIR:-$FFMPEG_KIT_ROOT/prebuilt/src/ffmpeg}"
CURRENT_SOURCE_DIR="${CURRENT_SOURCE_DIR:-$PROJECT_ROOT}"

rsync -am --include='*/' \
--include='*.c' --include='*.h' --include='*.css' --include='*.html' \
--exclude='*' \
"$FFMPEG_SRC_DIR/fftools/" "$CURRENT_SOURCE_DIR/fftools.tmp"

# remove "fftools/" from includes
find "$CURRENT_SOURCE_DIR/fftools.tmp" -type f -name "*.c" -o -name "*.h" -exec gsed -i 's|#include "fftools/|#include "|g' {} +

# move from fftools to src
cp -r "$CURRENT_SOURCE_DIR/fftools.tmp/"* "$CURRENT_SOURCE_DIR/src/"

# remove fftools.tmp
rm -rf "$CURRENT_SOURCE_DIR/fftools.tmp"

if [ -d "$PATCH_DIR" ] && [ "$NO_PATCH" != "y" ]; then
    cd "$PROJECT_ROOT" || exit 1
    echo "-- Checking for patches in 'patches' directory..."
    
    # Ensure patch utility is installed
    if ! command -v patch &> /dev/null; then
        echo "patch command could not be found" >&2
        exit 1
    fi
    
    # Iterate over .patch files in the directory
    for PATCH_FILE in "$PATCH_DIR"/*.patch; do
        # Handle case where no .patch files exist
        [ -e "$PATCH_FILE" ] || continue
        
        PATCH_NAME=$(basename "$PATCH_FILE")
        echo "-- Processing patch: $PATCH_NAME"
        
        # Check if applied (Reverse dry-run)
        # -p1: strip 1 directory level
        # -R: reverse check
        # --dry-run: do not modify files
        # -s: silent/quiet mode
        patch -p1 -R --dry-run -s -i "$PATCH_FILE" -d "$CURRENT_SOURCE_DIR" &> /dev/null
        PATCH_APPLIED_EXIT_CODE=$?
        
        if [ $PATCH_APPLIED_EXIT_CODE -eq 0 ]; then
            echo "  - Already applied."
        else
            # Apply Patch
            # -N: ignore patches that seem to be already applied or reversed
            patch -p1 -N -i "$PATCH_FILE" -d "$CURRENT_SOURCE_DIR"
            PATCH_EXIT_CODE=$?
            
            if [ $PATCH_EXIT_CODE -ne 0 ]; then
                echo "FATAL: Failed to apply patch '$PATCH_NAME'. Check for conflicts." >&2
                exit 1
            else
                echo "  - Applied successfully."
            fi
        fi
    done
    cd "$CURRENT_SOURCE_DIR"
    
    # exec $CURRENT_SOURCE_DIR/scripts/audit_cmds.sh
    
    exec python3 "$SCRIPT_DIR/tls_patch.py"
    
    # exec python3 $SCRIPT_DIR/options_patch.py
fi