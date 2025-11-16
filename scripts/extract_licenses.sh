#!/bin/bash

set -e

SOURCE_BASE="$1"
DEST_DIR="$2"

mkdir -p "$DEST_DIR"

if [ ! -d "$SOURCE_BASE" ]; then
    echo "Error: Source directory '$SOURCE_BASE' does not exist"
    exit 1
fi

echo "Starting license extraction from: $SOURCE_BASE"
echo "Destination: $DEST_DIR"
echo

# Directories to ignore
IGNORE_DIRS="pkgconfig ffmpeg-kit_shared ffmpeg-kit_static build cross_compilers"

license_count=0
processed_dirs=0
directories_without_licenses=()

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
    
    echo "PROCESSING: $dir_name"
    processed_dirs=$((processed_dirs + 1))
    
    # Find only LICENSE or COPYING files (exact names, case insensitive)
    found_files=0
    find "$item" -type f \( \
        -iname "COPYRIGHT" -o \
        -iname "*COPYRIGHT*" -o \
        -iname "LICENSE" -o \
        -iname "*LICENSE*" -o \
        -iname "COPYING" -o \
        -iname "*COPYING*" \
    \) > /tmp/found_licenses.$$ 2>/dev/null
    
    while IFS= read -r license_file; do
        if [ -n "$license_file" ] && [ -f "$license_file" ]; then
            license_filename=$(basename "$license_file")
            safe_filename="${dir_name}_${license_filename}"
            
            cp "$license_file" "$DEST_DIR/$safe_filename"
            echo "  COPY: $license_filename -> $safe_filename"
            
            license_count=$((license_count + 1))
            found_files=$((found_files + 1))
        fi
    done < /tmp/found_licenses.$$
    
    rm -f /tmp/found_licenses.$$
    
    if [ $found_files -eq 0 ]; then
        echo "  No LICENSE or COPYING files found in $dir_name"
        directories_without_licenses+=("$dir_name")
    else
        echo "  Found $found_files LICENSE/COPYING file(s) in $dir_name"
    fi
    echo
done

echo "=== SUMMARY ==="
echo "Processed directories: $processed_dirs"
echo "Total LICENSE/COPYING files copied: $license_count"
echo "Destination: $DEST_DIR"

if [ $license_count -gt 0 ]; then
    echo
    echo "Copied files:"
    ls -1 "$DEST_DIR"
fi

# Show directories without LICENSE/COPYING files
if [ ${#directories_without_licenses[@]} -gt 0 ]; then
    echo
    echo "=== DIRECTORIES WITHOUT LICENSE/COPYING FILES ==="
    printf '%s\n' "${directories_without_licenses[@]}"
    echo "Total: ${#directories_without_licenses[@]} directories"
fi