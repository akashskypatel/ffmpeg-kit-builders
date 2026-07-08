#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292

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

BIN="${1:?binary path required}"

failed=0

echo "Checking final iOS dylib for unprefixed/exported LZMA symbols"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$BIN"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$BIN"
fi

echo "=== linked dylibs ==="
otool -L "$BIN"

echo "=== exported ffmpeg kit symbols ==="
nm -gU "$BIN" 2>/dev/null | awk '
  $NF ~ /^_ffmpeg_kit_/ ||
  $NF ~ /^_ffprobe_kit_/ ||
  $NF ~ /^_ffplay_kit_/ {
    print
  }
' | head -n 80 || true

echo "=== counts ==="

unprefixed_lzma_any_count="$(
  {
    nm -u "$BIN" 2>/dev/null || true
    nm -gU "$BIN" 2>/dev/null || true
    nm -m "$BIN" 2>/dev/null || true
  } | awk '
    $NF ~ /^_lzma_[A-Za-z0-9_.]+$/ {
      print $NF
    }
  ' | sort -u | wc -l | tr -d ' '
)"

prefixed_lzma_exported_count="$(
  nm -gU "$BIN" 2>/dev/null | awk '
    $NF ~ /^_ffmpegkit_lzma_[A-Za-z0-9_.]+$/ {
      print $NF
    }
  ' | sort -u | wc -l | tr -d ' '
)"

prefixed_lzma_internal_count="$(
  nm -m "$BIN" 2>/dev/null | awk '
    $NF ~ /^_ffmpegkit_lzma_[A-Za-z0-9_.]+$/ {
      print $NF
    }
  ' | sort -u | wc -l | tr -d ' '
)"

liblzma_load_count="$(
  otool -L "$BIN" | awk '
    /liblzma\./ {
      count++
    }
    END {
      print count + 0
    }
  '
)"

forbidden_system_third_party_load_count="$(
  otool -L "$BIN" | awk '
    /\/usr\/lib\/lib(lzma|archive|xml2|bz2|expat|iconv)\./ {
      count++
    }
    END {
      print count + 0
    }
  '
)"

ffmpeg_kit_count="$(
  nm -gU "$BIN" 2>/dev/null | awk '
    $NF ~ /^_ffmpeg_kit_/ {
      count++
    }
    END {
      print count + 0
    }
  '
)"

ffprobe_kit_count="$(
  nm -gU "$BIN" 2>/dev/null | awk '
    $NF ~ /^_ffprobe_kit_/ {
      count++
    }
    END {
      print count + 0
    }
  '
)"

ffplay_kit_count="$(
  nm -gU "$BIN" 2>/dev/null | awk '
    $NF ~ /^_ffplay_kit_/ {
      count++
    }
    END {
      print count + 0
    }
  '
)"

echo "unprefixed_lzma_any_count=$unprefixed_lzma_any_count"
echo "prefixed_lzma_exported_count=$prefixed_lzma_exported_count"
echo "prefixed_lzma_internal_count=$prefixed_lzma_internal_count"
echo "liblzma_load_count=$liblzma_load_count"
echo "forbidden_system_third_party_load_count=$forbidden_system_third_party_load_count"
echo "ffmpeg_kit_count=$ffmpeg_kit_count"
echo "ffprobe_kit_count=$ffprobe_kit_count"
echo "ffplay_kit_count=$ffplay_kit_count"

if [[ "$unprefixed_lzma_any_count" != "0" ]]; then
  echo "ERROR: unprefixed _lzma_* symbols remain"
  failed=1
fi

if [[ "$prefixed_lzma_exported_count" != "0" ]]; then
  echo "ERROR: private-prefixed _ffmpegkit_lzma_* symbols are exported"
  failed=1
fi

if [[ "$liblzma_load_count" != "0" ]]; then
  echo "ERROR: binary links liblzma dynamically"
  failed=1
fi

if [[ "$forbidden_system_third_party_load_count" != "0" ]]; then
  echo "ERROR: binary links forbidden/private-looking system third-party dylibs"
  failed=1
fi

if [[ "$ffmpeg_kit_count" == "0" ]]; then
  echo "ERROR: no exported _ffmpeg_kit_* symbols found"
  failed=1
fi

if [[ "$ffprobe_kit_count" == "0" ]]; then
  echo "ERROR: no exported _ffprobe_kit_* symbols found"
  failed=1
fi

if [[ "$ffplay_kit_count" == "0" ]]; then
  echo "ERROR: no exported _ffplay_kit_* symbols found"
  failed=1
fi

exit "$failed"