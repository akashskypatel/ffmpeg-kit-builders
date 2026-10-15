#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
NATIVE_BIN_DIR="${FFMPEGKIT_NATIVE_BIN_DIR:-$REPO_ROOT/prebuilt/linux-x86_64/ffmpeg-video-linux-x86_64-static-small-gpl/bin}"
NATIVE_LIB_DIR="${FFMPEGKIT_NATIVE_LIB_DIR:-$REPO_ROOT/prebuilt/linux-x86_64/libraries/lib}"
export LD_LIBRARY_PATH="$NATIVE_LIB_DIR/pulseaudio:$NATIVE_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

FFMPEG="$NATIVE_BIN_DIR/ffmpeg"
FFPROBE="$NATIVE_BIN_DIR/ffprobe"
if [[ ! -x "$FFMPEG" || ! -x "$FFPROBE" ]]; then
  echo "Native ffmpeg/ffprobe not executable under $NATIVE_BIN_DIR" >&2
  exit 1
fi

rm -f "$SCRIPT_DIR"/segment-[123].ts "$SCRIPT_DIR/vod.m3u8" "$SCRIPT_DIR/live-template.ts"

COMMON_VIDEO=(
  -c:v libx264 -preset medium -crf 22 -profile:v baseline -level:v 3.0 -pix_fmt yuv420p
  -g 50 -keyint_min 50 -sc_threshold 0
  -force_key_frames 'expr:gte(t,n_forced*2)'
  -c:a aac -profile:a aac_low -b:a 128k -ar 48000 -ac 2
)

"$FFMPEG" -hide_banner -y -loglevel warning \
  -f lavfi -i 'testsrc2=size=320x240:rate=25:duration=6' \
  -f lavfi -i 'sine=frequency=880:sample_rate=48000:duration=6' \
  -map 0:v:0 -map 1:a:0 -t 6 "${COMMON_VIDEO[@]}" \
  -mpegts_copyts 1 -f hls -hls_time 2 -hls_playlist_type vod -hls_flags independent_segments \
  -start_number 1 -hls_segment_filename "$SCRIPT_DIR/segment-%d.ts" \
  "$SCRIPT_DIR/vod.m3u8"

"$FFMPEG" -hide_banner -y -loglevel warning \
  -f lavfi -i 'testsrc2=size=320x240:rate=25:duration=6' \
  -f lavfi -i 'sine=frequency=880:sample_rate=48000:duration=6' \
  -map 0:v:0 -map 1:a:0 -t 6 "${COMMON_VIDEO[@]}" \
  -mpegts_copyts 1 -mpegts_flags +resend_headers -f mpegts "$SCRIPT_DIR/live-template.ts"

python3 - "$SCRIPT_DIR" "$FFPROBE" <<'PY'
import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

fixture_dir = Path(sys.argv[1])
ffprobe = sys.argv[2]
playlist = fixture_dir / "vod.m3u8"
lines = playlist.read_text().splitlines()
segments = sorted(fixture_dir.glob("segment-[123].ts"))
if len(segments) != 3:
    raise SystemExit(f"expected three HLS segments, found {len(segments)}")

durations = {}
for segment in segments:
    output = subprocess.check_output([
        ffprobe, "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(segment),
    ], text=True)
    durations[segment.name] = float(output.strip())

target_duration = math.ceil(max(durations.values()))
updated = []
segment_index = 0
for line in lines:
    if line.startswith("#EXT-X-TARGETDURATION:"):
        line = f"#EXT-X-TARGETDURATION:{target_duration}"
    elif line.startswith("#EXTINF:"):
        name = segments[segment_index].name
        line = f"#EXTINF:{durations[name]:.6f},"
    elif line.startswith("segment-") and line.endswith(".ts"):
        segment_index += 1
    updated.append(line)

if segment_index != len(segments):
    raise SystemExit(f"playlist references {segment_index} segments, expected {len(segments)}")
playlist.write_text("\n".join(updated) + "\n")

# The Wasm packet-continuity test uses an independent native packet oracle.
source = fixture_dir / "live-template.ts"
arguments = [
    ffprobe, "-v", "error", "-show_packets", "-show_data_hash", "sha256",
    "-show_entries", "packet=stream_index,pts,dts,size,data_hash", "-of", "json",
    str(source),
]
reference = json.loads(subprocess.check_output(arguments, text=True))
reference.update({
    "sourceBytes": source.stat().st_size,
    "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "binary": ffprobe,
    "arguments": arguments[1:],
})
(fixture_dir / "live-template-packets.json").write_text(
    json.dumps(reference, indent=2) + "\n")
PY

cat "$SCRIPT_DIR/vod.m3u8"
