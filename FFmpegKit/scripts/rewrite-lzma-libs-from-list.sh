#!/usr/bin/env bash

if (( BASH_VERSINFO[0] < 5 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 5+ is required." >&2
    exit 1
fi

set -euo pipefail

INPUT_LIST="${1:?input libs list required}"
STAGE_DIR="${2:?stage dir required}"
MAP_FILE="${3:?map file required}"
LLVM_OBJCOPY="${4:?llvm-objcopy path required}"
RANLIB="${5:?ranlib path required}"
OUTPUT_LIST="${6:?output libs list required}"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
: > "$OUTPUT_LIST"

i=0

while IFS= read -r item || [ -n "$item" ]; do
  [ -n "$item" ] || continue

  if [[ "$item" == *.a && -f "$item" ]]; then
    name="$(basename "$item")"
    out="$STAGE_DIR/${i}_${name}"
    i=$((i + 1))

    cp "$item" "$out"

    echo "Rewriting LZMA symbol map in $item -> $out"
    "$LLVM_OBJCOPY" --redefine-syms "$MAP_FILE" "$out"
    "$RANLIB" "$out" || true

    echo "$out" >> "$OUTPUT_LIST"
  else
    # Preserve SDK .tbd files, frameworks, linker flags, and other non-archive
    # entries exactly so the final CMake link list remains 1:1.
    echo "$item" >> "$OUTPUT_LIST"
  fi
done < "$INPUT_LIST"