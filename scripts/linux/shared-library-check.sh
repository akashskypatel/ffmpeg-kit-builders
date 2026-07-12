#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207
if (( BASH_VERSINFO[0] < 4 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 4+ is required." >&2
    exit 1
fi

lib_path="$1"

if [[ ! -d $lib_path && ! -f $lib_path ]]; then
  echo "Invalid path"
  exit 1
fi

if [[ -d $lib_path && -f "$lib_path/libffmpegkit.so" ]]; then
  lib_path="$lib_path/libffmpegkit.so"
fi

echo "Symbol count:"
nm -D --defined-only "$lib_path" | grep " T " | wc -l
echo "Text relocation check (blank = success):"
readelf -d "$lib_path" | grep TEXTREL
echo "Dependency check (system deps = success):"
ldd -r "$lib_path"
