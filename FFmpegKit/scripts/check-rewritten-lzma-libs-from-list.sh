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

OUTPUT_LIST="${1:?output libs list required}"

failed=0

while IFS= read -r lib || [ -n "$lib" ]; do
  [[ "$lib" == *.a && -f "$lib" ]] || continue

  bad="$(
    {
      nm -u "$lib" 2>/dev/null || true
      nm -m "$lib" 2>/dev/null || true
      nm "$lib" 2>/dev/null || true
    } | awk '
      {
        sym = $NF

        # Must catch dotted local symbols too.
        # Must NOT match _ffmpegkit_lzma_*.
        if (sym ~ /^_lzma_[A-Za-z0-9_.]+$/) {
          print sym
        }
      }
    ' | sort -u
  )"

  if [ -n "$bad" ]; then
    echo "ERROR: unprefixed LZMA symbols remain in $lib"
    echo "$bad"
    failed=1
  fi
done < "$OUTPUT_LIST"

exit "$failed"