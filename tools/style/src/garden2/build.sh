#!/usr/bin/env bash
# ART-GARDEN2: renders the hand-drawn living-garden sheets into game/assets/sprites/garden/, rewrites
# garden_props.json, the layout overlay and the mock, and the review contact sheet. Run from the repo root.
#   bash tools/style/src/garden2/build.sh
set -euo pipefail
SRC=tools/style/src/garden2
OUT=game/assets/sprites/garden
REVIEW=tools/style/review
mkdir -p "$OUT" "$REVIEW"
R() { python3 tools/pipeline/ascii_sprite.py render "$@" >/dev/null; }
# generated sources (parts composed in Python), then the renders
(cd "$SRC" && python3 gravel_gen.py && python3 truck_bed_gen.py && python3 coop_gen.py && python3 props_gen.py)
# drawn with their own ink rings (or too small for one)
for n in gravel truck_bed coop run_back run_front clothesline scarecrow bench bee smoke; do
  R "$SRC/$n.txt" --out "$OUT/garden_$n.png"
done
# fills only: the 1 px ink outline is added here
for n in truck hive crow rooster; do
  R "$SRC/$n.txt" --out "$OUT/garden_$n.png" --outline ink
done
R "$SRC/hen.txt" --out "$OUT/garden_hen.png" --outline ink \
  --variant "H=amber_600,h=bark_700,J=gold_300,T=bark_900" --variant "H=cream_100,h=cream_400,J=stone_300,T=stone_500"
R "$SRC/leafburst.txt" --out "$OUT/garden_leafburst.png" \
  --variant "L=leaf_red_500,D=leaf_red_700" --variant "L=gold_300,D=amber_600" --variant "L=amber_600,D=bark_700" \
  --variant "L=leaf_red_700,D=plum_900"
python3 "$SRC/garden2_layout.py"
# review sheet: the mock on top, the props x3, the critters and effects x6
python3 tools/pipeline/contact_sheet.py "$OUT/garden_truck.png" "$OUT/garden_truck_bed.png" "$OUT/garden_gravel.png" \
  "$OUT/garden_coop.png" "$OUT/garden_run_front.png" "$OUT/garden_hive.png" "$OUT/garden_clothesline.png" \
  "$OUT/garden_scarecrow.png" "$OUT/garden_bench.png" --out /tmp/garden2_art_a.png --scale 4 --cols 2 --labels --bg 83571e >/dev/null
python3 tools/pipeline/contact_sheet.py "$OUT/garden_hen.png" "$OUT/garden_rooster.png" "$OUT/garden_crow.png" \
  "$OUT/garden_bee.png" "$OUT/garden_smoke.png" "$OUT/garden_leafburst.png" --out /tmp/garden2_art_b.png --scale 6 --cols 2 \
  --labels --bg 83571e >/dev/null
python3 - "$REVIEW/garden2_mock.png" /tmp/garden2_art_a.png /tmp/garden2_art_b.png "$REVIEW/garden2_art.png" <<'PY'
import sys
from PIL import Image
parts = [Image.open(p).convert("RGB") for p in sys.argv[1:-1]]
out = Image.new("RGB", (max(p.width for p in parts), sum(p.height for p in parts)), (131, 87, 30))
y = 0
for p in parts:
    out.paste(p, (0, y))
    y += p.height
out.save(sys.argv[-1])
print(sys.argv[-1], out.size)
PY
