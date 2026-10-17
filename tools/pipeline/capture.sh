#!/usr/bin/env bash
# Record gameplay deterministically with Godot's Movie Maker and encode crisp MP4 (+ optional GIF).
#   capture.sh <project_dir> <out_base> [--seconds 12] [--fps 30] [--scene res://scenes/main.tscn]
#              [--base 480x270] [--scale 4] [--gif] [--gif-scale 2] [--gif-fps 15] [--png] [--thumb-at 1]
#              [-- <extra user args>]
# Renders at the base resolution (pixel-exact), then upscales with nearest neighbour.
# --png: Movie Maker writes lossless PNG frames + WAV instead of MJPEG (no JPEG ringing on pixel edges; ~0.1 MB
#        per 480x270 frame in a temp dir while it runs).
# Extra args after -- reach the game via OS.get_cmdline_user_args() (e.g. --demo timeline.json).
set -euo pipefail
GODOT="${GODOT:-godot}"
PROJ="${1:?project dir}"; OUT="${2:?output base path without extension}"; shift 2
SECONDS_=12; FPS=30; SCENE=""; BASE="480x270"; SCALE=4; GIF=0; GIF_SCALE=2; GIF_FPS=15; PNG=0; THUMB_AT=1; EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) SECONDS_="$2"; shift 2 ;;
    --fps) FPS="$2"; shift 2 ;;
    --scene) SCENE="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --scale) SCALE="$2"; shift 2 ;;
    --gif) GIF=1; shift ;;
    --gif-scale) GIF_SCALE="$2"; shift 2 ;;
    --gif-fps) GIF_FPS="$2"; shift 2 ;;
    --png) PNG=1; shift ;;
    --thumb-at) THUMB_AT="$2"; shift 2 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "unknown arg $1"; exit 2 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp -d)"
FRAMES=$(( SECONDS_ * FPS ))
if [[ $PNG -eq 1 ]]; then MOVIE="$TMP/raw.png"; else MOVIE="$TMP/raw.avi"; fi
args=(--path "$PROJ" --resolution "$BASE" --write-movie "$MOVIE" --fixed-fps "$FPS" --quit-after "$FRAMES")
[[ -n "$SCENE" ]] && args+=("$SCENE")
"$GODOT" "${args[@]}" ${EXTRA[@]+-- "${EXTRA[@]}"} >"$TMP/godot.log" 2>&1 || { tail -20 "$TMP/godot.log"; exit 1; }
grep -E "SCRIPT ERROR|ERROR" "$TMP/godot.log" | head -5 || true
if [[ $PNG -eq 1 ]]; then
  IN_V=(-framerate "$FPS" -i "$TMP/raw%08d.png"); IN_A=(-i "$TMP/raw.wav")
else
  IN_V=(-i "$TMP/raw.avi"); IN_A=()
fi

VF="scale=iw*${SCALE}:ih*${SCALE}:flags=neighbor,format=yuv420p"
ffmpeg -y -hide_banner -loglevel error "${IN_V[@]}" ${IN_A[@]+"${IN_A[@]}"} -vf "$VF" -c:v libx264 -crf 16 -preset slow \
  -c:a aac -b:a 160k -movflags +faststart "$OUT.mp4"
echo "$OUT.mp4 ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT.mp4")s)"
ffmpeg -y -hide_banner -loglevel error "${IN_V[@]}" -ss "$THUMB_AT" -frames:v 1 -vf "scale=iw*${SCALE}:ih*${SCALE}:flags=neighbor" "$OUT.thumb.png"
echo "$OUT.thumb.png"

if [[ $GIF -eq 1 ]]; then
  GVF="fps=${GIF_FPS},scale=iw*${GIF_SCALE}:ih*${GIF_SCALE}:flags=neighbor"
  ffmpeg -y -hide_banner -loglevel error "${IN_V[@]}" -vf "$GVF,palettegen=max_colors=128:stats_mode=diff" "$TMP/pal.png"
  ffmpeg -y -hide_banner -loglevel error "${IN_V[@]}" -i "$TMP/pal.png" \
    -lavfi "$GVF [x]; [x][1:v] paletteuse=dither=none:diff_mode=rectangle" -loop 0 "$OUT.gif"
  echo "$OUT.gif ($(du -h "$OUT.gif" | cut -f1))"
fi
rm -rf "$TMP"
