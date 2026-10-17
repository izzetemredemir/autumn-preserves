#!/usr/bin/env bash
# MARKET-LIVE · Renders the hand-drawn villager part sheets (tools/style/src/villagers/*.txt) to
# game/assets/sprites/villagers/<name>.png (frames in one row, no outline: the game outlines the whole figure),
# checks them against the palette, then writes the review sheet tools/style/review/villagers_v2.png (24 villagers).
#   bash tools/style/src/villagers/build.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"
SRC="tools/style/src/villagers"
OUT="game/assets/sprites/villagers"
mkdir -p "$OUT"
for f in "$SRC"/*.txt; do
  name="$(basename "$f" .txt)"
  python3 tools/pipeline/ascii_sprite.py render "$f" --out "$OUT/$name.png" >/dev/null
  python3 tools/pipeline/pixel_cleanup.py --check --in "$OUT/$name.png" --size any --palette tools/palettes/autumn.hex >/dev/null
done
echo "rendered $(ls "$SRC"/*.txt | wc -l | tr -d ' ') sheets into $OUT"
godot --headless --path game --import >/dev/null 2>&1 || true
godot --headless --path game -s res://scenes/market/villager_sheet.gd
