#!/usr/bin/env bash
# ART-MARKET: renders the hand-drawn market sheets into game/assets/sprites/market/, rewrites market_layout.json,
# the layout debug overlay and the review contact sheet (mock + background x3, stall + fiddler x3, small sheets x6). Run from the repo root.
# (--variant renders only the listed colourings, so the base colours are listed first.)
#   bash tools/style/src/market/build.sh
set -euo pipefail
SRC=tools/style/src/market
OUT=game/assets/sprites/market
REVIEW=tools/style/review
mkdir -p "$OUT" "$REVIEW"
python3 "$SRC/stall_finish.py" >/dev/null
python3 "$SRC/musician_gen.py" >/dev/null
for n in pigeon sparrow dog musician note; do
  python3 tools/pipeline/ascii_sprite.py render "$SRC/$n.txt" --out "$OUT/$n.png" --outline ink
done
python3 tools/pipeline/ascii_sprite.py render "$SRC/leaf.txt" --out "$OUT/leaf.png" \
  --variant "L=leaf_red_500,D=leaf_red_700" --variant "L=gold_300,D=amber_600" --variant "L=amber_600,D=bark_700" --variant "L=leaf_red_700,D=plum_900"
python3 tools/pipeline/ascii_sprite.py render "$SRC/bunting.txt" --out "$OUT/bunting.png" \
  --variant "L=leaf_peach_300,M=leaf_red_500,D=leaf_red_700" --variant "L=gold_200,M=gold_300,D=amber_600" --variant "L=olive_300,M=olive_600,D=olive_800" \
  --variant "L=cream_100,M=cream_100,D=cream_400"
python3 "$SRC/market_layout.py"
python3 tools/pipeline/contact_sheet.py "$REVIEW/market_mock.png" "$OUT/bg_market.png" --out /tmp/market_art_a.png --scale 3 --cols 1 --labels --max-px 1500 >/dev/null
python3 tools/pipeline/contact_sheet.py "$OUT/stall_granny.png" "$OUT/musician.png" --out /tmp/market_art_b.png --scale 3 --cols 2 --labels >/dev/null
python3 tools/pipeline/contact_sheet.py "$OUT/pigeon.png" "$OUT/dog.png" "$OUT/sparrow.png" "$OUT/note.png" "$OUT/leaf.png" \
  "$OUT/bunting.png" --out /tmp/market_art_c.png --scale 6 --cols 1 --labels >/dev/null
python3 - /tmp/market_art_a.png /tmp/market_art_b.png /tmp/market_art_c.png "$REVIEW/market_art.png" <<'PY'
import sys
from PIL import Image
parts = [Image.open(p).convert("RGB") for p in sys.argv[1:-1]]
out = Image.new("RGB", (max(p.width for p in parts), sum(p.height for p in parts)), parts[0].getpixel((0, 0)))
y = 0
for p in parts:
    out.paste(p, (0, y))
    y += p.height
out.save(sys.argv[-1])
print(sys.argv[-1], out.size)
PY
