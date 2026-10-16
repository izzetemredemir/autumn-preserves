# tools/procedural

Deterministic (fixed-seed) generators for PNG art. Run from the repo root; needs numpy + Pillow.

## Forest ground tiles (ART-01)

```
python3 tools/procedural/tiles.py
```

Writes `game/assets/sprites/tiles/forest_tiles.png` (16x16 cells, 4 variants per row, rows = WildGen
ids 0 grass, 1 leaves, 2 dirt, 3 water, 4 path, 5 stone) and `forest_tiles.json` (id -> atlas cells).
Palette: `tools/palettes/autumn.hex`. Ordered (Bayer 4x4) dither only; tiles wrap seamlessly.
