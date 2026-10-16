#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
NATIVE_BIN_DIR="${FFMPEGKIT_NATIVE_BIN_DIR:-$REPO_ROOT/prebuilt/linux-x86_64/ffmpeg-video-linux-x86_64-static-small-gpl/bin}"
NATIVE_LIB_DIR="${FFMPEGKIT_NATIVE_LIB_DIR:-$REPO_ROOT/prebuilt/linux-x86_64/libraries/lib}"
export LD_LIBRARY_PATH="$NATIVE_LIB_DIR/pulseaudio:$NATIVE_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
FFMPEG="$NATIVE_BIN_DIR/ffmpeg"
FFPROBE="$NATIVE_BIN_DIR/ffprobe"
SOURCE="$SCRIPT_DIR/segment-1.ts"

if [[ ! -x "$FFMPEG" || ! -x "$FFPROBE" ]]; then
  echo "Native ffmpeg/ffprobe not executable under $NATIVE_BIN_DIR" >&2
  exit 1
fi
if [[ ! -s "$SOURCE" ]]; then
  echo "Validated source segment is missing: $SOURCE" >&2
  exit 1
fi

"$FFMPEG" -hide_banner -y -loglevel error -i "$SOURCE" \
  -map 0:v:0 -map 0:a:0 -c copy "$SCRIPT_DIR/same-h264-aac.mp4"
"$FFMPEG" -hide_banner -y -loglevel error -i "$SOURCE" \
  -map 0:v:0 -c copy -f mpegts "$SCRIPT_DIR/segment-video-only.ts"
"$FFMPEG" -hide_banner -y -loglevel error -i "$SOURCE" \
  -map 0:a:0 -c copy -f mpegts "$SCRIPT_DIR/segment-audio-only.ts"

for input in same-h264-aac.mp4 segment-video-only.ts segment-audio-only.ts; do
  case "$input" in
    same-h264-aac.mp4) maps=(-map 0:v:0 -map 0:a:0) ;;
    segment-video-only.ts) maps=(-map 0:v:0) ;;
    segment-audio-only.ts) maps=(-map 0:a:0) ;;
  esac
  "$FFPROBE" -v error \
    -show_entries format=format_name:stream=index,codec_name,profile,width,height,sample_rate,channels \
    -of json "$SCRIPT_DIR/$input" > "$SCRIPT_DIR/$input.native-probe.json"
  "$FFMPEG" -hide_banner -v error -xerror -i "$SCRIPT_DIR/$input" \
    "${maps[@]}" -f null -
done

python3 - "$SCRIPT_DIR" "$FFMPEG" "$FFPROBE" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

fixture_dir = Path(sys.argv[1])
ffmpeg, ffprobe = sys.argv[2:]
files = [
    ("same-h264-aac.mp4", ["h264", "aac"]),
    ("segment-video-only.ts", ["h264"]),
    ("segment-audio-only.ts", ["aac"]),
]

def version(executable):
    return subprocess.check_output([executable, "-version"], text=True).splitlines()[0]

controls = []
for name, expected_codecs in files:
    data = (fixture_dir / name).read_bytes()
    probe = json.loads((fixture_dir / f"{name}.native-probe.json").read_text())
    codecs = [stream["codec_name"] for stream in probe.get("streams", [])]
    if codecs != expected_codecs:
        raise SystemExit(f"{name}: expected codecs {expected_codecs}, got {codecs}")
    controls.append({
        "file": name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "expectedCodecs": expected_codecs,
        "probe": probe,
        "fullNativeDecode": "PASS (-xerror; ffmpeg -f null -)",
    })

manifest = {
    "source": {
        "file": "segment-1.ts",
        "bytes": (fixture_dir / "segment-1.ts").stat().st_size,
        "sha256": hashlib.sha256((fixture_dir / "segment-1.ts").read_bytes()).hexdigest(),
    },
    "nativeToolchain": {"ffmpeg": version(ffmpeg), "ffprobe": version(ffprobe)},
    "generation": "Native stream copy only; no codec re-encoding.",
    "controls": controls,
}
(fixture_dir / "stream-copy-controls-native-validation.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
PY
