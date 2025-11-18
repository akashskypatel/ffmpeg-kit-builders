#!/bin/bash

set -e

SOURCE_BASE="$1"
DEST_DIR="$2"

if [[ -z $DEST_DIR && ! -d $DEST_DIR ]]; then
	DEST_DIR="$(pwd)"
fi

mkdir -p "$DEST_DIR"

if [ ! -d "$SOURCE_BASE" ]; then
    echo "Error: Source directory '$SOURCE_BASE' does not exist"
    exit 1
fi

echo "Starting directory relocation from: $SOURCE_BASE"
echo "Destination: $DEST_DIR"
echo

# Directories to ignore
IGNORE_DIRS="pkgconfig ffmpeg-kit_shared ffmpeg-kit_static cross_compilers src"

processed_dirs=0

DIRS=$(find "$SOURCE_BASE"/*)

# Process each item in source directory
for item in "$SOURCE_BASE"/*; do
    # Skip if not a directory
    if [ ! -d "$item" ]; then
        continue
    fi
    
    dir_name=$(basename "$item")
    
    # Check if this directory should be ignored
    skip=0
    for ignore_dir in $IGNORE_DIRS; do
        if [ "$dir_name" = "$ignore_dir" ]; then
            echo "SKIPPING: $dir_name (in ignore list)"
            skip=1
            break
        fi
    done
    [ $skip -eq 1 ] && continue
    
    echo "MOVING: $item to $DEST_DIR"
    processed_dirs=$(( processed_dirs + 1 ))
    
    mv -fv "$item" "$DEST_DIR" || continue
		echo
done

echo "=== SUMMARY ==="
echo "Processed directories: $processed_dirs"
echo "Destination: $DEST_DIR"
